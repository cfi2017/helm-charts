"""Attic watcher with authenticated, synchronous catch-up before scale-down."""
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import os
from pathlib import Path
import signal
import subprocess
import threading
import time
import urllib.request

LOG = logging.getLogger(__name__)


def credential(token_file):
    # Authenticate the control API without transmitting the Attic upload token.
    token = Path(token_file).read_bytes().strip()
    if not token:
        raise ValueError("Attic token must not be empty")
    return hashlib.sha256(token).hexdigest()


class Uploader:
    def __init__(self, endpoint, cache, token_file, runtime="/attic-runtime",
                 attic="/attic-bin/attic", nix="/nix/var/nix/profiles/default/bin/nix",
                 jobs=5, timeout=600, retry=30, reconcile=300, configure_nix=True):
        self.cache = "builder:" + cache
        self.token_file = token_file
        self.runtime = Path(runtime)
        self.attic, self.nix = attic, nix
        self.jobs, self.timeout, self.retry = jobs, timeout, retry
        self.reconcile = reconcile
        self.configure_nix = configure_nix
        self.state = threading.RLock()
        self.upload = threading.Lock()
        self.paused = False
        self.watcher = None
        self.watch_generation = 0
        self.synced_generation = -1
        self.last_sync = 0
        self.stop = threading.Event()
        self.environment = dict(os.environ, XDG_CONFIG_HOME=str(self.runtime),
                                NIX_REMOTE="local", NIX_CONFIG="build-users-group =\n")
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.runtime.chmod(0o700)
        config_dir = self.runtime / "attic"
        config_dir.mkdir(exist_ok=True, mode=0o700)
        config = ('default-server = "builder"\n[servers.builder]\n'
                  f'endpoint = {json.dumps(endpoint)}\n'
                  f'token-file = {json.dumps(str(config_dir / "token"))}\n')
        config_file = config_dir / "config.toml"
        config_file.write_text(config)
        config_file.chmod(0o600)
        self.refresh_token()

    def refresh_token(self):
        token = self.runtime / "attic/token"
        temporary = token.with_suffix(".tmp")
        content = Path(self.token_file).read_bytes().strip()
        if not content:
            raise ValueError("Attic token must not be empty")
        temporary.write_bytes(content)
        temporary.chmod(0o600)
        temporary.replace(token)

    @staticmethod
    def remaining(deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Attic upload deadline exceeded")
        return remaining

    def run(self, arguments, deadline, **kwargs):
        environment = kwargs.pop("env", self.environment)
        return subprocess.run(arguments, env=environment, check=True,
                              timeout=self.remaining(deadline), **kwargs)

    def start_watch(self):
        # Caller holds state. Starting a process doesn't wait for remote IO.
        if self.watcher is None or self.watcher.poll() is not None:
            self.refresh_token()
            self.watcher = subprocess.Popen(
                [self.attic, "watch-store", self.cache, "--jobs", str(self.jobs)],
                env=self.environment,
            )
            self.watch_generation += 1

    def stop_watch(self, deadline):
        if self.watcher is not None:
            self.watcher.terminate()
            try:
                self.watcher.wait(timeout=min(10, self.remaining(deadline)))
            except (subprocess.TimeoutExpired, TimeoutError):
                self.watcher.kill()
                self.watcher.wait()
            self.watcher = None

    def catch_up(self, deadline):
        self.refresh_token()
        if self.configure_nix:
            # Let Attic discover the cache's public key, substituter and netrc.
            # Stage its non-atomic writes away from the builder's live config.
            staging = self.runtime / "configure"
            (staging / "attic").mkdir(parents=True, exist_ok=True, mode=0o700)
            staged_client = staging / "attic/config.toml"
            staged_client.write_bytes((self.runtime / "attic/config.toml").read_bytes())
            staged_client.chmod(0o600)
            (staging / "nix").mkdir(exist_ok=True, mode=0o700)
            staged_nix = staging / "nix/nix.conf"
            staged_nix.unlink(missing_ok=True)
            self.run([self.attic, "use", self.cache], deadline,
                     env=dict(self.environment, XDG_CONFIG_HOME=str(staging)))
            nix_config = self.runtime / "nix/nix.conf"
            nix_config.parent.mkdir(exist_ok=True, mode=0o700)
            netrc = nix_config.parent / "netrc"
            temporary = netrc.with_suffix(".tmp")
            temporary.write_bytes((staging / "nix/netrc").read_bytes())
            temporary.chmod(0o600)
            temporary.replace(netrc)
            content = staged_nix.read_text().replace(
                "substituters =", "extra-substituters ="
            ).replace("trusted-public-keys =", "extra-trusted-public-keys =").replace(
                str(staging / "nix/netrc"), str(netrc)
            )
            temporary = nix_config.with_suffix(".tmp")
            temporary.write_text(content)
            temporary.chmod(0o600)
            temporary.replace(nix_config)
        paths = self.run([self.nix, "--extra-experimental-features", "nix-command",
                          "path-info", "--all"], deadline,
                         stdout=subprocess.PIPE).stdout
        self.run([self.attic, "push", self.cache, "--stdin", "--jobs", str(self.jobs)],
                 deadline, input=paths)

    def resume(self):
        with self.state:
            self.paused = False
            self.start_watch()

    def drain(self):
        deadline = time.monotonic() + self.timeout
        if not self.upload.acquire(timeout=self.remaining(deadline)):
            raise TimeoutError("Timed out waiting for Attic catch-up")
        try:
            # A new SSH admission invalidates this snapshot at the proxy, which
            # keeps the worker running and resumes the watcher after this drain.
            with self.state:
                if self.paused:
                    return
                self.paused = True
                self.stop_watch(deadline)
                try:
                    self.catch_up(deadline)
                except Exception:
                    self.paused = False
                    self.start_watch()
                    raise
        finally:
            self.upload.release()

    def supervise(self):
        while not self.stop.is_set():
            try:
                with self.state:
                    if not self.paused:
                        if self.watcher is None or self.watcher.poll() is not None:
                            self.start_watch()
                    needs_sync = (self.synced_generation != self.watch_generation
                                  or time.monotonic() - self.last_sync >= self.reconcile)
                if needs_sync:
                    with self.upload:
                        with self.state:
                            paused = self.paused
                            generation = self.watch_generation
                        if not paused:
                            self.catch_up(time.monotonic() + self.timeout)
                            with self.state:
                                self.synced_generation = generation
                                self.last_sync = time.monotonic()
            except Exception:
                # A cache outage must not discard pending paths or stop builds.
                LOG.exception("Attic catch-up failed; will retry and keep worker running")
            self.stop.wait(self.retry)

    def close(self):
        self.stop.set()
        with self.state:
            self.stop_watch(time.monotonic() + 10)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.path == "/health" else 404)
        self.end_headers()

    def do_POST(self):
        uploader = self.server.uploader
        expected = "Bearer " + credential(uploader.token_file)
        if not hmac.compare_digest(self.headers.get("Authorization", ""), expected):
            self.send_error(401)
            return
        if self.path not in ("/drain", "/resume"):
            self.send_error(404)
            return
        try:
            getattr(uploader, self.path[1:])()
        except Exception:
            LOG.exception("Attic control request failed")
            self.send_error(503, "Attic upload incomplete")
            return
        self.send_response(200)
        body = json.dumps({"operation": self.path[1:], "complete": True}).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--drain", action="store_true")
    args = parser.parse_args()
    token_file = "/attic-auth/token"
    if args.drain:
        request = urllib.request.Request(
            "http://127.0.0.1:8090/drain", data=b"",
            headers={"Authorization": "Bearer " + credential(token_file)},
        )
        with urllib.request.urlopen(request, timeout=int(os.environ["DRAIN_TIMEOUT"]) + 5):
            return
    uploader = Uploader(
        os.environ["ATTIC_ENDPOINT"], os.environ["ATTIC_CACHE"], token_file,
        jobs=int(os.environ["ATTIC_JOBS"]), timeout=int(os.environ["DRAIN_TIMEOUT"]),
        retry=int(os.environ["RETRY_SECONDS"]),
        reconcile=int(os.environ.get("CATCH_UP_INTERVAL", "300")),
        configure_nix=os.environ["CONFIGURE_NIX"] == "true",
    )
    server = ThreadingHTTPServer(("0.0.0.0", 8090), Handler)
    server.daemon_threads = True
    server.uploader = uploader
    supervisor = threading.Thread(target=uploader.supervise, daemon=True)
    supervisor.start()
    def terminate(*_):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    try:
        server.serve_forever()
    finally:
        uploader.close()
        server.server_close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
