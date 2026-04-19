#!/usr/bin/env bash
# scripts/generate_soul_anchor.sh
#
# Generates the Soul Anchor dual-root key material for JARVIS.
#
#   - P-256 (operational root, on Mac)   — Secure Enclave if available,
#                                           Keychain fallback via openssl+security.
#   - Ed25519 (cold root, on phone)      — INGEST-ONLY. The private key is
#                                           generated on the operator's iPhone
#                                           (see scripts/jarvis_cold_sign_setup.md).
#                                           This script reads only the 32-byte
#                                           raw PUBLIC half from a file path
#                                           the operator supplies.
#
# PRIVATE KEY MATERIAL NEVER TOUCHES THIS SCRIPT OR THIS WORKSTATION FOR THE
# COLD ROOT. The P-256 private half lives in Secure Enclave/Keychain on this
# Mac and is never written to disk in plaintext. No private bytes are ever
# printed, piped, or logged.
#
# Run this on the operator's workstation. Do NOT run it inside any LLM
# agent session, do NOT paste its output (other than the printed
# fingerprints) back into any model context.
#
# Usage:
#   scripts/generate_soul_anchor.sh --ed25519-pub /path/to/ed25519.pub.raw
#   scripts/generate_soul_anchor.sh --ed25519-pub-hex /path/to/ed25519.pub.hex
#
# Produces:
#   Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/p256.pub.der      (P-256 public, DER)
#   Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/p256.fingerprint
#   Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/ed25519.pub.raw   (Ed25519 public, 32 bytes)
#   Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/ed25519.fingerprint
#   Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/README.txt
#
# If neither --ed25519-pub nor --ed25519-pub-hex is supplied, the script
# will generate P-256 only and leave an Ed25519 placeholder, so the
# operator can complete the phone-side flow at a separate time.

set -euo pipefail

# --- find repo root -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUB_DIR="$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"
mkdir -p "$PUB_DIR"

# --- arg parse ----------------------------------------------------------------

ED_PUB_PATH=""
ED_PUB_HEX_PATH=""
SKIP_P256=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ed25519-pub) ED_PUB_PATH="$2"; shift 2;;
    --ed25519-pub-hex) ED_PUB_HEX_PATH="$2"; shift 2;;
    --skip-p256) SKIP_P256=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# --- sanity: not running inside an LLM agent ----------------------------------

if [[ -n "${CLAUDE_AGENT:-}${COPILOT_AGENT:-}${GEMINI_AGENT:-}${OPENAI_AGENT:-}${ANTHROPIC_AGENT:-}" ]]; then
  echo "ABORT: LLM agent environment detected. The Soul Anchor generator must not run inside a model context." >&2
  exit 3
fi

umask 077

# --- P-256 operational root (on this Mac) ------------------------------------

if [[ "$SKIP_P256" -eq 0 ]]; then
  echo "[1/3] Generating P-256 operational root (on this Mac)..."
  SE_HELPER="$REPO_ROOT/scripts/secure_enclave_p256.swift"
  if [[ -x "$SE_HELPER" ]] || ([[ -f "$SE_HELPER" ]] && command -v swift >/dev/null 2>&1); then
    echo "       using Secure Enclave helper at $SE_HELPER"
    swift "$SE_HELPER" --emit-public-der "$PUB_DIR/p256.pub.der"
  else
    echo "       Secure Enclave helper not present; generating software P-256 and importing to Keychain"
    P256_PRIV_TMP="$(mktemp -t jarvis_p256_priv.XXXXXX)"
    trap 'shred -u "$P256_PRIV_TMP" 2>/dev/null || rm -f "$P256_PRIV_TMP"' EXIT
    openssl ecparam -name prime256v1 -genkey -noout -out "$P256_PRIV_TMP" >/dev/null
    openssl ec -in "$P256_PRIV_TMP" -pubout -outform DER -out "$PUB_DIR/p256.pub.der" 2>/dev/null
    P12_TMP="$(mktemp -t jarvis_p256_p12.XXXXXX).p12"
    openssl pkcs12 -export -nocerts -inkey "$P256_PRIV_TMP" \
      -out "$P12_TMP" -passout pass:jarvis-soul-anchor >/dev/null
    security import "$P12_TMP" -k "$HOME/Library/Keychains/login.keychain-db" \
      -P jarvis-soul-anchor -A >/dev/null 2>&1 || true
    rm -f "$P12_TMP"
  fi
  P256_FP="$(shasum -a 256 "$PUB_DIR/p256.pub.der" | awk '{print $1}')"
  echo "$P256_FP" > "$PUB_DIR/p256.fingerprint"
