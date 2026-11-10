"""Test catch-up, failed drains and authenticated control over real HTTP."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
files = Path(__file__).resolve().parents[3] / "charts/nix-builder/files"


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, files / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


upload = module("upload", "attic-uploader.py")
proxy = module("proxy", "proxy.py")


class FakeWatcher:
    def __init__(self, events):
        self.events = events
        self.dead = False

    def poll(self):
        return 0 if self.dead else None

    def terminate(self):
        self.events.append("stop-watch")
        self.dead = True

    def wait(self, timeout=None):
        return 0


class UploaderTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.token = root / "token"
        self.token.write_text("test-secret\n")
        self.events = []
        self.uploader = upload.Uploader(
            "https://cache.example.com/", "efi-nixos", str(self.token),
            runtime=str(root / "runtime"), timeout=1, retry=0.01,
        )
        self.popen = patch.object(upload.subprocess, "Popen", side_effect=self.watch).start()
        self.addCleanup(patch.stopall)
        self.addCleanup(self.uploader.close)

    def watch(self, *args, **kwargs):
        self.events.append("start-watch")
        return FakeWatcher(self.events)

    def test_credentials_are_private_and_not_embedded_in_config(self):
        config = self.uploader.runtime / "attic/config.toml"
        token = self.uploader.runtime / "attic/token"
        self.assertNotIn("test-secret", config.read_text())
        self.assertEqual(token.read_text(), "test-secret")
        self.assertEqual(token.stat().st_mode & 0o777, 0o600)
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)

    def test_final_snapshot_runs_after_watcher_stops(self):
        self.uploader.resume()
        self.uploader.catch_up = lambda deadline: self.events.append("push-all-paths")
        self.uploader.drain()
        self.assertEqual(self.events, ["start-watch", "stop-watch", "push-all-paths"])
        self.assertTrue(self.uploader.paused)
        self.assertIsNone(self.uploader.watcher)
        self.uploader.resume()
        self.assertFalse(self.uploader.paused)
        self.assertEqual(self.events[-1], "start-watch")

    def test_failed_push_resumes_watching_and_can_retry(self):
        self.uploader.resume()
        self.uploader.catch_up = Mock(side_effect=OSError("cache unavailable"))
        with self.assertRaises(OSError):
            self.uploader.drain()
        self.assertFalse(self.uploader.paused)
        self.assertIsNotNone(self.uploader.watcher)
        self.uploader.catch_up.side_effect = None
        self.uploader.drain()
        self.assertTrue(self.uploader.paused)

    def test_busy_startup_catchup_has_bounded_drain_wait(self):
        self.uploader.timeout = 0.02
        self.uploader.upload.acquire()
        try:
            with self.assertRaises(TimeoutError):
                self.uploader.drain()
            self.assertFalse(self.uploader.paused)
        finally:
            self.uploader.upload.release()

    def test_startup_catchup_retries_without_stopping_the_watcher(self):
        attempts = []

        def catch_up(deadline):
            attempts.append(1)
            if len(attempts) == 1:
                raise OSError("temporary outage")
            self.uploader.stop.set()

        self.uploader.catch_up = catch_up
        with self.assertLogs("upload", level="ERROR"):
            self.uploader.supervise()
        self.assertEqual(len(attempts), 2)
        self.assertEqual(self.events, ["start-watch"])

    def test_failed_drain_reconciles_again_even_if_restarted_watcher_is_alive(self):
        self.uploader.resume()
        self.uploader.synced_generation = self.uploader.watch_generation
        self.uploader.last_sync = time.monotonic()
        self.uploader.catch_up = Mock(side_effect=OSError("cache down"))
        with self.assertRaises(OSError):
            self.uploader.drain()
        attempts = []

        def catch_up(deadline):
            attempts.append(1)
            self.uploader.stop.set()

        self.uploader.catch_up = catch_up
        self.uploader.supervise()
        self.assertEqual(attempts, [1])

    def test_periodic_catchup_recovers_missed_watch_events(self):
        self.uploader.resume()
        self.uploader.synced_generation = self.uploader.watch_generation
        self.uploader.last_sync = 0
        self.uploader.catch_up = Mock(side_effect=lambda _: self.uploader.stop.set())
        self.uploader.supervise()
        self.uploader.catch_up.assert_called_once()

    def test_catchup_pushes_all_valid_paths_and_extends_nix_configuration(self):
        paths = b"/nix/store/path-one\n/nix/store/path-two\n"
        received = []

        def run(arguments, **kwargs):
            if "use" in arguments:
                staging = Path(kwargs["env"]["XDG_CONFIG_HOME"])
                (staging / "nix/nix.conf").write_text(
                    "substituters = https://cache.example.com/efi-nixos https://cache.nixos.org\n"
                    "trusted-public-keys = efi-nixos:key\n"
                    f"netrc-file = {staging}/nix/netrc\n"
                )
                (staging / "nix/netrc").write_text("machine cache.example.com password test-secret")
                return subprocess.CompletedProcess(arguments, 0)
            if "path-info" in arguments:
                return subprocess.CompletedProcess(arguments, 0, stdout=paths)
            if "push" in arguments:
                received.append(kwargs["input"])
                return subprocess.CompletedProcess(arguments, 0)
            self.fail("unexpected command")

        with patch.object(upload.subprocess, "run", side_effect=run):
            self.uploader.catch_up(time.monotonic() + 1)
        self.assertEqual(received, [paths])
        config = (self.uploader.runtime / "nix/nix.conf").read_text()
        self.assertIn("extra-substituters =", config)
        self.assertIn("extra-trusted-public-keys =", config)
        self.assertNotIn("test-secret", config)
        self.assertNotIn("/configure/", config)
        netrc = self.uploader.runtime / "nix/netrc"
        self.assertEqual(netrc.stat().st_mode & 0o777, 0o600)
        self.assertIn("test-secret", netrc.read_text())

    def test_repeated_drain_does_not_reupload_during_pre_stop(self):
        self.uploader.catch_up = Mock()
        self.uploader.drain()
        self.uploader.drain()
        self.uploader.catch_up.assert_called_once()

    def test_failed_config_refresh_preserves_live_builder_config(self):
        config = self.uploader.runtime / "nix/nix.conf"
        config.parent.mkdir()
        config.write_text("extra-substituters = https://previous-cache.example.com\n")
        with patch.object(upload.subprocess, "run", side_effect=OSError("cache down")):
            with self.assertRaises(OSError):
                self.uploader.catch_up(time.monotonic() + 1)
        self.assertEqual(config.read_text(), "extra-substituters = https://previous-cache.example.com\n")

    def test_failed_store_query_never_acknowledges_a_drain(self):
        self.uploader.configure_nix = False
        with patch.object(upload.subprocess, "run", side_effect=OSError("store unavailable")):
            with self.assertRaises(OSError):
                self.uploader.drain()
        self.assertFalse(self.uploader.paused)


class ControlTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.token = Path(self.directory.name) / "token"
        self.token.write_text("only-a-test-token\n")
        self.server = upload.ThreadingHTTPServer(("127.0.0.1", 0), upload.Handler)
        self.server.uploader = Mock(token_file=str(self.token))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = "http://127.0.0.1:" + str(self.server.server_port)
        self.client = proxy.HTTPUploader(self.url, str(self.token), timeout=1)

    def test_authenticated_drain_and_resume(self):
        self.client.drain()
        self.client.resume()
        self.server.uploader.drain.assert_called_once()
        self.server.uploader.resume.assert_called_once()

    def test_invalid_auth_cannot_pause_uploads(self):
        request = urllib.request.Request(self.url + "/drain", data=b"",
                                         headers={"Authorization": "Bearer wrong"})
        with self.assertRaises(urllib.error.HTTPError) as failure:
            urllib.request.urlopen(request)
        self.assertEqual(failure.exception.code, 401)
        failure.exception.close()
        self.server.uploader.drain.assert_not_called()

    def test_control_credential_tracks_rotated_secret(self):
        old = upload.credential(str(self.token))
        self.token.write_text("rotated-token")
        self.assertNotEqual(old, upload.credential(str(self.token)))
        self.client.drain()
        self.server.uploader.drain.assert_called_once()

    def test_empty_token_is_not_a_public_control_credential(self):
        self.token.write_text("\n")
        with self.assertRaises(ValueError):
            self.client.drain()
        self.server.uploader.drain.assert_not_called()

    def test_upload_failure_is_not_a_successful_http_acknowledgment(self):
        self.server.uploader.drain.side_effect = OSError("cache offline")
        with self.assertLogs("upload", level="ERROR"):
            with self.assertRaises(urllib.error.HTTPError) as failure:
                self.client.drain()
        self.assertEqual(failure.exception.code, 503)
        failure.exception.close()

    def test_health_check_does_not_trigger_uploads(self):
        with urllib.request.urlopen(self.url + "/health") as response:
            self.assertEqual(response.status, 200)
        self.server.uploader.drain.assert_not_called()
        self.server.uploader.resume.assert_not_called()

    def test_missing_drain_acknowledgment_is_rejected(self):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = b'{}'
        with patch.object(proxy.urllib.request, "urlopen", return_value=response):
            with self.assertRaises(RuntimeError):
                self.client.drain()


if __name__ == "__main__":
    unittest.main()
