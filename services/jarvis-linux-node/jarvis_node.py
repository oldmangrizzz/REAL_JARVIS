#!/usr/bin/env python3
"""
JARVIS Linux mesh node daemon.

Satisfies the CANON §5.1 "interconnected mesh" contract:
every host on which Jarvis runs maintains a registered,
heartbeating tunnel connection back to the echo host server
(JarvisHostTunnelServer, Swift, port 9443).

Wire protocol — reproduced bit-for-bit from
Jarvis/Shared/Sources/JarvisShared/TunnelCrypto.swift +
Jarvis/Shared/Sources/JarvisShared/TunnelModels.swift:

    TCP
    → newline-framed lines
      → JSON JarvisTransportPacket { origin, timestamp, payload }
        → payload = base64(ChaCha20-Poly1305 sealed box,
                           key = SHA-256(sharedSecret_utf8))
          → plaintext = JSON JarvisTunnelMessage
            { kind, registration?, command?, snapshot?,
              response?, push?, error? }

Dependencies: python3 (stdlib) + python3-cryptography (Debian pkg).
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import os
import platform
import signal
import socket
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

LOG = logging.getLogger("jarvis-node")


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


# ─────────────────────────────────────────── crypto ──

class TunnelCrypto:
    """Matches Swift JarvisTunnelCrypto exactly."""

    def __init__(self, shared_secret: str) -> None:
        key = hashlib.sha256(shared_secret.encode("utf-8")).digest()
        self.aead = ChaCha20Poly1305(key)

    def seal(self, obj: dict) -> str:
        plaintext = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        nonce = os.urandom(12)  # ChaChaPoly.Nonce is 12 bytes
        ct = self.aead.encrypt(nonce, plaintext, None)
        combined = nonce + ct  # Swift `combined` = nonce || ct || tag
        return base64.b64encode(combined).decode("ascii")

    def open(self, payload_b64: str) -> dict:
        combined = base64.b64decode(payload_b64)
        if len(combined) < 12 + 16:
            raise ValueError("combined payload too short")
        nonce, ct = combined[:12], combined[12:]
        plaintext = self.aead.decrypt(nonce, ct, None)
        return json.loads(plaintext.decode("utf-8"))


# ─────────────────────────────────────────── config ──

@dataclass
class NodeConfig:
    host_addr: str
    host_port: int
    shared_secret: str
    device_id: str
    device_name: str
    role: str
    app_version: str = "1218"
    heartbeat_interval_s: int = 30
    reconnect_min_s: int = 2
    reconnect_max_s: int = 60

    @classmethod
    def from_env(cls) -> "NodeConfig":
        host = os.environ.get("JARVIS_HOST_ADDR", "192.168.7.114")
        port = int(os.environ.get("JARVIS_HOST_PORT", "9443"))

        secret = os.environ.get("JARVIS_TUNNEL_SECRET", "").strip()
        if not secret:
            secret_path = os.environ.get(
                "JARVIS_TUNNEL_SECRET_FILE", "/etc/jarvis/tunnel.secret"
            )
            try:
                with open(secret_path, "r", encoding="utf-8") as f:
                    secret = f.read().strip()
            except FileNotFoundError as exc:
                raise SystemExit(f"jarvis-node: missing tunnel secret ({secret_path})") from exc
        if not secret:
            raise SystemExit("jarvis-node: empty JARVIS_TUNNEL_SECRET")

        # Stable machine ID.
        machine_id = ""
        for p in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    machine_id = f.read().strip()
                    break
            except FileNotFoundError:
                continue
        if not machine_id:
            machine_id = str(uuid.getnode())

        hostname = socket.gethostname()
        role = os.environ.get("JARVIS_NODE_ROLE", f"node-{hostname}").lower()

        return cls(
            host_addr=host,
            host_port=port,
            shared_secret=secret,
            device_id=machine_id,
            device_name=hostname,
            role=role,
        )


# ─────────────────────────────────────────── tunnel ──

class JarvisNode:
    def __init__(self, cfg: NodeConfig) -> None:
        self.cfg = cfg
        self.crypto = TunnelCrypto(cfg.shared_secret)
        self.origin = f"linux-node-{cfg.device_name}"
        self._stopping = asyncio.Event()

    def stop(self) -> None:
        self._stopping.set()

    # ----- framing -----

    def _wrap(self, message: dict) -> bytes:
        packet = {
            "origin": self.origin,
            "timestamp": iso_now(),
            "payload": self.crypto.seal(message),
        }
        line = json.dumps(packet, separators=(",", ":")).encode("utf-8") + b"\n"
        return line

    def _unwrap(self, line: bytes) -> dict:
        packet = json.loads(line.decode("utf-8"))
        return self.crypto.open(packet["payload"])

    # ----- messages -----

    def _registration_message(self) -> dict:
        return {
            "kind": "register",
            "registration": {
                "deviceID": self.cfg.device_id,
                "deviceName": self.cfg.device_name,
                "platform": "linux",
                "role": self.cfg.role,
                "appVersion": self.cfg.app_version,
            },
        }

    def _heartbeat_message(self) -> dict:
        return {"kind": "heartbeat"}

    # ----- one full session -----

    async def _session(self) -> None:
        LOG.info(
            "connecting to jarvis host tunnel %s:%s as %s",
            self.cfg.host_addr,
            self.cfg.host_port,
            self.cfg.role,
        )
        reader, writer = await asyncio.open_connection(
            self.cfg.host_addr, self.cfg.host_port
        )
        try:
            writer.write(self._wrap(self._registration_message()))
            await writer.drain()
            LOG.info("register sent")

            async def heartbeat_loop() -> None:
                while not self._stopping.is_set():
                    await asyncio.sleep(self.cfg.heartbeat_interval_s)
                    if self._stopping.is_set():
                        return
                    try:
                        writer.write(self._wrap(self._heartbeat_message()))
                        await writer.drain()
                        LOG.debug("heartbeat sent")
                    except (ConnectionError, BrokenPipeError):
                        return

            async def reader_loop() -> None:
                while not self._stopping.is_set():
                    line = await reader.readline()
                    if not line:
                        return
                    try:
                        msg = self._unwrap(line.rstrip(b"\n"))
                        kind = msg.get("kind", "unknown")
                        LOG.info("inbound kind=%s", kind)
                        if kind == "command":
                            await self._handle_command(writer, msg)
                    except Exception as exc:  # noqa: BLE001
                        LOG.warning("inbound decode failed: %s", exc)

            done, pending = await asyncio.wait(
                {asyncio.create_task(heartbeat_loop()), asyncio.create_task(reader_loop())},
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:  # noqa: BLE001
                pass

    async def _handle_command(self, writer: asyncio.StreamWriter, msg: dict) -> None:
        cmd = msg.get("command") or {}
        action = (cmd.get("action") or {}).get("kind") or cmd.get("action") or "ping"
        # Minimum viable responder — ack ping/status; everything else 'received'.
        response = {
            "kind": "response",
            "response": {
                "action": action if isinstance(action, dict) else {"kind": action},
                "spokenText": f"{self.cfg.device_name} ack {action}",
            },
        }
        try:
            writer.write(self._wrap(response))
            await writer.drain()
        except (ConnectionError, BrokenPipeError):
            return

    # ----- supervisor -----

    async def run_forever(self) -> None:
        delay = self.cfg.reconnect_min_s
        while not self._stopping.is_set():
            try:
                await self._session()
                delay = self.cfg.reconnect_min_s  # clean close → fast reconnect
            except asyncio.CancelledError:
                raise
            except (ConnectionRefusedError, OSError, asyncio.IncompleteReadError) as exc:
                LOG.warning("tunnel error: %s — retry in %ss", exc, delay)
                try:
                    await asyncio.wait_for(self._stopping.wait(), timeout=delay)
                    return
                except asyncio.TimeoutError:
                    pass
                delay = min(self.cfg.reconnect_max_s, delay * 2)
            except Exception as exc:  # noqa: BLE001
                LOG.error("unexpected: %s — retry in %ss", exc, delay)
                try:
                    await asyncio.wait_for(self._stopping.wait(), timeout=delay)
                    return
                except asyncio.TimeoutError:
                    pass
                delay = min(self.cfg.reconnect_max_s, delay * 2)


# ─────────────────────────────────────────── entry ──

def main() -> int:
    logging.basicConfig(
        level=os.environ.get("JARVIS_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )
    cfg = NodeConfig.from_env()
    LOG.info(
        "jarvis-node starting host=%s port=%s role=%s device_id=%s python=%s",
        cfg.host_addr,
        cfg.host_port,
        cfg.role,
        cfg.device_id[:8] + "…",
        platform.python_version(),
    )

    node = JarvisNode(cfg)
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, node.stop)

    try:
        loop.run_until_complete(node.run_forever())
    finally:
        loop.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
