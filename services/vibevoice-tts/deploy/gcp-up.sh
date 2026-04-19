#!/usr/bin/env bash
# Bring up the JARVIS VibeVoice T4 spot instance on GCP.
# Prereqs (one-time, run once per project before first invocation):
#   gcloud auth login
#   gcloud config set project "$GCP_PROJECT_ID"
#   gcloud services enable compute.googleapis.com artifactregistry.googleapis.com iap.googleapis.com
#   gcloud iam service-accounts create jarvis-vibevoice-sa --display-name "JARVIS VibeVoice runtime"
#   gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
#       --member "serviceAccount:jarvis-vibevoice-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
#       --role roles/artifactregistry.reader
#   gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
#       --member "serviceAccount:jarvis-vibevoice-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
#       --role roles/secretmanager.secretAccessor
#   echo -n "$RANDOM_BEARER" | gcloud secrets create jarvis-vibevoice-bearer --data-file=-
#   gcloud artifacts repositories create jarvis --repository-format=docker --location="$GCP_REGION"
#   docker build -t "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/vibevoice-tts:latest" .
#   docker push "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/vibevoice-tts:latest"
#   gcloud compute firewall-rules create jarvis-vibevoice-iap \
#       --direction=INGRESS --action=ALLOW --rules=tcp:8000 --source-ranges=35.235.240.0/20 \
#       --target-tags=jarvis-vibevoice
#
# Then the daily flow is just:
#   ./deploy/gcp-up.sh
#   # ... use it ...
#   ./deploy/gcp-down.sh
set -euo pipefail

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
INSTANCE_NAME="${INSTANCE_NAME:-jarvis-vibevoice-t4}"
MACHINE_TYPE="${MACHINE_TYPE:-n1-standard-4}"
IMAGE_TAG="${IMAGE_TAG:-${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/vibevoice-tts:latest}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-jarvis-vibevoice-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com}"
BEARER_SECRET="${BEARER_SECRET:-jarvis-vibevoice-bearer}"
DISK_SIZE_GB="${DISK_SIZE_GB:-100}"

if gcloud compute instances describe "$INSTANCE_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
  echo "[gcp-up] instance $INSTANCE_NAME already exists; doing nothing."
  exit 0
fi

# Startup script runs on the VM. Pulls the image, fetches the bearer
# from Secret Manager, runs the container with --gpus all.
STARTUP_SCRIPT=$(cat <<'EOSH'
#!/usr/bin/env bash
set -eux
# Wait for nvidia drivers (deep-learning image already includes them).
for _ in $(seq 1 60); do nvidia-smi >/dev/null 2>&1 && break; sleep 5; done
# Install docker + nvidia-container-toolkit (Ubuntu 22.04 DL image does not ship them).
if ! command -v docker >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
  # nvidia-container-toolkit-base is preinstalled by the DL image; install matching version of toolkit.
  TOOLKIT_VERSION=$(dpkg-query -W -f='${Version}' nvidia-container-toolkit-base 2>/dev/null || echo "")
  if [ -n "$TOOLKIT_VERSION" ]; then
    apt-get install -y --allow-downgrades "nvidia-container-toolkit=${TOOLKIT_VERSION}" "libnvidia-container-tools=${TOOLKIT_VERSION}" "libnvidia-container1=${TOOLKIT_VERSION}"
  else
    apt-get install -y nvidia-container-toolkit
  fi
  nvidia-ctk runtime configure --runtime=docker
  systemctl enable --now docker
fi
# Configure docker to auth against artifact registry.
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet || true
# Resolve metadata.
IMAGE_TAG=$(curl -fsSL -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/image-tag)
BEARER_SECRET=$(curl -fsSL -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/bearer-secret)
BEARER_VALUE=$(gcloud secrets versions access latest --secret="$BEARER_SECRET")
docker pull "$IMAGE_TAG"
docker rm -f vibevoice 2>/dev/null || true
docker run -d --name vibevoice --restart=on-failure:5 --gpus all \
    -p 8000:8000 \
    -e VIBEVOICE_BEARER="$BEARER_VALUE" \
    -e VIBEVOICE_IDLE_SECONDS=1800 \
    -v /models:/models \
    "$IMAGE_TAG"
EOSH
)

echo "[gcp-up] creating $INSTANCE_NAME (spot T4) in $GCP_ZONE"
gcloud compute instances create "$INSTANCE_NAME" \
    --project="$GCP_PROJECT_ID" \
    --zone="$GCP_ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --accelerator="type=nvidia-tesla-t4,count=1" \
    --maintenance-policy=TERMINATE \
    --provisioning-model=SPOT \
    --instance-termination-action=DELETE \
    --image-family=common-cu129-ubuntu-2204-nvidia-580 \
    --image-project=deeplearning-platform-release \
    --boot-disk-size="${DISK_SIZE_GB}GB" \
    --boot-disk-type=pd-balanced \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=jarvis-vibevoice \
    --metadata=image-tag="$IMAGE_TAG",bearer-secret="$BEARER_SECRET" \
    --metadata-from-file=startup-script=<(echo "$STARTUP_SCRIPT")

echo "[gcp-up] waiting for container to come up (first boot will pull image)..."
for i in $(seq 1 60); do
  if gcloud compute ssh "$INSTANCE_NAME" --zone="$GCP_ZONE" --tunnel-through-iap \
       --command="curl -sf http://localhost:8000/healthz" >/dev/null 2>&1; then
    echo "[gcp-up] healthz OK"
    break
  fi
  sleep 10
done

cat <<EOM

[gcp-up] DONE.

To tunnel from this Mac:
  gcloud compute start-iap-tunnel "$INSTANCE_NAME" 8000 \\
    --local-host-port=localhost:8000 --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID"

Then export for the JARVIS CLI:
  set -x JARVIS_TTS_URL http://localhost:8000/tts/synthesize
  set -x JARVIS_TTS_BEARER (gcloud secrets versions access latest --secret=$BEARER_SECRET)
  set -x JARVIS_TTS_IDENTIFIER vibevoice/VibeVoice-1.5B
  set -x JARVIS_TTS_VOICE_LABEL vibevoice-1.5b-clone
  set -x JARVIS_TTS_SAMPLE_RATE 24000
EOM
