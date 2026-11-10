"""Exercise real TCP streams and scaler failures without a Kubernetes cluster."""
import asyncio
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import unittest

source = Path(__file__).resolve().parents[3] / "charts/nix-builder/files/proxy.py"
spec = importlib.util.spec_from_file_location("proxy", source)
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class Scaler:
    def __init__(self):
        self.calls = []
        self.fail = False

    def set_replicas(self, replicas):
        if self.fail:
            raise OSError("API unavailable")
        self.calls.append(replicas)


class ProxyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.scaler = Scaler()
        self.activator = proxy.Activator(self.scaler, "127.0.0.1", idle=0.01)
        self.servers = []

    async def asyncTearDown(self):
        for server in self.servers:
            server.close()
            await server.wait_closed()

    async def listen(self, handler):
        server = await asyncio.start_server(handler, "127.0.0.1", 0)
        self.servers.append(server)
        return server.sockets[0].getsockname()[1]

    async def test_wakes_for_session_preserves_half_close_then_sleeps(self):
        async def backend(reader, writer):
            data = await reader.read()
            writer.write(b"result:" + data)
            await writer.drain()
            writer.close()
            await writer.wait_closed()

        self.activator.port = await self.listen(backend)
        port = await self.listen(self.activator.handle)
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        writer.write(b"derivation")
        await writer.drain()
        writer.write_eof()
        self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"result:derivation")
        writer.close()
        await writer.wait_closed()
        await asyncio.sleep(0.05)
        await self.activator.idle_check()
        self.assertEqual(self.scaler.calls, [1, 0])
        self.assertEqual(self.activator.active, 0)

    async def test_holds_connection_until_cold_worker_starts(self):
        reservation = await asyncio.start_server(lambda r, w: None, "127.0.0.1", 0)
        self.activator.port = reservation.sockets[0].getsockname()[1]
        reservation.close()
        await reservation.wait_closed()
        port = await self.listen(self.activator.handle)
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        writer.write(b"queued")
        await writer.drain()
        await asyncio.sleep(0.05)
        self.assertEqual(self.scaler.calls, [1])
        self.assertEqual(self.activator.active, 1)
        await self.activator.idle_check()
        self.assertEqual(self.scaler.calls, [1])

        async def backend(upstream, downstream):
            downstream.write(await upstream.read(6))
            await downstream.drain()
            downstream.close()
            await downstream.wait_closed()

        server = await asyncio.start_server(backend, "127.0.0.1", self.activator.port)
        self.servers.append(server)
        self.assertEqual(await asyncio.wait_for(reader.read(6), 3), b"queued")
        writer.close()
        await writer.wait_closed()
        await asyncio.sleep(0.01)

    async def test_live_sessions_prevent_downscale_even_when_idle(self):
        self.activator.active = 2
        self.activator.last_close = 0
        await self.activator.idle_check()
        self.assertEqual(self.scaler.calls, [])

    async def test_failed_downscale_is_retried(self):
        self.activator.last_close = 0
        self.scaler.fail = True
        with self.assertRaises(OSError):
            await self.activator.idle_check()
        self.assertIsNone(self.activator.desired)
        self.scaler.fail = False
        await self.activator.idle_check()
        self.assertEqual(self.scaler.calls, [0])

    async def test_startup_timeout_releases_connection_counter(self):
        self.activator.startup_timeout = 0
        # Allocate and close a port so the worker is unavailable.
        server = await asyncio.start_server(lambda r, w: None, "127.0.0.1", 0)
        self.activator.port = server.sockets[0].getsockname()[1]
        server.close()
        await server.wait_closed()
        port = await self.listen(self.activator.handle)
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        with self.assertLogs("proxy", level="ERROR"):
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
            await asyncio.sleep(0.01)
        writer.close()
        await writer.wait_closed()
        self.assertEqual(self.activator.active, 0)

    async def test_failed_wakeup_releases_connection_counter(self):
        self.scaler.fail = True
        port = await self.listen(self.activator.handle)
        with self.assertLogs("proxy", level="ERROR"):
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
            await asyncio.sleep(0.01)
        writer.close()
        await writer.wait_closed()
        self.assertEqual(self.activator.active, 0)

    async def test_admission_and_downscale_share_lock(self):
        self.activator.last_close = 0
        async with self.activator.lock:
            task = asyncio.create_task(self.activator.idle_check())
            await asyncio.sleep(0)
            self.activator.active = 1
        await task
        self.assertEqual(self.scaler.calls, [])

    async def test_repeated_scale_calls_are_coalesced(self):
        await self.activator.scale(1)
        await self.activator.scale(1)
        await self.activator.scale(0)
        self.assertEqual(self.scaler.calls, [1, 0])


if __name__ == "__main__":
    unittest.main()
