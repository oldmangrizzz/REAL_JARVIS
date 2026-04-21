#!/usr/bin/env bash
# scripts/smoke/arc-submit.sh
# Smoke test for the ARC-AGI end-to-end submission path (MK2-EPIC-03).
# Builds the Jarvis CLI if the binary is missing, then runs scripts/arc/submit.sh
# on the canned SAMPLE-0001.json demo task and verifies the output JSON.
# Exits 0 on pass, non-zero on failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASK_FILE="${REPO_ROOT}/arc-agi-tasks/demo/SAMPLE-0001.json"
SUBMIT_SCRIPT="${REPO_ROOT}/scripts/arc/submit.sh"
OUT_DIR="${REPO_ROOT}/.arc-smoke-out"
SCHEME="Jarvis"
WORKSPACE="${REPO_ROOT}/jarvis.xcworkspace"
DESTINATION="platform=macOS,arch=arm64"

echo "[arc-smoke] REPO_ROOT: ${REPO_ROOT}"

# ── 1. Locate or build the Jarvis binary ──────────────────────────────────────
JARVIS_BIN=""
for candidate in \
  "${HOME}/Library/Developer/Xcode/DerivedData/jarvis-"*/Build/Products/Debug/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/jarvis-"*/Build/Products/Release/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/Jarvis-"*/Build/Products/Debug/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/Jarvis-"*/Build/Products/Release/Jarvis \
  "$(command -v Jarvis 2>/dev/null || true)" \
  "$(command -v jarvis 2>/dev/null || true)"; do
  if [[ -x "${candidate}" ]]; then
    JARVIS_BIN="${candidate}"
    break
  fi
done

if [[ -z "${JARVIS_BIN}" ]]; then
  echo "[arc-smoke] Jarvis binary not found — building ${SCHEME}…"
  xcodebuild \
    -workspace "${WORKSPACE}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -configuration Debug \
    build 2>&1 | tail -10
  # Re-scan after build
for candidate in \
  "${HOME}/Library/Developer/Xcode/DerivedData/jarvis-"*/Build/Products/Debug/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/jarvis-"*/Build/Products/Release/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/Jarvis-"*/Build/Products/Debug/Jarvis \
  "${HOME}/Library/Developer/Xcode/DerivedData/Jarvis-"*/Build/Products/Release/Jarvis; do
    if [[ -x "${candidate}" ]]; then
      JARVIS_BIN="${candidate}"
      break
    fi
  done
  if [[ -z "${JARVIS_BIN}" ]]; then
    echo "[arc-smoke] FAILED — could not locate Jarvis binary after build" >&2
    exit 1
  fi
fi
echo "[arc-smoke] Using binary: ${JARVIS_BIN}"

# ── 2. Run submit.sh ──────────────────────────────────────────────────────────
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

echo "[arc-smoke] Running: ${SUBMIT_SCRIPT} ${TASK_FILE} --out ${OUT_DIR}"
OUTPUT=$(bash "${SUBMIT_SCRIPT}" "${TASK_FILE}" --out "${OUT_DIR}" 2>&1) || {
  EXIT_CODE=$?
  echo "[arc-smoke] FAILED — submit.sh exited ${EXIT_CODE}"
  echo "${OUTPUT}"
  exit "${EXIT_CODE}"
}

echo "[arc-smoke] Output:"
echo "${OUTPUT}"

# ── 3. Extract last JSON line ─────────────────────────────────────────────────
LAST_LINE=$(echo "${OUTPUT}" | grep '^{' | tail -1)
if [[ -z "${LAST_LINE}" ]]; then
  echo "[arc-smoke] FAILED — no JSON line found in output" >&2
  exit 1
fi

# ── 4. Verify candidateGrid ───────────────────────────────────────────────────
# Expected: [[1,0,0],[0,1,0],[0,0,1]] — the identity grid from SAMPLE-0001.json
EXPECTED_GRID='[[1,0,0],[0,1,0],[0,0,1]]'

CANDIDATE=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
grid = data.get('candidateGrid', [])
print(json.dumps(grid, separators=(',', ':')))
" <<< "${LAST_LINE}")

if [[ "${CANDIDATE}" != "${EXPECTED_GRID}" ]]; then
  echo "[arc-smoke] FAILED — candidateGrid mismatch"
  echo "  expected: ${EXPECTED_GRID}"
  echo "  got:      ${CANDIDATE}" >&2
  exit 1
fi
echo "[arc-smoke] candidateGrid ✓ matches expected identity matrix"

# ── 5. Verify witnessSha256 is non-empty ──────────────────────────────────────
WITNESS=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('witnessSha256', ''))
" <<< "${LAST_LINE}")

if [[ -z "${WITNESS}" ]]; then
  echo "[arc-smoke] FAILED — witnessSha256 is empty" >&2
  exit 1
fi
echo "[arc-smoke] witnessSha256 ✓ (${WITNESS:0:16}…)"

# ── 6. Cleanup ────────────────────────────────────────────────────────────────
rm -rf "${OUT_DIR}"

echo "[arc-smoke] PASS — ARC submission E2E smoke test succeeded"
echo "${LAST_LINE}"
