#!/usr/bin/env bash
# Rotate the JARVIS F5-TTS service bearer token.
set -e
PROJECT="${GCP_PROJECT_ID:-grizzly-helicarrier-586794}"
NEW=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
echo -n "$NEW" | gcloud secrets versions add jarvis-f5-tts-bearer \
    --data-file=- --project="$PROJECT"
echo
echo "[rotate] new bearer staged in Secret Manager for jarvis-f5-tts-bearer."
