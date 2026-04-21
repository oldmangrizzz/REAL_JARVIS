#!/usr/bin/env bash
#
# gcp-up.sh - Deploy the F5‑TTS service to Google Cloud Platform.
#
# This script performs the following actions:
#   1. Builds and pushes the Docker image for the F5‑TTS service.
#   2. Creates (or updates) a Secret Manager secret containing Swift credentials.
#   3. Ensures a firewall rule allowing inbound traffic to the service port.
#   4. Provisions a Compute Engine VM (if not already present).
#   5. Starts the F5‑TTS service (and its renamed watchdog) on the VM.
#
# The script is idempotent where possible and will abort on any error.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated.
#   - Docker installed locally (for building the image).
#   - The environment variables for Swift credentials must be set.
#
# Required environment variables:
#   PROJECT_ID          GCP project identifier.
#   REGION              GCP region (e.g., us-central1).
#   ZONE                GCP zone within the region (e.g., us-central1-a).
#   SERVICE_NAME        Name of the service (default: f5-tts).
#   SERVICE_PORT        Port the container listens on (default: 8080).
#   SWIFT_AUTH_URL      Swift authentication URL.
#   SWIFT_USERNAME      Swift username.
#   SWIFT_PASSWORD      Swift password.
#   SWIFT_TENANT        Swift tenant/project name.
#   SWIFT_REGION        Swift region (optional, may be required by the backend).
#
# Usage:
#   ./gcp-up.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
SERVICE_NAME="${SERVICE_NAME:-f5-tts}"
SERVICE_PORT="${SERVICE_PORT:-8080}"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}:latest"
INSTANCE_NAME="${SERVICE_NAME}-instance"
FIREWALL_RULE_NAME="${SERVICE_NAME}-allow-http"
SECRET_NAME="${SERVICE_NAME}-swift-cred"
WATCHDOG_BINARY="f5-tts-watchdog"
DOCKERFILE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/Dockerfile"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $*"
}

error() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
    exit 1
}

require_env() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        error "Environment variable ${var_name} is required but not set."
    fi
}

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
require_env "PROJECT_ID"
require_env "SWIFT_AUTH_URL"
require_env "SWIFT_USERNAME"
require_env "SWIFT_PASSWORD"
require_env "SWIFT_TENANT"

# ---------------------------------------------------------------------------
# Build and push Docker image
# ---------------------------------------------------------------------------
build_and_push_image() {
    log "Building Docker image ${IMAGE_NAME} ..."
    docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE_PATH}" .

    log "Pushing Docker image to Container Registry ..."
    gcloud auth configure-docker -q
    docker push "${IMAGE_NAME}"
}

# ---------------------------------------------------------------------------
# Create or update Secret Manager secret with Swift credentials
# ---------------------------------------------------------------------------
ensure_swift_secret() {
    log "Ensuring Secret Manager secret ${SECRET_NAME} exists ..."
    if ! gcloud secrets list --project="${PROJECT_ID}" --filter="name:${SECRET_NAME}" --format="value(name)" | grep -q "${SECRET_NAME}"; then
        gcloud secrets create "${SECRET_NAME}" --project="${PROJECT_ID}" --replication-policy="automatic"
        log "Secret ${SECRET_NAME} created."
    else
        log "Secret ${SECRET_NAME} already exists."
    fi

    # Prepare JSON payload
    local payload
    payload=$(jq -n \
        --arg auth_url "${SWIFT_AUTH_URL}" \
        --arg username "${SWIFT_USERNAME}" \
        --arg password "${SWIFT_PASSWORD}" \
        --arg tenant "${SWIFT_TENANT}" \
        --arg region "${SWIFT_REGION:-}" \
        '{
            auth_url: $auth_url,
            username: $username,
            password: $password,
            tenant: $tenant,
            region: $region
        }')

    # Add a new version (overwrites previous)
    echo "${payload}" | gcloud secrets versions add "${SECRET_NAME}" \
        --project="${PROJECT_ID}" \
        --data-file=-
    log "Swift credentials stored in secret ${SECRET_NAME} (new version added)."
}

# ---------------------------------------------------------------------------
# Ensure firewall rule exists
# ---------------------------------------------------------------------------
ensure_firewall_rule() {
    log "Ensuring firewall rule ${FIREWALL_RULE_NAME} allows TCP:${SERVICE_PORT} ..."
    if ! gcloud compute firewall-rules list --project="${PROJECT_ID}" --filter="name=${FIREWALL_RULE_NAME}" --format="value(name)" | grep -q "${FIREWALL_RULE_NAME}"; then
        gcloud compute firewall-rules create "${FIREWALL_RULE_NAME}" \
            --project="${PROJECT_ID}" \
            --allow="tcp:${SERVICE_PORT}" \
            --target-tags="${SERVICE_NAME}" \
            --description="Allow inbound HTTP traffic to ${SERVICE_NAME}" \
            --direction=INGRESS \
            --priority=1000 \
            --network=default
        log "Firewall rule ${FIREWALL_RULE_NAME} created."
    else
        log "Firewall rule ${FIREWALL_RULE_NAME} already exists."
    fi
}

