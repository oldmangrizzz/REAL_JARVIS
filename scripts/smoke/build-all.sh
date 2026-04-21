#!/usr/bin/env bash
#
# Smoke‑build script for the `all` scheme.
#
# This script builds the composite `all` scheme (which aggregates every
# surface target – macOS, iOS, visionOS, etc.) and reports the success or
# failure of each individual target.
#
# Usage:
#   scripts/smoke/build-all.sh
#
# The script runs:
#   xcodebuild build -workspace jarvis.xcworkspace -scheme all \
#       -destination 'generic/platform=macOS'
#
# It parses the build log, extracts the target names, and prints a table
# like:
#
#   Target                         Status
#   ------                         ------
#   JarvisMacOS                    ✅
#   JarvisiOS                      ❌
#
# The script exits with status 0 only if *all* targets succeed; otherwise
# it exits with status 1 and prints the full build log for debugging.

set -uo pipefail

# Temporary file to capture the full build log.
log_file=$(mktemp)

# Run the build.  All output (stdout & stderr) goes to the log file.
xcodebuild build \
    -workspace jarvis.xcworkspace \
    -scheme all \
    -destination 'generic/platform=macOS' \
    >"$log_file" 2>&1
build_exit=$?

# Associative array: target name → status (✅ or ❌)
declare -A target_status
current_target=""

# Parse the log line‑by‑line.
while IFS= read -r line; do
    # Xcode prints a line like:
    #   === BUILD TARGET JarvisMacOS OF PROJECT Jarvis WITH CONFIGURATION Debug ===
    if [[ $line =~ ^===\ BUILD\ TARGET\ ([^[:space:]]+) ]]; then
        current_target="${BASH_REMATCH[1]}"
        # Assume success until an error is seen for this target.
        target_status["$current_target"]="✅"
    # Detect error lines (ignore warnings).
    elif [[ $line =~ ^.*error:\ .* ]]; then
        if [[ -n $current_target ]]; then
            target_status["$current_target"]="❌"
        fi
    fi
done <"$log_file"

# -------------------------------------------------------------------------
# Output the results table.
printf "\n%-30s %s\n" "Target" "Status"
printf "%-30s %s\n" "------" "------"
# Sort keys for deterministic output.
for tgt in "$(printf '%s\n' "${!target_status[@]}" | sort)"; do
    printf "%-30s %s\n" "$tgt" "${target_status[$tgt]}"
done

# -------------------------------------------------------------------------
# Determine overall success.
overall_success=0
for status in "${target_status[@]}"; do
    if [[ $status != "✅" ]]; then
        overall_success=1
        break
    fi
done

# Print a helpful summary and, on failure, dump the full log.
if [[ $overall_success -eq 0 ]]; then
    echo -e "\nAll targets built successfully."
else
    echo -e "\nSome targets failed. Full build log follows:\n"
    cat "$log_file"
fi

# Clean up the temporary log file.
rm -f "$log_file"

exit $overall_success