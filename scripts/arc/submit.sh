#!/usr/bin/env bash
#
# ARC-AGI submission wrapper
# Parses arguments, validates inputs, invokes the Swift CLI and reports errors
# in a user‑friendly way.

set -euo pipefail

# ----------------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") --task <task_path> --out <output_dir>

Options:
  -t, --task   Path to the task file (required)
  -o, --out    Output directory for the submission (required)
  -h, --help   Show this help message and exit
EOF
}

error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

# ----------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------
TASK=""
OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--task)
            if [[ -z "${2-}" ]]; then
                error_exit "Missing argument for $1"
            fi
            TASK="$2"
            shift 2
            ;;
        -o|--out)
            if [[ -z "${2-}" ]]; then
                error_exit "Missing argument for $1"
            fi
            OUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# ----------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------
[[ -n "$TASK" ]] || error_exit "The --task argument is required."
[[ -n "$OUT" ]]  || error_exit "The --out argument is required."

if [[ ! -f "$TASK" ]]; then
    error_exit "Task file not found: $TASK"
fi

# Ensure output directory exists (or can be created)
if ! mkdir -p "$OUT" 2>/dev/null; then
    error_exit "Unable to create output directory: $OUT"
fi

# Verify that the Swift CLI is available
if ! command -v jarvis >/dev/null 2>&1; then
    error_exit "'jarvis' command not found in PATH. Please install the Swift CLI."
fi

# ----------------------------------------------------------------------
# Submission
# ----------------------------------------------------------------------
echo "Submitting ARC task..."
if ! jarvis arc-submit --task "$TASK" --out "$OUT"; then
    RC=$?
    echo "arc-submit failed with exit code $RC." >&2
    echo "Please check the task file and output directory for issues." >&2
    exit $RC
fi

echo "Submission completed successfully."
exit 0