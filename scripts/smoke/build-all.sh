#!/usr/bin/env bash
# scripts/smoke/build-all.sh
# Builds every Jarvis surface target and prints a pass/fail table.
# Exits 0 only if ALL available builds succeed (skips absent platforms).

set -uo pipefail

WORKSPACE="jarvis.xcworkspace"
PASS="✅ PASS"
FAIL="❌ FAIL"
SKIP="⚠️  SKIP"
overall=0

declare -A results

run_build() {
    local scheme="$1"
    local dest="$2"
    local label="$3"
    local optional="${4:-required}"
    echo "▶  Building $label …"
    local out
    out=$(xcodebuild build \
        -workspace "$WORKSPACE" \
        -scheme "$scheme" \
        -destination "$dest" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet 2>&1)
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        results["$label"]="$PASS"
    else
        # Destination unavailable → skip optional targets, fail required
        if echo "$out" | grep -q "Unable to find a destination" && [[ "$optional" == "optional" ]]; then
            results["$label"]="$SKIP"
        else
            echo "$out" | tail -10
            results["$label"]="$FAIL"
            overall=1
        fi
    fi
}

# ── macOS ──────────────────────────────────────────────────────────────────
run_build "Jarvis"        "platform=macOS,arch=arm64"  "Jarvis (CLI+Core)"
run_build "RealJarvisMac" "platform=macOS,arch=arm64"  "RealJarvisMac"

# ── iOS (simulator) ───────────────────────────────────────────────────────
run_build "RealJarvisPhone" "generic/platform=iOS Simulator" "RealJarvisPhone"
run_build "RealJarvisPad"   "generic/platform=iOS Simulator" "RealJarvisPad"

# ── watchOS (simulator) ───────────────────────────────────────────────────
run_build "RealJarvisWatch" "generic/platform=watchOS Simulator" "RealJarvisWatch"

# ── visionOS — optional: skip gracefully if platform not installed ─────────
run_build "RealJarvisVision" "generic/platform=visionOS Simulator" "RealJarvisVision" "optional"

# ── Print table ───────────────────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────┬────────────┐"
echo "│ Target                           │ Result     │"
echo "├──────────────────────────────────┼────────────┤"
for label in "Jarvis (CLI+Core)" "RealJarvisMac" "RealJarvisPhone" "RealJarvisPad" "RealJarvisWatch" "RealJarvisVision"; do
    printf "│ %-32s │ %s │\n" "$label" "${results[$label]:-  SKIP  }"
done
echo "└──────────────────────────────────┴────────────┘"
echo ""

if [[ $overall -eq 0 ]]; then
    echo "All required targets green. 🟢"
else
    echo "One or more required targets FAILED. 🔴"
fi

exit $overall
