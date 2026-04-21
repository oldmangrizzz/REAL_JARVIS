#!/usr/bin/env bash
# scripts/smoke/voice-loop.sh
# Smoke test for the unified voice pipeline orchestrator.
# Feeds a WAV file into the orchestrator, validates telemetry event order,
# and ensures the generated TTS output is at least 1 second long.

set -euo pipefail

# -------------------------- Configuration --------------------------

# Orchestrator endpoint (expects a POST that accepts raw WAV data)
ORCH_URL="${ORCH_URL:-http://localhost:8080/orchestrate}"

# Telemetry endpoint (expects GET ?jobId=... returning JSON array of events)
TELEMETRY_URL="${TELEMETRY_URL:-http://localhost:8080/telemetry}"

# Maximum time (seconds) to wait for the pipeline to finish
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-60}"

# Poll interval for telemetry (seconds)
POLL_INTERVAL="${POLL_INTERVAL:-2}"

# Expected telemetry event sequence
EXPECTED_EVENTS=(
    "audio_received"
    "transcription_started"
    "transcription_completed"
    "tts_started"
    "tts_completed"
)

# -------------------------- Helpers --------------------------

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Check required commands
for cmd in curl jq sox; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found in PATH."
done

# Compute duration of a WAV file (seconds, floating point)
wav_duration() {
    local file=$1
    # sox prints "Length (seconds): X.XX"
    sox --i -D "$file"
}

# -------------------------- Input --------------------------

if [[ $# -lt 1 ]]; then
    die "Usage: $0 <path-to-wav-file>"
fi

WAV_FILE="$1"
[[ -f "$WAV_FILE" ]] || die "WAV file '$WAV_FILE' does not exist."

# -------------------------- Submit Audio --------------------------

log "Submitting audio '$WAV_FILE' to orchestrator at $ORCH_URL ..."
# The orchestrator is expected to return JSON: { "jobId": "...", "ttsUrl": "..." }
RESPONSE=$(curl -sSf -X POST "$ORCH_URL" \
    -H "Content-Type: audio/wav" \
    --data-binary @"$WAV_FILE")

JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId // empty')
[[ -n "$JOB_ID" ]] || die "Orchestrator response missing jobId. Response: $RESPONSE"

log "Received jobId: $JOB_ID"

# -------------------------- Telemetry Validation --------------------------

log "Polling telemetry for jobId $JOB_ID (timeout ${PIPELINE_TIMEOUT}s)..."
START_TIME=$(date +%s)
EVENTS=()

while true; do
    # Fetch telemetry events for this job
    TELEMETRY_JSON=$(curl -sSf "${TELEMETRY_URL}?jobId=${JOB_ID}")
    # Expecting an array of objects: [{ "event": "audio_received", "timestamp": ... }, ...]
    EVENTS=($(echo "$TELEMETRY_JSON" | jq -r '.[].event'))

    # Check if we have all expected events
    if [[ ${#EVENTS[@]} -ge ${#EXPECTED_EVENTS[@]} ]]; then
        # Verify order
        MATCH=true
        for i in "${!EXPECTED_EVENTS[@]}"; do
            if [[ "${EVENTS[i]}" != "${EXPECTED_EVENTS[i]}" ]]; then
                MATCH=false
                break
            fi
        done
        if $MATCH; then
            log "Telemetry events received in expected order: ${EVENTS[*]}"
            break
        else
            log "Telemetry events order mismatch. Received: ${EVENTS[*]}"
            # continue polling until timeout
        fi
    else
        log "Telemetry events so far (${#EVENTS[@]}/${#EXPECTED_EVENTS[@]}): ${EVENTS[*]}"
    fi

    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if (( ELAPSED >= PIPELINE_TIMEOUT )); then
        die "Timeout waiting for telemetry events. Last received: ${EVENTS[*]}"
    fi
    sleep "$POLL_INTERVAL"
done

# -------------------------- TTS Output Validation --------------------------

# Retrieve TTS URL from telemetry (or from original response if present)
TTS_URL=$(echo "$TELEMETRY_JSON" | jq -r '.[] | select(.event=="tts_completed") | .payload.ttsUrl // empty')
if [[ -z "$TTS_URL" ]]; then
    # Fallback to original response payload
    TTS_URL=$(echo "$RESPONSE" | jq -r '.ttsUrl // empty')
fi
[[ -n "$TTS_URL" ]] || die "Unable to locate TTS output URL."

log "Downloading TTS output from $TTS_URL ..."
TTS_FILE=$(mktemp /tmp/tts-output-XXXX.wav)
curl -sSf -o "$TTS_FILE" "$TTS_URL"

DURATION=$(wav_duration "$TTS_FILE")
log "TTS output duration: ${DURATION}s"

# Ensure duration is at least 1 second (allow small floating point tolerance)
MIN_DURATION=1.0
if (( $(awk -v d="$DURATION" -v m="$MIN_DURATION" 'BEGIN{print (d+0) >= (m+0)}') )); then
    log "TTS output meets minimum duration requirement (>= ${MIN_DURATION}s)."
else
    die "TTS output too short (${DURATION}s). Expected at least ${MIN_DURATION}s."
fi

# Cleanup
rm -f "$TTS_FILE"

log "Smoke test completed successfully."
exit 0