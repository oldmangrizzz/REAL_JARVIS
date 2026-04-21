#!/usr/bin/env bash
# scripts/smoke/all.sh
# Unified smoke runner: executes each stage sequentially, aborts on first failure,
# and writes a JSON summary to Storage/mark-ii/last-smoke.json.

set -euo pipefail

# Ensure the output directory exists
mkdir -p Storage/mark-ii

# Define the ordered list of smoke steps.
# Adjust the command paths if your scripts live elsewhere.
steps=(
    "build"
    "entitlement"
    "nav"
    "voice-loop"
    "arc-submit"
    "destructive-confirm"
    "full-test-suite"
)

# Associative array to capture per‑step results.
declare -A results

# Helper to emit JSON.
emit_json() {
    local status=$1
    local failed_step=$2
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    {
        echo "{"
        echo "  \"status\": \"${status}\","
        [[ -n $failed_step ]] && echo "  \"failed_step\": \"${failed_step}\","
        echo "  \"timestamp\": \"${timestamp}\","
        echo "  \"results\": {"
        local first=true
        for k in "${!results[@]}"; do
            $first && first=false || echo ","
            echo -n "    \"${k}\": \"${results[$k]}\""
        done
        echo
        echo "  }"
        echo "}"
    } > Storage/mark-ii/last-smoke.json
}

# Execute each step.
for step in "${steps[@]}"; do
    # Resolve the command: prefer a script in scripts/smoke/, otherwise assume it's in PATH.
    if [[ -x "scripts/smoke/${step}.sh" ]]; then
        cmd="./scripts/smoke/${step}.sh"
    else
        cmd="${step}"
    fi

    echo "=== Running ${step} ==="
    if $cmd; then
        results[$step]="passed"
    else
        results[$step]="failed"
        emit_json "failed" "$step"
        exit 1
    fi
done

# All steps succeeded.
emit_json "passed" ""
exit 0