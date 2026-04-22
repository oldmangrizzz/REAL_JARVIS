#!/usr/bin/env bash
# homebridge-hydrate.sh — merge .jarvis/control-plane/homebridge/config.json template
# with secret pin from .jarvis/secrets/homebridge.secret.json.
# Writes hydrated config to $HOMEBRIDGE_RUNTIME_CONFIG (default /tmp/jarvis-homebridge.config.json).
set -euo pipefail
TEMPLATE="${HOMEBRIDGE_CONFIG_TEMPLATE:-.jarvis/control-plane/homebridge/config.json}"
SECRET="${HOMEBRIDGE_SECRET_FILE:-.jarvis/secrets/homebridge.secret.json}"
OUT="${HOMEBRIDGE_RUNTIME_CONFIG:-/tmp/jarvis-homebridge.config.json}"
if [[ ! -f "$TEMPLATE" ]]; then echo "missing template: $TEMPLATE" >&2; exit 2; fi
if [[ ! -f "$SECRET" ]]; then echo "missing secret: $SECRET" >&2; exit 2; fi
PIN=$(jq -r '.bridge.pin' "$SECRET")
if [[ -z "$PIN" || "$PIN" == "null" ]]; then echo "secret file missing .bridge.pin" >&2; exit 2; fi
jq --arg pin "$PIN" '.bridge.pin = $pin' "$TEMPLATE" > "$OUT"
chmod 600 "$OUT"
echo "hydrated → $OUT"
