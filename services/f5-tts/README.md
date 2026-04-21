# JARVIS F5-TTS Service

High-quality, zero-shot voice cloning service using F5-TTS (SWivid).
Replaces VibeVoice-1.5B for lower latency, better prosody, and English-stable output.

## Deploy Runbook (GCP)

### First-time Setup

```bash
export GCP_PROJECT_ID="grizzly-helicarrier-586794"
export GCP_REGION="us-central1"

# 1. Create Service Account
gcloud iam service-accounts create jarvis-f5-tts-sa --display-name "JARVIS F5-TTS runtime"

# 2. Assign Permissions
gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:jarvis-f5-tts-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role roles/artifactregistry.reader

gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member "serviceAccount:jarvis-f5-tts-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role roles/secretmanager.secretAccessor

# 3. Create Bearer Secret
# Generate a token: python3 -c "import secrets; print(secrets.token_urlsafe(48))"
echo -n "YOUR_TOKEN" | gcloud secrets create jarvis-f5-tts-bearer --data-file=-

# 4. Create Artifact Registry Repo (if not exists)
gcloud artifacts repositories create jarvis --repository-format=docker --location="$GCP_REGION"

# 5. Build and Push Image
docker build -t "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/f5-tts:latest" .
docker push "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/f5-tts:latest"

# 6. Create Firewall Rule
gcloud compute firewall-rules create jarvis-f5-tts-iap \
    --direction=INGRESS --action=ALLOW --rules=tcp:8000 --source-ranges=35.235.240.0/20 \
    --target-tags=jarvis-f5-tts
```

### Daily Flow

```bash
# Bring up VM (Spot T4)
./deploy/gcp-up.sh

# Start Tunnel (in a background tab)
./deploy/gcp-tunnel.sh

# The watchdog will automatically pick up the new IP and update ~/.jarvis/tts.env
```

## Audition + Approval Flow

Since F5-TTS has a different voice fingerprint than VibeVoice, the `VoiceApprovalGate` will block speech until a new audition is approved.

1. **Audition the new model:**
   ```bash
   Jarvis voice-audition "Hello Grizzly. This is the new F5-TTS engine. I'm ready to cook."
   ```
2. **Listen to the output:**
   Open the WAV file printed by the audition command.
3. **Approve the voice:**
   ```bash
   Jarvis voice-approve grizzly "f5-tts matrix-01 2026-04-20"
   ```

## Rollback

To revert to VibeVoice in < 5 mins:
1. `cd services/vibevoice-tts/`
2. `./deploy/gcp-up.sh`
3. Update `~/.jarvis/vibevoice.env` or let the watchdog handle it (if still pointing to vibevoice).
4. Re-approve the VibeVoice fingerprint if you wiped the approval file.