else
  echo "[1/3] Skipping P-256 generation (--skip-p256)."
  if [[ -f "$PUB_DIR/p256.pub.der" ]]; then
    P256_FP="$(shasum -a 256 "$PUB_DIR/p256.pub.der" | awk '{print $1}')"
  else
    P256_FP="<not generated>"
  fi
fi

# --- Ed25519 cold root (ingest from phone) -----------------------------------

ED_FP="<not ingested>"
ED_STATUS="PENDING — run scripts/jarvis_cold_sign_setup.md on phone, then re-run this script with --ed25519-pub"

if [[ -n "$ED_PUB_PATH" ]]; then
  echo "[2/3] Ingesting Ed25519 cold root public key from: $ED_PUB_PATH"
  if [[ ! -f "$ED_PUB_PATH" ]]; then
    echo "ABORT: file not found: $ED_PUB_PATH" >&2
    exit 4
  fi
  SIZE=$(wc -c < "$ED_PUB_PATH" | tr -d ' ')
  if [[ "$SIZE" -ne 32 ]]; then
    echo "ABORT: expected raw 32-byte Ed25519 public key, got $SIZE bytes." >&2
    echo "       If you have a DER- or PEM-encoded key, extract the 32-byte raw first." >&2
    exit 4
  fi
  cp "$ED_PUB_PATH" "$PUB_DIR/ed25519.pub.raw"
  chmod 0644 "$PUB_DIR/ed25519.pub.raw"
  ED_FP="$(shasum -a 256 "$PUB_DIR/ed25519.pub.raw" | awk '{print $1}')"
  echo "$ED_FP" > "$PUB_DIR/ed25519.fingerprint"
  ED_STATUS="OK"
elif [[ -n "$ED_PUB_HEX_PATH" ]]; then
  echo "[2/3] Ingesting Ed25519 cold root public key (hex) from: $ED_PUB_HEX_PATH"
  if [[ ! -f "$ED_PUB_HEX_PATH" ]]; then
    echo "ABORT: file not found: $ED_PUB_HEX_PATH" >&2
    exit 4
  fi
  HEX="$(tr -d '[:space:]:' < "$ED_PUB_HEX_PATH")"
  if [[ ! "$HEX" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "ABORT: expected 64 hex chars (32 bytes), got: ${#HEX} chars." >&2
    exit 4
  fi
  echo -n "$HEX" | xxd -r -p > "$PUB_DIR/ed25519.pub.raw"
  SIZE=$(wc -c < "$PUB_DIR/ed25519.pub.raw" | tr -d ' ')
  if [[ "$SIZE" -ne 32 ]]; then
    echo "ABORT: decoded bytes != 32 ($SIZE)." >&2
    rm -f "$PUB_DIR/ed25519.pub.raw"
    exit 4
  fi
  chmod 0644 "$PUB_DIR/ed25519.pub.raw"
  ED_FP="$(shasum -a 256 "$PUB_DIR/ed25519.pub.raw" | awk '{print $1}')"
  echo "$ED_FP" > "$PUB_DIR/ed25519.fingerprint"
  ED_STATUS="OK"
else
  echo "[2/3] No Ed25519 public key supplied."
  echo "       See scripts/jarvis_cold_sign_setup.md for the phone-side flow."
  echo "       Re-run with --ed25519-pub /path/to/ed25519.pub.raw once complete."
fi

# --- README -------------------------------------------------------------------

echo "[3/3] Writing pubkeys README..."
cat > "$PUB_DIR/README.txt" <<EOF
Soul Anchor public keys for JARVIS.

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Host:      $(scutil --get ComputerName 2>/dev/null || hostname)
Operator:  Robert Barclay Hanson, EMT-P (Ret.) & Theoretical Futurist
           Founder, GrizzlyMedicine Research Institute

Files:
  p256.pub.der          — operational root, DER-encoded P-256 public key
                          (private half: Secure Enclave / Keychain on this Mac)
  p256.fingerprint      — SHA-256 of p256.pub.der
  ed25519.pub.raw       — cold root, raw 32-byte Ed25519 public key
                          (private half: iPhone, see jarvis_cold_sign_setup.md)
  ed25519.fingerprint   — SHA-256 of ed25519.pub.raw

NO PRIVATE BYTES ARE STORED IN THIS DIRECTORY. This directory is safe to
commit to a non-secret repo; the contents are public verifier material.
EOF

echo
echo "======================= SOUL ANCHOR FINGERPRINTS ======================="
echo "P-256   (operational, this Mac):    $P256_FP"
echo "Ed25519 (cold root,  on phone):     $ED_FP"
echo "Ed25519 status:                     $ED_STATUS"
echo "========================================================================"
echo
echo "RECORD THESE FINGERPRINTS BY HAND in .secrets.env (P256_PUBKEY_FINGERPRINT"
echo "and ED25519_PUBKEY_FINGERPRINT). They are your out-of-band verifiers."
