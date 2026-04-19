#!/usr/bin/env bash
# Rotate the JARVIS VibeVoice service bearer token.
# Run this any time the bearer may have been exposed (terminal trace,
# screenshot shared, etc.) Container picks up new bearer on next VM boot.
set -e
PROJECT=grizzly-helicarrier-586794
NEW=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
echo -n "$NEW" | gcloud secrets versions add jarvis-vibevoice-bearer \
    --data-file=- --project="$PROJECT"
echo
echo "[rotate] new bearer staged in Secret Manager."
echo "[rotate] If a VM is currently running, recreate it with gcp-up.sh"
echo "[rotate] to pull the new bearer. Otherwise the next bring-up handles it."
