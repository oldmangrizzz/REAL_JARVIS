#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <instance> <secret> <identifier> <voice_label>" >&2
  exit 1
}

# Ensure we have exactly four arguments
if [ "$#" -ne 4 ]; then
  usage
fi

INSTANCE=$1
SECRET=$2
IDENTIFIER=$3
VOICE_LABEL=$4

# F5‑TTS health‑check endpoint
HEALTH_URL="https://${INSTANCE}/api/v1/tts/health"

# Perform the health request, passing required parameters.
# The response is captured together with the HTTP status code.
RESPONSE=$(curl -s -G "$HEALTH_URL" \
  --data-urlencode "secret=${SECRET}" \
  --data-urlencode "identifier=${IDENTIFIER}" \
  --data-urlencode "voice=${VOICE_LABEL}" \
  -w "\n%{http_code}")

# Separate body and status code.
BODY=$(echo "$RESPONSE" | sed '$d')
CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$CODE" -eq 200 ]; then
  echo "F5‑TTS service is healthy."
  exit 0
else
  echo "F5‑TTS health check failed (HTTP $CODE): $BODY" >&2
  exit 1
fi