#!/usr/bin/env bash
# Tear down the JARVIS F5-TTS T4 instance.
set -euo pipefail

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
INSTANCE_NAME="${INSTANCE_NAME:-jarvis-f5-tts-t4}"

if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  echo "[gcp-down] instance $INSTANCE_NAME not found; nothing to do."
  exit 0
fi

echo "[gcp-down] deleting $INSTANCE_NAME"
gcloud compute instances delete "$INSTANCE_NAME" \
    --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" --quiet
echo "[gcp-down] done."
