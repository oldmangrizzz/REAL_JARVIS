#!/bin/zsh
# Jarvis TTS watchdog.
# Supports swapping between VibeVoice and F5-TTS via top-of-file constants.
#
# What it does (every invocation):
#   1. Asks GCP for the instance status + current external IP.
#   2. If the VM is missing/stopped/terminated, re-runs gcp-up.sh.
#   3. Hits /healthz. If ok, writes the current env (URL + bearer) to
#      ~/.jarvis/tts.env and (if changed) restarts the local
#      voice-bridge so Obsidian picks up the new IP without user action.
#   4. Logs to ~/.jarvis/tts-watchdog.log (rotated at 5MB).
#
# Intended to be driven by launchd (com.grizz.jarvis.tts.watchdog)
# on 60s cadence. Safe to run manually.

set -u

# --- CONFIGURATION (Swap here) ---
PROJECT="grizzly-helicarrier-586794"
ZONE="us-central1-a"
INSTANCE="jarvis-f5-tts-t4"
IDENTIFIER="f5-tts/F5-TTS_Base"
VOICE_LABEL="f5-tts-clone"
SAMPLE_RATE="24000"
BEARER_SECRET_NAME="jarvis-f5-tts-bearer"
GCP_UP_SCRIPT="services/f5-tts/deploy/gcp-up.sh"
# ---------------------------------

REPO="/Users/grizzmed/REAL_JARVIS"
ENV_FILE="${HOME}/.jarvis/tts.env" # Renamed from vibevoice.env
BRIDGE_ENV="${HOME}/REAL_JARVIS/.jarvis/voice-bridge.env"
LOG_FILE="${HOME}/.jarvis/tts-watchdog.log"
GCLOUD="/opt/homebrew/bin/gcloud"
BRIDGE_PORT=8787

mkdir -p "$(dirname "$ENV_FILE")"
touch "$LOG_FILE"
# rotate if > 5MB
if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE") -gt 5242880 ]]; then
  mv "$LOG_FILE" "${LOG_FILE}.1"
fi

log() { print -r -- "[$(date -u +%FT%TZ)] $*" >> "$LOG_FILE"; }

if ! command -v "$GCLOUD" >/dev/null 2>&1; then
  log "ERROR: gcloud not found at $GCLOUD"
  exit 0
fi

# 1. Query VM status
STATUS_LINE="$("$GCLOUD" compute instances describe "$INSTANCE" \
  --project="$PROJECT" --zone="$ZONE" \
  --format='value(status,networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)"

STATUS="${STATUS_LINE%%$'\t'*}"
IP="${STATUS_LINE##*$'\t'}"

if [[ -z "$STATUS" || "$STATUS" != "RUNNING" ]]; then
  log "VM state=${STATUS:-missing}; calling $GCP_UP_SCRIPT"
  (cd "$REPO" && GCP_PROJECT_ID="$PROJECT" /bin/bash "$GCP_UP_SCRIPT") >> "$LOG_FILE" 2>&1
  sleep 5
  STATUS_LINE="$("$GCLOUD" compute instances describe "$INSTANCE" \
    --project="$PROJECT" --zone="$ZONE" \
    --format='value(status,networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null)"
  STATUS="${STATUS_LINE%%$'\t'*}"
  IP="${STATUS_LINE##*$'\t'}"
fi

if [[ "$STATUS" != "RUNNING" || -z "$IP" ]]; then
  log "still not healthy after bring-up attempt (status=$STATUS ip=$IP)"
  exit 0
fi

# 2. Healthcheck
CODE="$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://${IP}:8000/healthz" 2>/dev/null || echo "000")"
if [[ "$CODE" != "200" ]]; then
  log "healthz returned $CODE at http://${IP}:8000 — may be booting; will retry next tick"
  exit 0
fi

# 3. Fetch bearer (cached)
BEARER_CACHE="${HOME}/.jarvis/tts-bearer"
if [[ ! -s "$BEARER_CACHE" ]]; then
  BEARER="$("$GCLOUD" secrets versions access latest --secret="$BEARER_SECRET_NAME" --project="$PROJECT" 2>/dev/null)"
  if [[ -n "$BEARER" ]]; then
    umask 077
    print -n -- "$BEARER" > "$BEARER_CACHE"
    chmod 600 "$BEARER_CACHE"
  fi
fi
BEARER="$(cat "$BEARER_CACHE" 2>/dev/null)"

# 4. Write env file atomically if IP or bearer drifted
if [[ -z "$IP" || -z "$BEARER" || -z "$IDENTIFIER" ]]; then
  log "ERROR: missing critical env vars (IP=$IP, IDENTIFIER=$IDENTIFIER, BEARER=${#BEARER} chars); skipping env update"
  exit 0
fi

NEW_ENV="export JARVIS_TTS_URL=\"http://${IP}:8000/tts/synthesize\"
export JARVIS_TTS_BEARER=\"${BEARER}\"
export JARVIS_TTS_IDENTIFIER=\"${IDENTIFIER}\"
export JARVIS_TTS_VOICE_LABEL=\"${VOICE_LABEL}\"
export JARVIS_TTS_SAMPLE_RATE=\"${SAMPLE_RATE}\""
OLD_ENV=""
[[ -f "$ENV_FILE" ]] && OLD_ENV="$(cat "$ENV_FILE")"

if [[ "$NEW_ENV" != "$OLD_ENV" ]]; then
  umask 077
  printf '%s' "$NEW_ENV" > "${ENV_FILE}.tmp"
  mv "${ENV_FILE}.tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "env updated: IP=$IP"

  # 5. Kick the voice-bridge LaunchAgent so it reloads with the new env.
  # KeepAlive=true means launchd will respawn it within ThrottleInterval.
  /bin/launchctl kickstart -k "gui/$(id -u)/com.grizz.jarvis.voice-bridge" \
    >> "$LOG_FILE" 2>&1 || true
  log "kicked voice-bridge LaunchAgent"
else
  log "healthy (IP=$IP unchanged)"
fi
