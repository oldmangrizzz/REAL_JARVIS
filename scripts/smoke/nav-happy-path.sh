#!/usr/bin/env bash
#
# scripts/smoke/nav-happy-path.sh
#
# This smoke test simulates a navigation intent via the tunnel, waits for a
# navigationRoute response, validates the returned polyline and ensures that a
# `nav.route.computed` telemetry event is emitted.
#
# Platform‑guard: this script is intended to run on macOS (Darwin) where the
# tunnel and associated services are available.

set -euo pipefail

# ---------------------------------------------------------------------------
# Platform guard
# ---------------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ Platform guard failure: this script must be executed on macOS (Darwin)."
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Base URL of the local tunnel exposing the app's HTTP endpoints.
# Override via the TUNNEL_URL environment variable if needed.
TUNNEL_URL=${TUNNEL_URL:-http://localhost:8080}

# Endpoints
NAV_INTENT_ENDPOINT="${TUNNEL_URL}/intent"
ROUTE_ENDPOINT="${TUNNEL_URL}/navigation/route"
TELEMETRY_ENDPOINT="${TUNNEL_URL}/telemetry/events"

# Retry policy
MAX_RETRIES=30          # total attempts
SLEEP_SECONDS=2         # pause between attempts

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

fail() {
  echo "❌ $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1️⃣ Send a navigate intent
# ---------------------------------------------------------------------------
NAV_PAYLOAD='{
  "type": "navigate",
  "destination": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "name": "San Francisco"
  }
}'

log "Sending navigate intent to ${NAV_INTENT_ENDPOINT}..."
INTENT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$NAV_PAYLOAD" "$NAV_INTENT_ENDPOINT") || fail "Failed to POST navigate intent."
log "Intent response: $INTENT_RESPONSE"

# ---------------------------------------------------------------------------
# 2️⃣ Wait for a navigation route response
# ---------------------------------------------------------------------------
log "Waiting for navigation route (max ${MAX_RETRIES} attempts)..."
route_json=""

for ((i=1; i<=MAX_RETRIES; i++)); do
  route_json=$(curl -s "$ROUTE_ENDPOINT") || true
  if [[ -n "$route_json" && "$route_json" != "null" ]]; then
    log "Received navigation route JSON."
    break
  fi
  log "Attempt $i/${MAX_RETRIES}: route not ready – sleeping ${SLEEP_SECONDS}s..."
  sleep $SLEEP_SECONDS
done

if [[ -z "$route_json" || "$route_json" == "null" ]]; then
  fail "Did not receive a navigation route within the allotted time."
fi

# ---------------------------------------------------------------------------
# 3️⃣ Validate the polyline
# ---------------------------------------------------------------------------
polyline=$(echo "$route_json" | jq -r '.polyline // empty') || fail "Failed to parse route JSON."
if [[ -z "$polyline" ]]; then
  fail "Polyline field missing in navigation route."
fi

# Basic sanity check: non‑empty string and reasonable length
if (( ${#polyline} < 5 )); then
  fail "Polyline appears invalid (length ${#polyline} < 5)."
fi

log "Polyline validation passed (length ${#polyline})."

# ---------------------------------------------------------------------------
# 4️⃣ Verify telemetry event `nav.route.computed`
# ---------------------------------------------------------------------------
log "Checking telemetry for event 'nav.route.computed' (max ${MAX_RETRIES} attempts)..."
event_found=0

for ((i=1; i<=MAX_RETRIES; i++)); do
  events=$(curl -s "$TELEMETRY_ENDPOINT") || true
  if echo "$events" | jq -e '.[] | select(.name == "nav.route.computed")' > /dev/null 2>&1; then
    event_found=1
    log "Telemetry event 'nav.route.computed' detected."
    break
  fi
  log "Attempt $i/${MAX_RETRIES}: event not yet emitted – sleeping ${SLEEP_SECONDS}s..."
  sleep $SLEEP_SECONDS
done

if (( event_found != 1 )); then
  fail "Telemetry event 'nav.route.computed' was not emitted."
fi

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------
log "✅ Navigation happy‑path smoke test succeeded."
exit 0