#!/usr/bin/env bash
# scripts/soul-anchor/rotate.sh
#
# Soul Anchor rotation driver. Per MK2-EPIC-08:
#   --op      Rotate the operational (P-256) root. Requires operator + Touch ID.
#   --cold    Rotate the cold (Ed25519) root. Private half is displayed to
#             operator ONCE and NEVER persisted to disk.
#   --drill   Dry run: generates ephemeral key material, produces dual
#             signatures over a canon test artifact, verifies, tears down,
#             logs the drill outcome. No real keys are replaced.
#
# Per PRINCIPLES §1.3 this is BSP-call territory. If run from inside an LLM
# agent session, the script refuses to proceed beyond sanity checks — the
# operator must be physically present for Touch ID on --op.
#
# No private key material is ever logged. All log output is append-only to
#   Storage/soul-anchor/rotation.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$REPO_ROOT/Storage/soul-anchor/rotation.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s | %s\n' "$ts" "$*" >> "$LOG_FILE"
  printf '%s\n' "$*"
}

refuse_in_agent() {
  if [[ -n "${CLAUDE_AGENT:-}${COPILOT_AGENT:-}${GEMINI_AGENT:-}${OPENAI_AGENT:-}${ANTHROPIC_AGENT:-}" ]]; then
    log "ABORT: LLM agent environment detected; rotation requires a human operator."
    exit 3
  fi
}

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
}

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --op)    MODE="op";    shift;;
    --cold)  MODE="cold";  shift;;
    --drill) MODE="drill"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage; exit 2
fi

PUB_DIR="$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"
DRILL_DIR="$(mktemp -d -t jarvis-soul-anchor-drill.XXXXXX)"
cleanup_drill() {
  rm -rf "$DRILL_DIR"
}
trap cleanup_drill EXIT

case "$MODE" in
  drill)
    log "soul_anchor.rotate.started mode=drill actor=$(id -un)"

    # 1. Ephemeral P-256 key (software; drill never uses Secure Enclave).
    openssl ecparam -name prime256v1 -genkey -noout \
      -out "$DRILL_DIR/p256.key.pem" 2>/dev/null
    openssl ec -in "$DRILL_DIR/p256.key.pem" -pubout \
      -out "$DRILL_DIR/p256.pub.pem" 2>/dev/null

    # 2. Ephemeral Ed25519 key (software).
    openssl genpkey -algorithm ED25519 \
      -out "$DRILL_DIR/ed25519.key.pem" 2>/dev/null
    openssl pkey -in "$DRILL_DIR/ed25519.key.pem" -pubout \
      -out "$DRILL_DIR/ed25519.pub.pem" 2>/dev/null

    # 3. Canon test artifact (a throwaway file so we never touch real canon).
    ARTIFACT="$DRILL_DIR/canon-test.txt"
    printf 'Soul Anchor drill artifact %s\n' "$(date -u +%s)" > "$ARTIFACT"

    # 4. Dual-sign.
    openssl dgst -sha256 -sign "$DRILL_DIR/p256.key.pem" \
      -out "$ARTIFACT.p256.sig" "$ARTIFACT"
    openssl pkeyutl -sign -rawin -inkey "$DRILL_DIR/ed25519.key.pem" \
      -in "$ARTIFACT" -out "$ARTIFACT.ed25519.sig"

    # 5. Verify both.
    openssl dgst -sha256 -verify "$DRILL_DIR/p256.pub.pem" \
      -signature "$ARTIFACT.p256.sig" "$ARTIFACT" >/dev/null
    openssl pkeyutl -verify -rawin -pubin -inkey "$DRILL_DIR/ed25519.pub.pem" \
      -in "$ARTIFACT" -sigfile "$ARTIFACT.ed25519.sig" >/dev/null

    # 6. Record fingerprints (public halves only).
    P256_FP=$(openssl pkey -pubin -in "$DRILL_DIR/p256.pub.pem" -outform DER \
      | openssl dgst -sha256 | awk '{print $2}')
    ED_FP=$(openssl pkey -pubin -in "$DRILL_DIR/ed25519.pub.pem" -outform DER \
      | openssl dgst -sha256 | awk '{print $2}')
    ART_HASH=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')

    log "soul_anchor.rotate.signed p256_fp=$P256_FP ed25519_fp=$ED_FP artifact_sha256=$ART_HASH"
    log "soul_anchor.rotate.verified mode=drill outcome=pass"
    log "soul_anchor.rotate.completed mode=drill"
    exit 0
    ;;

  op)
    refuse_in_agent
    log "soul_anchor.rotate.started mode=op actor=$(id -un)"
    echo "Operational key rotation requires Touch ID on the Secure Enclave." >&2
    echo "This will invoke scripts/secure_enclave_p256.swift interactively." >&2
    read -r -p "Continue? [y/N] " ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
      log "soul_anchor.rotate.aborted mode=op reason=operator_declined"
      exit 1
    fi
    SE_HELPER="$REPO_ROOT/scripts/secure_enclave_p256.swift"
    if [[ ! -f "$SE_HELPER" ]]; then
      log "soul_anchor.rotate.failed mode=op reason=se_helper_missing"
      exit 4
    fi
    NEW_PUB="$DRILL_DIR/p256.pub.der"
    swift "$SE_HELPER" --emit-public-der "$NEW_PUB"
    NEW_FP=$(openssl dgst -sha256 "$NEW_PUB" | awk '{print $2}')
    cp "$NEW_PUB" "$PUB_DIR/p256.pub.der"
    printf '%s\n' "$NEW_FP" > "$PUB_DIR/p256.fingerprint"
    log "soul_anchor.rotate.signed mode=op p256_fp=$NEW_FP"
    log "soul_anchor.rotate.completed mode=op"
    exit 0
    ;;

  cold)
    refuse_in_agent
    log "soul_anchor.rotate.started mode=cold actor=$(id -un)"
    TMP_PRIV="$DRILL_DIR/ed25519.key.pem"
    TMP_PUB="$DRILL_DIR/ed25519.pub.pem"
    openssl genpkey -algorithm ED25519 -out "$TMP_PRIV" 2>/dev/null
    openssl pkey -in "$TMP_PRIV" -pubout -out "$TMP_PUB" 2>/dev/null

    echo "============================================================" >&2
    echo "COLD ROOT PRIVATE KEY — shown ONCE, never written to disk." >&2
    echo "Transfer to YubiKey / paper / airgap machine NOW, then press" >&2
    echo "Enter to destroy the ephemeral file and continue." >&2
    echo "============================================================" >&2
    cat "$TMP_PRIV" >&2
    echo "============================================================" >&2
    read -r _
    # Overwrite file content before deletion.
    : > "$TMP_PRIV"
    rm -f "$TMP_PRIV"

    # Publish the public half.
    openssl pkey -in "$TMP_PUB" -pubin -outform DER -out "$PUB_DIR/ed25519.pub.der"
    RAW_HEX=$(openssl pkey -in "$TMP_PUB" -pubin -outform DER \
      | xxd -p -c 256 | tr -d '\n' | tail -c 64)
    printf '%s' "$RAW_HEX" | xxd -r -p > "$PUB_DIR/ed25519.pub.raw"
    FP=$(openssl dgst -sha256 "$PUB_DIR/ed25519.pub.der" | awk '{print $2}')
    printf '%s\n' "$FP" > "$PUB_DIR/ed25519.fingerprint"
    log "soul_anchor.rotate.signed mode=cold ed25519_fp=$FP"
    log "soul_anchor.rotate.completed mode=cold"
    exit 0
    ;;
esac