# ---------------------------------------------------------------------------
# Provision Compute Engine VM (if not already present)
# ---------------------------------------------------------------------------
ensure_instance() {
    log "Ensuring Compute Engine instance ${INSTANCE_NAME} exists ..."
    if ! gcloud compute instances list --project="${PROJECT_ID}" --filter="name=${INSTANCE_NAME}" --format="value(name)" | grep -q "${INSTANCE_NAME}"; then
        gcloud compute instances create "${INSTANCE_NAME}" \
            --project="${PROJECT_ID}" \
            --zone="${ZONE}" \
            --machine-type="e2-medium" \
            --tags="${SERVICE_NAME}" \
            --image-family="debian-11" \
            --image-project="debian-cloud" \
            --boot-disk-size="20GB" \
            --metadata="startup-script=$(cat <<'EOF'
#!/bin/bash
# Install Docker if not present
if ! command -v docker >/dev/null 2>&1; then
    apt-get update && apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker
fi
EOF
)" \
            --scopes="cloud-platform"
        log "Instance ${INSTANCE_NAME} created."
    else
        log "Instance ${INSTANCE_NAME} already exists."
    fi
}

# ---------------------------------------------------------------------------
# Deploy and start the service on the VM
# ---------------------------------------------------------------------------
deploy_service_on_instance() {
    log "Deploying F5‑TTS service on instance ${INSTANCE_NAME} ..."
    local remote_cmd
    remote_cmd=$(cat <<'EOS'
#!/bin/bash
set -euo pipefail

# Pull latest image
docker pull "${IMAGE_NAME}"

# Stop and remove any existing container
if docker ps -a --format "{{.Names}}" | grep -q "^f5-tts$"; then
    docker stop f5-tts && docker rm f5-tts
fi

# Run the container
docker run -d \
    --name f5-tts \
    --restart unless-stopped \
    -p ${SERVICE_PORT}:8080 \
    -e SWIFT_SECRET_NAME="${SECRET_NAME}" \
    -e GOOGLE_CLOUD_PROJECT="${PROJECT_ID}" \
    "${IMAGE_NAME}"

# Install and start the renamed watchdog (if not already present)
if ! command -v ${WATCHDOG_BINARY} >/dev/null 2>&1; then
    # Assume the binary is bundled inside the container at /usr/local/bin/f5-tts-watchdog
    docker cp f5-tts:/usr/local/bin/${WATCHDOG_BINARY} /usr/local/bin/${WATCHDOG_BINARY}
    chmod +x /usr/local/bin/${WATCHDOG_BINARY}
    # Create a simple systemd service
    cat <<'EOF' > /etc/systemd/system/${WATCHDOG_BINARY}.service
[Unit]
Description=F5‑TTS Watchdog
After=network.target docker.service

[Service]
ExecStart=/usr/local/bin/${WATCHDOG_BINARY} --container f5-tts
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${WATCHDOG_BINARY}.service
    systemctl start ${WATCHDOG_BINARY}.service
fi
EOS
)

    # Replace placeholders with actual values before sending
    remote_cmd="${remote_cmd//\${IMAGE_NAME}/${IMAGE_NAME}}"
    remote_cmd="${remote_cmd//\${SERVICE_PORT}/${SERVICE_PORT}}"
    remote_cmd="${remote_cmd//\${SECRET_NAME}/${SECRET_NAME}}"
    remote_cmd="${remote_cmd//\${PROJECT_ID}/${PROJECT_ID}}"
    remote_cmd="${remote_cmd//\${WATCHDOG_BINARY}/${WATCHDOG_BINARY}}"

    gcloud compute ssh "${INSTANCE_NAME}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --command="${remote_cmd}"
    log "Service deployment completed on ${INSTANCE_NAME}."
}

# ---------------------------------------------------------------------------
# Main execution flow
# ---------------------------------------------------------------------------
main() {
    log "Starting deployment of ${SERVICE_NAME} to project ${PROJECT_ID} ..."
    build_and_push_image
    ensure_swift_secret
    ensure_firewall_rule
    ensure_instance
    deploy_service_on_instance
    log "Deployment of ${SERVICE_NAME} finished successfully."
}

main "$@"
