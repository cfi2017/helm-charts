"""Connection-aware TCP activator; only this process owns worker replica count."""
import asyncio
import contextlib
import hashlib
import json
import logging
import os
from pathlib import Path
import ssl
import time
import urllib.request

LOG = logging.getLogger(__name__)
SA = Path("/var/run/secrets/kubernetes.io/serviceaccount")


class KubernetesScaler:
    def __init__(self):
        namespace = os.environ["NAMESPACE"]
        deployment = os.environ["DEPLOYMENT"]
        self.url = (
            "https://kubernetes.default.svc/apis/apps/v1/namespaces/"
            f"{namespace}/deployments/{deployment}/scale"
        )
        self.context = ssl.create_default_context(cafile=str(SA / "ca.crt"))

    def get_replicas(self):
        request = urllib.request.Request(
            self.url, headers={"Authorization": "Bearer " + (SA / "token").read_text().strip()}
        )
        with urllib.request.urlopen(request, context=self.context, timeout=10) as response:
            return json.load(response)["spec"]["replicas"]

    def set_replicas(self, replicas):
        # Read for every call: projected service-account tokens rotate.
        request = urllib.request.Request(
            self.url,
            data=json.dumps({"spec": {"replicas": replicas}}).encode(),
            headers={
                "Authorization": "Bearer " + (SA / "token").read_text().strip(),
                "Content-Type": "application/merge-patch+json",
            },
            method="PATCH",
        )
        with urllib.request.urlopen(request, context=self.context, timeout=10) as response:
            response.read()


class HTTPUploader:
    def __init__(self, url, token_file="/attic-auth/token", timeout=600):
        self.url, self.token_file, self.timeout = url.rstrip("/"), token_file, timeout

    def call(self, operation):
        token = Path(self.token_file).read_bytes().strip()
        if not token:
            raise ValueError("Attic token must not be empty")
        credential = hashlib.sha256(token).hexdigest()
        request = urllib.request.Request(
            self.url + "/" + operation, data=b"",
            headers={"Authorization": "Bearer " + credential},
        )
        with urllib.request.urlopen(request, timeout=self.timeout + 5) as response:
            if json.load(response) != {"operation": operation, "complete": True}:
                raise RuntimeError("Uploader did not confirm " + operation)

    def drain(self):
        self.call("drain")

    def resume(self):
        self.call("resume")


class Activator:
    def __init__(self, scaler, host, port=2222, idle=300, startup_timeout=600, uploader=None):
        self.scaler = scaler
        self.host, self.port = host, port
        self.idle, self.startup_timeout = idle, startup_timeout
        self.active = 0
        self.last_close = time.monotonic()
        self.lock = asyncio.Lock()
        self.desired = None
        self.uploader = uploader
        self.draining = False
        self.generation = 0

    async def scale(self, replicas):
        if self.desired != replicas:
            await asyncio.to_thread(self.scaler.set_replicas, replicas)
            self.desired = replicas
            LOG.info("worker replicas = %s", replicas)

    async def idle_check(self):
        async with self.lock:
            if (self.active != 0 or self.desired == 0 or self.draining
                    or time.monotonic() - self.last_close < self.idle):
                return
            if not self.uploader:
                await self.scale(0)
                return
            self.draining = True
            generation = self.generation
        try:
            try:
                # Let new builds proceed while uploads finish. Any admission
                # invalidates this snapshot and cancels this scale-down attempt.
                await asyncio.to_thread(self.uploader.drain)
                async with self.lock:
                    stale = self.active != 0 or self.generation != generation
                    if not stale:
                        await self.scale(0)
            except Exception:
                await asyncio.to_thread(self.uploader.resume)
                raise
            if stale:
                await asyncio.to_thread(self.uploader.resume)
        finally:
            async with self.lock:
                self.draining = False

    async def reap(self):
        while True:
            await asyncio.sleep(1)
            try:
                await self.idle_check()
            except Exception:
                LOG.exception("cannot scale idle worker; will retry")

    async def connect(self):
        deadline = time.monotonic() + self.startup_timeout
        while True:
            try:
                return await asyncio.wait_for(
                    asyncio.open_connection(self.host, self.port), timeout=2
                )
            except (OSError, asyncio.TimeoutError):
                if time.monotonic() >= deadline:
                    raise TimeoutError("worker did not become ready")
                await asyncio.sleep(1)

    @staticmethod
    async def pipe(reader, writer):
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
        if writer.can_write_eof():
            writer.write_eof()

    async def handle(self, reader, writer):
        backend = None
        counted = False
        tasks = []
        try:
            # The same lock guards admission and the final scale-down decision.
            async with self.lock:
                self.active += 1
                self.generation += 1
                counted = True
                await self.scale(1)
                draining = self.draining
            upstream, backend = await self.connect()
            if self.uploader and not draining:
                await asyncio.to_thread(self.uploader.resume)
            tasks = [
                asyncio.create_task(self.pipe(reader, backend)),
                asyncio.create_task(self.pipe(upstream, writer)),
            ]
            # Preserve TCP half-close so final build output reaches the client.
            await asyncio.gather(*tasks)
        except Exception:
            LOG.exception("SSH session failed")
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            for stream in (backend, writer):
                if stream:
                    stream.close()
                    with contextlib.suppress(Exception):
                        await stream.wait_closed()
            if counted:
                async with self.lock:
                    self.active -= 1
                    self.last_close = time.monotonic()


async def main():
    Path("/tmp/ready").unlink(missing_ok=True)
    uploader = None
    if os.environ.get("UPLOADER_URL"):
        uploader = HTTPUploader(os.environ["UPLOADER_URL"],
                                timeout=int(os.environ["DRAIN_TIMEOUT"]))
    activator = Activator(
        KubernetesScaler(), os.environ["BACKEND_HOST"],
        idle=int(os.environ["IDLE_SECONDS"]),
        startup_timeout=int(os.environ["STARTUP_TIMEOUT_SECONDS"]),
        uploader=uploader,
    )
    if uploader:
        # A restarted proxy must not try to drain a worker already at zero.
        activator.desired = await asyncio.to_thread(activator.scaler.get_replicas)
    server = await asyncio.start_server(activator.handle, "0.0.0.0", 2222)
    Path("/tmp/ready").touch()
    async with server:
        await asyncio.gather(server.serve_forever(), activator.reap())


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
