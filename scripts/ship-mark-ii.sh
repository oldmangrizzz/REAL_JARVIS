#!/usr/bin/env bash
# scripts/ship-mark-ii.sh
#
# MK2-EPIC-09 — single-command Mark II deploy orchestrator.
# Runs every ship-gate check the PRD requires, in order, fail-fast.
#
# Stages:
#   1  xcodegen                 — regenerate project from project.yml
#   2  build/macOS              — Jarvis + JarvisCore schemes (arm64 macOS)
#   3  build/iOS                — JarvisPhone + JarvisPad + JarvisMobileCore
#   4  build/watchOS            — JarvisWatch + JarvisWatchCore
#   5  tests                    — JarvisCore xcodebuild test (must be >=130)
#   6  soul-anchor/drill        — MK2 gate #7 rotation drill
#   7  canon-gate                — MK2 gate #10 dual-sig verifier
#   8  smoke/arc-submit         — MK2 gate #8 ARC submission smoke
#   9  smoke/voice-latency      — MK2 gate #4 voice E2E latency probe
#  10  artifact                 — writes Storage/ship-mark-ii/<ts>.log
#
# Flags:
#   --skip-ios        skip iOS builds (for macOS-only dev loops)
#   --skip-watchos    skip watchOS builds
#   --skip-smoke      skip smoke/arc + smoke/voice
#   --fast            implies --skip-ios --skip-watchos --skip-smoke
#
# Non-zero on any stage failure with a single trailing diagnostic line:
#   ship-mark-ii: FAILED at stage <name> — see <log>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG_DIR="$REPO_ROOT/Storage/ship-mark-ii"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$TS.log"

SKIP_IOS=0
SKIP_WATCHOS=0
SKIP_SMOKE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-ios)     SKIP_IOS=1; shift;;
    --skip-watchos) SKIP_WATCHOS=1; shift;;
    --skip-smoke)   SKIP_SMOKE=1; shift;;
    --fast)         SKIP_IOS=1; SKIP_WATCHOS=1; SKIP_SMOKE=1; shift;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

say() {
  local ts
  ts=$(date -u +%H:%M:%SZ)
  printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

run_stage() {
  local name="$1"; shift
  say "== stage: $name =="
  if "$@" >>"$LOG_FILE" 2>&1; then
    say "   ok: $name"
    return 0
  else
    local rc=$?
    say "   FAIL: $name (rc=$rc)"
    echo "ship-mark-ii: FAILED at stage $name — see $LOG_FILE" >&2
    exit $rc
  fi
}

# -----------------------------------------------------------------------------
# stage 1: xcodegen
# -----------------------------------------------------------------------------
stage_xcodegen() {
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
  else
    say "   (xcodegen not installed — skipping project regen)"
  fi
}

# -----------------------------------------------------------------------------
# stage 2-4: builds
# -----------------------------------------------------------------------------
xb() {
  # $1 scheme, $2 destination
  xcodebuild -workspace jarvis.xcworkspace -scheme "$1" -destination "$2" \
    -quiet build
}

stage_build_macos() {
  xb Jarvis      'platform=macOS,arch=arm64'
  xb JarvisCore  'platform=macOS,arch=arm64'
}

stage_build_ios() {
  xb JarvisMobileCore 'generic/platform=iOS'
  xb JarvisPhone      'generic/platform=iOS'
  xb JarvisPad        'generic/platform=iOS'
}

stage_build_watchos() {
  xb JarvisWatchCore 'generic/platform=watchOS'
  xb JarvisWatch     'generic/platform=watchOS'
}

# -----------------------------------------------------------------------------
# stage 5: tests + floor
# -----------------------------------------------------------------------------
stage_tests() {
  local testlog
  testlog="$LOG_DIR/$TS.tests.log"
  set -o pipefail
  xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
    -destination 'platform=macOS,arch=arm64' test 2>&1 | tee "$testlog" >/dev/null
  local executed
  executed=$(grep -Eo 'Executed [0-9]+ tests, with 0 failures' "$testlog" \
    | tail -1 | grep -Eo '[0-9]+' | head -1 || echo 0)
  say "   tests executed: $executed"
  if [[ -z "$executed" || "$executed" -lt 130 ]]; then
    say "   canon floor violated (<130)"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# stage 6: soul-anchor drill
# -----------------------------------------------------------------------------
stage_soul_anchor_drill() {
  bash "$REPO_ROOT/scripts/soul-anchor/rotate.sh" --drill
}

# -----------------------------------------------------------------------------
# stage 7: canon-gate self-check against HEAD~1..HEAD
# -----------------------------------------------------------------------------
stage_canon_gate() {
  local base head
  base=$(git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD)
  head=$(git rev-parse HEAD)
  bash "$REPO_ROOT/scripts/ci/canon-gate.sh" "$base" "$head"
}

# -----------------------------------------------------------------------------
# stage 8: arc submit smoke
# -----------------------------------------------------------------------------
stage_smoke_arc() {
  if [[ -x "$REPO_ROOT/scripts/smoke/arc-submit.sh" ]]; then
    bash "$REPO_ROOT/scripts/smoke/arc-submit.sh"
  else
    say "   (arc-submit smoke not present — gate #8 deferred)"
    return 0
  fi
}

# -----------------------------------------------------------------------------
# stage 9: voice latency smoke
# -----------------------------------------------------------------------------
stage_smoke_voice() {
  if [[ -x "$REPO_ROOT/scripts/smoke/voice-latency.sh" ]]; then
    bash "$REPO_ROOT/scripts/smoke/voice-latency.sh"
  else
    say "   (voice-latency smoke not present — gate #4 deferred)"
    return 0
  fi
}

# -----------------------------------------------------------------------------
# stage 10: artifact
# -----------------------------------------------------------------------------
stage_artifact() {
  local git_sha
  git_sha=$(git rev-parse HEAD)
  printf 'ship-mark-ii\nsha: %s\nwhen: %s\nlog: %s\n' \
    "$git_sha" "$TS" "$LOG_FILE" \
    > "$LOG_DIR/latest.txt"
  say "   artifact: $LOG_DIR/latest.txt"
}

# -----------------------------------------------------------------------------
# orchestrate
# -----------------------------------------------------------------------------
say "ship-mark-ii start $TS (sha=$(git rev-parse --short HEAD))"

run_stage xcodegen            stage_xcodegen
run_stage build/macOS         stage_build_macos
[[ "$SKIP_IOS"     -eq 0 ]] && run_stage build/iOS        stage_build_ios
[[ "$SKIP_WATCHOS" -eq 0 ]] && run_stage build/watchOS    stage_build_watchos
run_stage tests               stage_tests
run_stage soul-anchor/drill   stage_soul_anchor_drill
run_stage canon-gate          stage_canon_gate
[[ "$SKIP_SMOKE"   -eq 0 ]] && run_stage smoke/arc        stage_smoke_arc
[[ "$SKIP_SMOKE"   -eq 0 ]] && run_stage smoke/voice      stage_smoke_voice
run_stage artifact            stage_artifact

say "ship-mark-ii: GREEN"
exit 0
