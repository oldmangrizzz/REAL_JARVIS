#!/usr/bin/env bash
# scripts/setup-distribution-certs.sh
# Creates Apple Distribution + Developer ID Application certs via App Store
# Connect API, downloads them, installs to login keychain, creates provisioning
# profiles, and exports an .env file for the ship script to use.
#
# Requires: API key at ~/Downloads/AuthKey_25WMCHVZV8.p8
#           Team ID: T5AFHQ4L9C
#           Key ID: 25WMCHVZV8
set -euo pipefail

API_KEY_PATH="${HOME}/Downloads/AuthKey_25WMCHVZV8.p8"
KEY_ID="25WMCHVZV8"
TEAM_ID="T5AFHQ4L9C"
ISSUER_ID="${ASC_ISSUER_ID:-}"
API_ROOT="https://api.appstoreconnect.apple.com/v1"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

die() { echo "$*" >&2; exit 1; }

[[ -f "$API_KEY_PATH" ]] || die "API key not found: $API_KEY_PATH"

# ── JWT generation ─────────────────────────────────────────────────────────────
# App Store Connect JWT: ES256, header {alg:ES256,kid:KEY_ID,typ:JWT}
# payload: {iss:ISSUER_ID,iat:now,exp:now+1200,aud:appstoreconnect-v1}
generate_jwt() {
  local header payload sig
  header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
  local now
  now="$(date +%s)"
  local exp=$((now + 1200))
  # If ISSUER_ID not set, try to derive from the key ID — but we need it.
  [[ -n "$ISSUER_ID" ]] || die "Set ASC_ISSUER_ID env var (from App Store Connect > Users and Access > Keys)"
  payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "$ISSUER_ID" "$now" "$exp" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
  # Sign with the private key
  sig="$(printf '%s' "$header.$payload" | openssl dgst -sha256 -sign "$API_KEY_PATH" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
  printf '%s.%s.%s\n' "$header" "$payload" "$sig"
}

JWT=""
ensure_jwt() { [[ -n "${JWT:-}" ]] || JWT="$(generate_jwt)"; }

# ── Helpers ──────────────────────────────────────────────────────────────────
asc_get() {
  ensure_jwt
  curl -sf -H "Authorization: Bearer $JWT" "$API_ROOT$1"
}

asc_post() {
  ensure_jwt
  curl -sf -X POST "$API_ROOT$1" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    -d "$2"
}

# ── 1. List existing certs ─────────────────────────────────────────────────────
echo "[cert-setup] Checking existing certificates..."
EXISTING_CERTS="$(asc_get /certificates)"
APPLE_DIST_EXISTS="$(echo "$EXISTING_CERTS" | grep -c 'APPLE_DISTRIBUTION' || true)"
DEV_ID_APP_EXISTS="$(echo "$EXISTING_CERTS" | grep -c 'DEVELOPER_ID_APPLICATION' || true)"
echo "[cert-setup] APPLE_DISTRIBUTION certs: $APPLE_DIST_EXISTS"
echo "[cert-setup] DEVELOPER_ID_APPLICATION certs: $DEV_ID_APP_EXISTS"

# ── 2. Generate CSR ──────────────────────────────────────────────────────────
CSR_PATH="$TMP_DIR/jarvis.csr"
KEY_PATH="$TMP_DIR/jarvis.key"
openssl genrsa -out "$KEY_PATH" 2048 2>/dev/null
openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" \
  -subj "/CN=Jarvis Distribution Cert/O=GrizzlyMedicine Research Institute/C=US" 2>/dev/null
echo "[cert-setup] CSR generated"

# ── 3. Create Apple Distribution cert ─────────────────────────────────────────
if [[ "$APPLE_DIST_EXISTS" -eq 0 ]]; then
  echo "[cert-setup] Creating APPLE_DISTRIBUTION certificate..."
  CSR_B64="$(openssl base64 -e -A -in "$CSR_PATH")"
  RESPONSE="$(asc_post /certificates "{\"data\":{\"type\":\"certificates\",\"attributes\":{\"certificateType\":\"APPLE_DISTRIBUTION\",\"csrContent\":\"$CSR_B64\"}}}")"
  if [[ -n "$RESPONSE" ]]; then
    echo "$RESPONSE" | tee "$TMP_DIR/apple_dist_response.json" >/dev/null
    echo "[cert-setup] Apple Distribution cert created"
  else
    echo "[cert-setup] WARN: cert creation returned empty — may already exist or API error"
  fi
