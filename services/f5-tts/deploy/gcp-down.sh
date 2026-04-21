#!/usr/bin/env bash
# services/f5-tts/deploy/gcp-down.sh
# Tear‑down VM and clean up resources for the F5‑TTS service on GCP.

set -euo pipefail

# ----------------------------------------------------------------------
# Configuration – can be overridden via environment variables.
# ----------------------------------------------------------------------
# GCP project to operate in. Defaults to the currently configured project.
PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
# Zone where the VM lives. Adjust if your deployment uses a different zone.
ZONE="${GCP_ZONE:-us-central1-a}"
# Name of the Compute Engine instance created by the corresponding gcp‑up.sh.
INSTANCE_NAME="${GCP_INSTANCE_NAME:-f5-tts}"
# Name of the firewall rule that allows traffic to the instance.
FIREWALL_NAME="${GCP_FIREWALL_NAME:-allow-f5-tts}"

# Validate that we have a project set.
if [[ -z "$PROJECT" ]]; then
  echo "Error: GCP_PROJECT is not set and no default project is configured."
  exit 1
fi

echo "=== Starting GCP teardown for F5‑TTS ==="
echo "Project:   $PROJECT"
echo "Zone:      $ZONE"
echo "Instance:  $INSTANCE_NAME"
echo "Firewall:  $FIREWALL_NAME"
echo ""

# ----------------------------------------------------------------------
# Helper: check if a resource exists.
# ----------------------------------------------------------------------
resource_exists() {
  local type=$1   # e.g., "instances" or "firewall"
  local name=$2
  case "$type" in
    instances)
      gcloud compute instances list \
        --project "$PROJECT" \
        --zones "$ZONE" \
        --filter="name=$name" \
        --format="value(name)" \
        | grep -qx "$name"
      ;;
    firewall)
      gcloud compute firewall list \
        --project "$PROJECT" \
        --filter="name=$name" \
        --format="value(name)" \
        | grep -qx "$name"
      ;;
    *)
      return 1
      ;;
  esac
}

# ----------------------------------------------------------------------
# Delete the Compute Engine instance if it exists.
# ----------------------------------------------------------------------
if resource_exists instances "$INSTANCE_NAME"; then
  echo "Deleting Compute Engine instance '$INSTANCE_NAME'..."
  gcloud compute instances delete "$INSTANCE_NAME" \
    --project "$PROJECT" \
    --zone "$ZONE" \
    --quiet
else
  echo "Instance '$INSTANCE_NAME' not found – nothing to delete."
fi
echo ""

# ----------------------------------------------------------------------
# Delete the firewall rule if it exists.
# ----------------------------------------------------------------------
if resource_exists firewall "$FIREWALL_NAME"; then
  echo "Deleting firewall rule '$FIREWALL_NAME'..."
  gcloud compute firewall delete "$FIREWALL_NAME" \
    --project "$PROJECT" \
    --quiet
else
  echo "Firewall rule '$FIREWALL_NAME' not found – nothing to delete."
fi
echo ""

echo "=== GCP teardown for F5‑TTS completed successfully ==="
```