#!/usr/bin/env bash
# services/f5-tts/deploy/gcp-tunnel.sh
#
# Creates an SSH tunnel to the F5‑TTS VM for local testing.
# The script is intentionally generic – you can override the
# project, zone, instance name, and ports via command‑line flags
# or environment variables.
#
# Example:
#   ./gcp-tunnel.sh --project my-gcp-project \
#                   --zone us-central1-a \
#                   --instance f5-tts \
#                   --local-port 5000 \
#                   --remote-port 5000
#
# The tunnel will forward <local-port> on your workstation to
# <remote-port> on the VM, allowing you to hit the F5‑TTS service
# as if it were running locally.

set -euo pipefail

# Default values – can be overridden by flags or env vars
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-}"
INSTANCE_NAME="${INSTANCE_NAME:-f5-tts}"
LOCAL_PORT="${LOCAL_PORT:-5000}"
REMOTE_PORT="${REMOTE_PORT:-5000}"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --project PROJECT_ID       GCP project ID (or set env PROJECT_ID)
  --zone ZONE               GCP compute zone (or set env ZONE)
  --instance INSTANCE_NAME   Compute instance name (default: f5-tts)
  --local-port PORT         Local port to bind (default: 5000)
  --remote-port PORT        Remote port on the VM (default: 5000)
  -h, --help                Show this help message and exit
EOF
}

# Parse command‑line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --zone)
      ZONE="$2"
      shift 2
      ;;
    --instance)
      INSTANCE_NAME="$2"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --remote-port)
      REMOTE_PORT="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
  echo "Error: GCP project ID must be provided via --project or PROJECT_ID env var." >&2
  exit 1
fi

if [[ -z "$ZONE" ]]; then
  echo "Error: GCP zone must be provided via --zone or ZONE env var." >&2
  exit 1
fi

# Inform the user about the tunnel being created
echo "Creating SSH tunnel to F5‑TTS instance:"
echo "  Project:      $PROJECT_ID"
echo "  Zone:         $ZONE"
echo "  Instance:     $INSTANCE_NAME"
echo "  Local port:   $LOCAL_PORT"
echo "  Remote port:  $REMOTE_PORT"
echo

# Execute the tunnel command
gcloud compute ssh "$INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$ZONE" \
  -- -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "$@"
