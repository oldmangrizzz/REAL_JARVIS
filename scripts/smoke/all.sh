#!/usr/bin/env bash
# scripts/smoke/all.sh
# Unified smoke test runner for Mark II.
# Executes a series of EPIC scripts sequentially, aborting on the first failure,
# records per‑step duration, and writes a JSON summary to Storage/mark-ii/last-smoke.json.

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# List of EPIC scripts to run (relative to this file's directory)
EPIC_SCRIPTS=(
    "build-all.sh"
    "carplay-entitlement.sh"
    "nav-happy-path.sh"
    "voice-loop.sh"
    "arc-submit.sh"
    "destructive-confirm-ui.sh"
)

# Destination for the JSON summary
OUTPUT_DIR="Storage/mark-ii"
OUTPUT_FILE="${OUTPUT_DIR}/last-smoke.json"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
timestamp_ns() {
    date +%s%N
}

duration_ms() {
    local start_ns=$1
    local end_ns=$2
    echo $(( (end_ns - start_ns) / 1000000 ))
}

json_escape() {
    # Minimal JSON string escaper for script names (no special chars expected)
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

overall_status="success"
declare -a step_results=()

# Run each EPIC script in order
for script in "${EPIC_SCRIPTS[@]}"; do
    step_name="${script%.*}"
    start_ts=$(timestamp_ns)

    if ./"$script"; then
        step_status="success"
    else
        step_status="failure"
        overall_status="failure"
    fi

    end_ts=$(timestamp_ns)
    step_dur=$(duration_ms "$start_ts" "$end_ts")
    step_results+=("{\"name\":\"$(json_escape "$step_name")\",\"duration_ms\":$step_dur,\"status\":\"$step_status\"}")

    # Abort on first failure
    if [[ "$step_status" == "failure" ]]; then
        break
    fi
done

# If all EPIC scripts succeeded, run the final xcodebuild test
if [[ "$overall_status" == "success" ]]; then
    start_ts=$(timestamp_ns)

    if xcodebuild test; then
        step_status="success"
    else
        step_status="failure"
        overall_status="failure"
    fi

    end_ts=$(timestamp_ns)
    step_dur=$(duration_ms "$start_ts" "$end_ts")
    step_results+=("{\"name\":\"xcodebuild_test\",\"duration_ms\":$step_dur,\"status\":\"$step_status\"}")
fi

# Assemble JSON payload
steps_json=$(IFS=,; echo "${step_results[*]}")
summary_json="{\"steps\":[${steps_json}],\"overall_status\":\"${overall_status}\"}"

# Write out the summary
mkdir -p "$OUTPUT_DIR"
printf '%s\n' "$summary_json" > "$OUTPUT_FILE"

# Exit with appropriate code
if [[ "$overall_status" == "success" ]]; then
    exit 0
else
    exit 1
fi