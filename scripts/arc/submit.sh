#!/usr/bin/env bash
# scripts/arc/submit.sh
# Usage: scripts/arc/submit.sh <task.json> [--out <dir>]
# Invokes the Jarvis CLI arc-submit subcommand.
# Exits 0 on success with a single trailing JSON line.
# Exits non-zero on failure with a "ship-arc: FAILED — <reason>" diagnostic.
set -euo pipefail

TASK_FILE="${1:-}"
OUT_DIR="${HOME}/arc-agi-submissions"

if [[ -z "${TASK_FILE}" ]]; then
  echo "ship-arc: FAILED — missing required argument <task.json>" >&2
  echo "Usage: $0 <task.json> [--out <dir>]" >&2
  exit 1
fi

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    *) echo "ship-arc: FAILED — unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "${TASK_FILE}" ]]; then
  echo "ship-arc: FAILED — task file not found: ${TASK_FILE}" >&2
  exit 1
fi

# Locate the Jarvis CLI binary
JARVIS_BIN=""
# Check common derived-data paths first, then PATH
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
  echo "ship-arc: FAILED — Jarvis binary not found; build the Jarvis scheme first" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

OUTPUT=$("${JARVIS_BIN}" arc-submit --task "${TASK_FILE}" --out "${OUT_DIR}" 2>&1) || {
  EXIT_CODE=$?
  echo "ship-arc: FAILED — Jarvis exited ${EXIT_CODE}: ${OUTPUT}" >&2
  exit "${EXIT_CODE}"
}

echo "${OUTPUT}"
