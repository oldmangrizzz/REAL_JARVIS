#!/usr/bin/env bash
# rotate-bearer.sh
# Rotates the bearer token secret used by the F5‑TTS service.
# The script obtains a fresh access token from the configured OAuth endpoint
# and stores it in a Kubernetes secret.

set -euo pipefail

# -------------------------------------------------------------------------
# Configuration (environment variables)
# -------------------------------------------------------------------------
# Required:
#   F5_TTS_TOKEN_URL      – OAuth token endpoint (e.g. https://auth.example.com/oauth2/token)
#   F5_TTS_CLIENT_ID      – OAuth client identifier
#   F5_TTS_CLIENT_SECRET  – OAuth client secret
#
# Optional (with defaults):
#   K8S_NAMESPACE               – Kubernetes namespace where the secret lives (default: default)
#   F5_TTS_BEARER_SECRET_NAME   – Name of the secret to create/update (default: f5-tts-bearer)
#
# Example usage:
#   export F5_TTS_TOKEN_URL="https://auth.example.com/oauth2/token"
#   export F5_TTS_CLIENT_ID="my-client-id"
#   export F5_TTS_CLIENT_SECRET="my-client-secret"
#   export K8S_NAMESPACE="production"
#   export F5_TTS_BEARER_SECRET_NAME="f5-tts-bearer"
#   ./rotate-bearer.sh
# -------------------------------------------------------------------------

# Helper to print usage
usage() {
    cat <<EOF
Usage: ${0##*/}
Rotates the bearer token secret for the F5‑TTS service.

Required environment variables:
  F5_TTS_TOKEN_URL       OAuth token endpoint URL
  F5_TTS_CLIENT_ID       OAuth client ID
  F5_TTS_CLIENT_SECRET   OAuth client secret

Optional environment variables:
  K8S_NAMESPACE          Kubernetes namespace (default: default)
  F5_TTS_BEARER_SECRET_NAME  Secret name (default: f5-tts-bearer)

The script will:
  1. Request a new access token using client‑credentials grant.
  2. Store the token in a Kubernetes generic secret (key: BEARER_TOKEN).
EOF
    exit 1
}

# Verify required tools are present
for cmd in curl jq kubectl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found in PATH." >&2
        exit 1
    fi
done

# Load configuration
TOKEN_URL="${F5_TTS_TOKEN_URL:-}"
CLIENT_ID="${F5_TTS_CLIENT_ID:-}"
CLIENT_SECRET="${F5_TTS_CLIENT_SECRET:-}"
NAMESPACE="${K8S_NAMESPACE:-default}"
SECRET_NAME="${F5_TTS_BEARER_SECRET_NAME:-f5-tts-bearer}"

# Validate required variables
if [[ -z "$TOKEN_URL" || -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
    echo "Error: one or more required environment variables are missing." >&2
    usage
fi

echo "Obtaining new access token from $TOKEN_URL..."

# Request a new token using client‑credentials grant
TOKEN_RESPONSE=$(curl -sS -X POST "$TOKEN_URL" \
    -d "grant_type=client_credentials" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -H "Accept: application/json")

# Extract the token; jq will fail if the response is not valid JSON
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: failed to obtain access token. Response:" >&2
    echo "$TOKEN_RESPONSE" >&2
    exit 1
fi

echo "Access token obtained successfully."

# Create or update the Kubernetes secret
# Using --dry-run=client ensures we generate the manifest locally before applying.
echo "Updating secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
    --from-literal=BEARER_TOKEN="$ACCESS_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '$SECRET_NAME' has been updated with the new bearer token."
```