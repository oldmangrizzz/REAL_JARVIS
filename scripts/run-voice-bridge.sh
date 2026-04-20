#!/bin/zsh
# Launcher for the Jarvis voice HTTP bridge.
# Sources dynamic TTS env (managed by vibevoice-watchdog) + static bridge
# bearer, then execs the Jarvis binary under launchd supervision.

set -u

REPO="/Users/grizzmed/REAL_JARVIS"
BIN="${REPO}/.derived/Build/Products/Release/Jarvis"
BRIDGE_ENV="${REPO}/.jarvis/voice-bridge.env"
TTS_ENV="${HOME}/.jarvis/vibevoice.env"
PORT="${JARVIS_VOICE_BRIDGE_PORT:-8787}"

[[ -f "$TTS_ENV" ]] && source "$TTS_ENV"
[[ -f "$BRIDGE_ENV" ]] && source "$BRIDGE_ENV"

export JARVIS_VOICE_BRIDGE_SECRET="${BEARER:-${JARVIS_VOICE_BRIDGE_SECRET:-}}"

exec "$BIN" start-voice-bridge "$PORT"
