#!/usr/bin/env python3
"""
mesh-display-agent — receives POSTs from Jarvis MeshDisplayDispatcher and drives
a local chromium --kiosk window. Runs on any Linux node in the mesh (alpha/beta/foxtrot)
that has a physical display and should act as a Jarvis display endpoint.

POST /display
  Headers:
    Authorization: Bearer $MESH_DISPLAY_SECRET
    Content-Type: application/json
  Body:
    { "display": "<id>", "action": "show|clear|dashboard|hud|telemetry",
      "parameters": { "url": "...", "content": "..." },
      "ts": "...", "authority": "..." }

Responses: 200 OK on success, 401 on bad bearer, 4xx/5xx on failure.
"""
from __future__ import annotations

import json
import logging
import os
import signal
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

LOG = logging.getLogger("mesh-display-agent")
LISTEN_HOST = os.environ.get("MESH_DISPLAY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("MESH_DISPLAY_PORT", "9455"))
SECRET = os.environ.get("MESH_DISPLAY_SECRET", "")
BROWSER = os.environ.get("MESH_DISPLAY_BROWSER", "chromium")
DEFAULT_URL = os.environ.get("MESH_DISPLAY_DEFAULT_URL", "about:blank")

# URL allowlist — restrict to trusted domains (HTTPS + TLD matching).
ALLOWED_HOSTS = {
    "grizzlymedicine.icu",
    "localhost",
    "127.0.0.1",
    "::1",
}
# Parse env var to add custom hosts
_custom_hosts = os.environ.get("JARVIS_DISPLAY_ALLOWED_HOSTS", "")
if _custom_hosts:
    ALLOWED_HOSTS.update(h.strip() for h in _custom_hosts.split(",") if h.strip())

_browser_proc: subprocess.Popen | None = None


def launch_kiosk(url: str) -> None:
    global _browser_proc
    if _browser_proc and _browser_proc.poll() is None:
        try:
            _browser_proc.terminate()
            _browser_proc.wait(timeout=3)
        except Exception:
            try:
                _browser_proc.kill()
            except Exception:
                pass
    LOG.info("launching kiosk: %s %s", BROWSER, url)
    _browser_proc = subprocess.Popen(
        [BROWSER, "--kiosk", "--noerrdialogs", "--disable-infobars", url],
        env={**os.environ, "DISPLAY": os.environ.get("DISPLAY", ":0")},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def clear_display() -> None:
    global _browser_proc
    if _browser_proc and _browser_proc.poll() is None:
        try:
            _browser_proc.terminate()
            _browser_proc.wait(timeout=3)
        except Exception:
            try:
                _browser_proc.kill()
            except Exception:
                pass
    _browser_proc = None


def _is_url_allowed(url: str) -> bool:
    """Validate URL matches allowlist: HTTPS + allowed host."""
    # Allow about:blank and other special schemes
    if url.startswith("about:"):
        return True
    try:
        parsed = urlparse(url)
        if parsed.scheme and parsed.scheme not in ("http", "https"):
            LOG.warning("rejecting non-http(s) URL: %s", url)
            return False
        # HTTPS required for production (HTTP allowed for localhost dev)
        host = parsed.hostname or ""
        if parsed.scheme == "http" and host not in ("127.0.0.1", "localhost"):
            LOG.warning("rejecting non-https remote URL: %s", url)
            return False
        # Check allowed hosts (exact match or subdomain match for *.grizzlymedicine.icu)
        for allowed in ALLOWED_HOSTS:
            if host == allowed or host.endswith("." + allowed):
                return True
        LOG.warning("rejecting URL from disallowed host: %s (allowed: %s)", host, ALLOWED_HOSTS)
        return False
    except Exception as exc:
        LOG.warning("failed to validate URL %s: %s", url, exc)
        return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        LOG.info("%s - %s", self.address_string(), fmt % args)

    def _deny(self, code: int, msg: str) -> None:
        payload = json.dumps({"ok": False, "error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _ok(self, data: dict) -> None:
        payload = json.dumps({"ok": True, **data}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._ok({"status": "alive"})
            return
        self._deny(404, "not found")

    def do_POST(self) -> None:
        if self.path != "/display":
            self._deny(404, "not found")
            return
        if SECRET:
            auth = self.headers.get("Authorization", "")
            if auth != f"Bearer {SECRET}":
                self._deny(401, "unauthorized")
                return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode() or "{}")
        except Exception:
            self._deny(400, "invalid json")
            return

        action = str(body.get("action", "")).lower()
        params = body.get("parameters") or {}
        url = params.get("url") or params.get("content") or DEFAULT_URL

        # Validate URL before launching
        if not _is_url_allowed(url):
            self._deny(403, f"URL not allowed: {url}")
            return

        try:
            if action in ("clear", "off", "stop"):
                clear_display()
                self._ok({"action": "cleared"})
                return
            if action in ("show", "dashboard", "hud", "telemetry", ""):
                launch_kiosk(url)
                self._ok({"action": "launched", "url": url})
                return
            self._deny(400, f"unknown action: {action}")
        except Exception as exc:
            LOG.exception("dispatch failed")
            self._deny(500, f"dispatch failed: {exc}")


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    if not SECRET:
        LOG.warning("MESH_DISPLAY_SECRET is empty; running UNAUTHENTICATED")
    srv = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    LOG.info("mesh-display-agent listening on %s:%d", LISTEN_HOST, LISTEN_PORT)

    def _shutdown(*_):
        LOG.info("shutting down")
        clear_display()
        srv.shutdown()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)
    try:
        srv.serve_forever()
    finally:
        clear_display()
    return 0


if __name__ == "__main__":
    sys.exit(main())
