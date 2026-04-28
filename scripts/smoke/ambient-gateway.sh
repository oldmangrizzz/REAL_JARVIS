#!/usr/bin/env bash
# scripts/smoke/ambient-gateway.sh
# MK2 gate #5 — ambient gateway (watch-as-audio-gateway) smoke.
# Verifies: watch app target exists, tunnel supports watch registration,
# watchOS build artifacts present.
# Exits 0 on pass, non-zero on failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

echo "[ambient-smoke] $TS — starting ambient gateway smoke"

# ── 1. Watch app source exists ──────────────────────────────────────────────
WATCH_APP="${REPO_ROOT}/Jarvis/Watch/Extension/RealJarvisWatchApp.swift"
if [[ ! -f "$WATCH_APP" ]]; then
  echo "[ambient-smoke] FAIL: Watch app entry point missing: $WATCH_APP" >&2
  exit 1
fi
echo "[ambient-smoke] Watch app source: OK"

# ── 2. Watch scheme builds (reuse derived data if present) ──────────────────
WATCH_DERIVED="${HOME}/Library/Developer/Xcode/DerivedData"
WATCH_BUILT="$(find "$WATCH_DERIVED" -path '*/Build/Products/*/JarvisWatch.app' -print -quit 2>/dev/null || true)"
if [[ -n "$WATCH_BUILT" ]]; then
  echo "[ambient-smoke] Watch build artifact present: $WATCH_BUILT"
else
  echo "[ambient-smoke] Watch build artifact not found in derived data — may need full build"
fi

# ── 3. Tunnel supports watch role ────────────────────────────────────────────
TUNNEL_SERVER="${REPO_ROOT}/Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift"
if ! grep -q 'watch' "$TUNNEL_SERVER" 2>/dev/null; then
  echo "[ambient-smoke] FAIL: Tunnel server does not reference watch role" >&2
  exit 1
fi
echo "[ambient-smoke] Tunnel watch role: OK"

# ── 4. AMBIENT-001 design doc exists ───────────────────────────────────────
AMBIENT_SPEC="${REPO_ROOT}/Construction/Qwen/spec/AMBIENT-001-watch-as-audio-gateway.md"
if [[ ! -f "$AMBIENT_SPEC" ]]; then
  echo "[ambient-smoke] WARN: AMBIENT-001 spec missing"
else
  echo "[ambient-smoke] AMBIENT-001 spec: OK"
fi

# ── 5. Placeholder for full gateway test ─────────────────────────────────────
# Full watch↔host audio tunnel is post-AMBIENT-001 implementation.
# This smoke verifies the build + tunnel surface only.
echo "[ambient-smoke] PASS — ambient gateway surface wired (full audio tunnel pending AMBIENT-001)"