else
  echo "[cert-setup] Apple Distribution cert already exists — skipping creation"
fi

# ── 4. Create Developer ID Application cert ──────────────────────────────────
if [[ "$DEV_ID_APP_EXISTS" -eq 0 ]]; then
  echo "[cert-setup] Creating DEVELOPER_ID_APPLICATION certificate..."
  CSR_B64="$(openssl base64 -e -A -in "$CSR_PATH")"
  RESPONSE="$(asc_post /certificates "{\"data\":{\"type\":\"certificates\",\"attributes\":{\"certificateType\":\"DEVELOPER_ID_APPLICATION\",\"csrContent\":\"$CSR_B64\"}}}")"
  if [[ -n "$RESPONSE" ]]; then
    echo "$RESPONSE" | tee "$TMP_DIR/dev_id_response.json" >/dev/null
    echo "[cert-setup] Developer ID Application cert created"
  else
    echo "[cert-setup] WARN: cert creation returned empty — may already exist or API error"
  fi
else
  echo "[cert-setup] Developer ID Application cert already exists — skipping creation"
fi

# ── 5. Download certs ────────────────────────────────────────────────────────
# Re-list to get the cert IDs
echo "[cert-setup] Re-listing certificates for download..."
CERT_LIST="$(asc_get /certificates)"

download_cert() {
  local cert_id="$1"
  local out_name="$2"
  local cert_data
  cert_data="$(asc_get "/certificates/$cert_id" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['attributes']['certificateContent'])" 2>/dev/null || true)"
  if [[ -n "$cert_data" ]]; then
    echo "$cert_data" | openssl base64 -d -A > "$TMP_DIR/$out_name.cer"
    echo "[cert-setup] Downloaded $out_name.cer"
  else
    echo "[cert-setup] WARN: could not download cert $cert_id"
  fi
}

# Extract cert IDs
echo "$CERT_LIST" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('data', []):
    t = c['attributes']['certificateType']
    i = c['id']
    print(f'{t}:{i}')
" > "$TMP_DIR/cert_ids.txt" 2>/dev/null || true

while IFS=: read -r ctype cid; do
  [[ -n "$cid" ]] || continue
  case "$ctype" in
    APPLE_DISTRIBUTION) download_cert "$cid" "apple_dist" ;;
    DEVELOPER_ID_APPLICATION) download_cert "$cid" "dev_id_app" ;;
  esac
done < "$TMP_DIR/cert_ids.txt"

# ── 6. Install to keychain ───────────────────────────────────────────────────
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
for cert in "$TMP_DIR"/*.cer; do
  [[ -e "$cert" ]] || continue
  echo "[cert-setup] Installing $(basename "$cert") to login keychain..."
  security import "$cert" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security || true
  # Also import the private key so the cert is usable
  security import "$KEY_PATH" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security || true
done

# ── 7. Create provisioning profiles ──────────────────────────────────────────
# We need bundle IDs first
echo "[cert-setup] Checking bundle IDs..."
BUNDLE_LIST="$(asc_get /bundleIds)"
# For now, just report. Profile creation needs explicit bundle ID resource IDs.
echo "[cert-setup] Bundle IDs:"
echo "$BUNDLE_LIST" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for b in d.get('data', []):
    print(' ', b['attributes']['identifier'], '-', b['id'])
" 2>/dev/null || true

# ── 8. Write deploy env ──────────────────────────────────────────────────────
ENV_FILE="${HOME}/.jarvis/deploy-env"
mkdir -p "$(dirname "$ENV_FILE")"
{
  echo "export JARVIS_ASC_API_KEY_PATH=\"$API_KEY_PATH\""
  echo "export JARVIS_ASC_KEY_ID=\"$KEY_ID\""
  echo "export JARVIS_ASC_TEAM_ID=\"$TEAM_ID\""
  echo "export JARVIS_ASC_ISSUER_ID=\"$ISSUER_ID\""
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "[cert-setup] Deploy env written to $ENV_FILE"

echo "[cert-setup] DONE."
