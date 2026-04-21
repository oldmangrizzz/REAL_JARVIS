#!/usr/bin/env bash
# scripts/smoke/arc-submit.sh
# Smoke test for the ARC-AGI submission pipeline.
# It runs `submit.sh` on SAMPLE-0001.json, validates the generated
# submission JSON and checks telemetry ordering.

set -euo pipefail

# Helper for error messages
die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Locate the sample task file
SAMPLE_FILE="$(find . -type f -name 'SAMPLE-0001.json' | head -n1)"
[[ -n "$SAMPLE_FILE" ]] || die "Could not find SAMPLE-0001.json in the repository."

# Run the submission script
OUTPUT_JSON="$(mktemp)"
if ! ./submit.sh "$SAMPLE_FILE" >"$OUTPUT_JSON"; then
    rm -f "$OUTPUT_JSON"
    die "'submit.sh' failed for $SAMPLE_FILE"
fi

# Ensure the output is valid JSON
if ! jq empty "$OUTPUT_JSON" >/dev/null 2>&1; then
    rm -f "$OUTPUT_JSON"
    die "Generated output is not valid JSON."
fi

# -------------------------------------------------------------------------
# 1. Verify candidate grid
# -------------------------------------------------------------------------
# Expected grid is taken from the sample file (field `grid` if present)
EXPECTED_GRID="$(jq -r '.grid // empty' "$SAMPLE_FILE")"
CANDIDATE_GRID="$(jq -r '.candidate.grid // empty' "$OUTPUT_JSON")"

if [[ -z "$CANDIDATE_GRID" ]]; then
    rm -f "$OUTPUT_JSON"
    die "candidate.grid is missing or empty in the submission."
fi

if [[ -n "$EXPECTED_GRID" && "$CANDIDATE_GRID" != "$EXPECTED_GRID" ]]; then
    rm -f "$OUTPUT_JSON"
    die "candidate.grid does not match expected value.
Expected: $EXPECTED_GRID
Got     : $CANDIDATE_GRID"
fi

# -------------------------------------------------------------------------
# 2. Verify witnessSha256 is present and non‑empty
# -------------------------------------------------------------------------
WITNESS_SHA="$(jq -r '.witnessSha256 // empty' "$OUTPUT_JSON")"
if [[ -z "$WITNESS_SHA" ]]; then
    rm -f "$OUTPUT_JSON"
    die "witnessSha256 is missing or empty in the submission."
fi

# -------------------------------------------------------------------------
# 3. Verify telemetry ordering
# -------------------------------------------------------------------------
# Expected ordering (example): start → submit → end
# Adjust this list if the pipeline defines a different order.
EXPECTED_TELEMETRY_ORDER=("start" "submit" "end")

# Extract the telemetry type list from the output
mapfile -t ACTUAL_TELEMETRY_ORDER < <(jq -r '.telemetry[].type' "$OUTPUT_JSON")

# Helper to compare two arrays
arrays_equal() {
    local -n a1=$1 a2=$2
    [[ "${#a1[@]}" -eq "${#a2[@]}" ]] || return 1
    for i in "${!a1[@]}"; do
        [[ "${a1[i]}" == "${a2[i]}" ]] || return 1
    done
    return 0
}

if ! arrays_equal EXPECTED_TELEMETRY_ORDER ACTUAL_TELEMETRY_ORDER; then
    rm -f "$OUTPUT_JSON"
    echo "Telemetry ordering mismatch."
    echo "Expected: ${EXPECTED_TELEMETRY_ORDER[*]}"
    echo "Actual  : ${ACTUAL_TELEMETRY_ORDER[*]}"
    exit 1
fi

# -------------------------------------------------------------------------
# Success
# -------------------------------------------------------------------------
echo "ARC-AGI smoke test passed."
rm -f "$OUTPUT_JSON"
exit 0