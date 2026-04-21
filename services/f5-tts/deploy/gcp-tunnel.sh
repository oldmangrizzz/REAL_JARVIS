#!/usr/bin/env bash
# Open the IAP tunnel to the F5-TTS instance.
set -euo pipefail

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
INSTANCE_NAME="${INSTANCE_NAME:-jarvis-f5-tts-t4}"
LOCAL_PORT="${LOCAL_PORT:-8000}"

echo "[tunnel] localhost:${LOCAL_PORT} -> ${INSTANCE_NAME}:8000 (Ctrl-C to close)"
exec gcloud compute start-iap-tunnel "$INSTANCE_NAME" 8000 \
    --local-host-port="localhost:${LOCAL_PORT}" \
    --zone="$GCP_ZONE" \
    --project="$GCP_PROJECT_ID"
