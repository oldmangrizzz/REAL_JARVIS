#!/usr/bin/env bash
# scripts/ci/canon-gate.sh
#
# Canon-gate verifier invoked by GitHub Actions. Fails any PR that modifies
# canon files (PRINCIPLES.md, SOUL_ANCHOR.md, VERIFICATION_PROTOCOL.md,
# CANON/**, Jarvis/Sources/JarvisCore/Canon/**) without a matching pair of
# detached dual signatures sitting next to each changed file:
#     <canon-file>.p256.sig      (ECDSA-P256 over SHA-256 of the file)
#     <canon-file>.ed25519.sig   (raw Ed25519 over the file bytes)
#
# Public keys are read from Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/.
#
# Exit codes:
#   0  — no canon files changed, or every changed canon file carries valid dual sigs.
#   1  — at least one changed canon file is missing or has invalid signatures.
#   2  — bad invocation / missing dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PUB_DIR="$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"

BASE="${1:-${GITHUB_BASE_REF:-origin/main}}"
HEAD="${2:-HEAD}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "canon-gate: openssl required" >&2
  exit 2
fi

is_canon() {
  local path="$1"
  case "$path" in
    PRINCIPLES.md|SOUL_ANCHOR.md|VERIFICATION_PROTOCOL.md) return 0 ;;
    CANON/*|Jarvis/Sources/JarvisCore/Canon/*) return 0 ;;
    *) return 1 ;;
  esac
}

changed_files=$(git -C "$REPO_ROOT" diff --name-only "$BASE" "$HEAD" 2>/dev/null || true)

canon_changed=()
for f in $changed_files; do
  if is_canon "$f"; then
    # Ignore sidecar .sig files themselves.
    case "$f" in *.p256.sig|*.ed25519.sig) continue ;; esac
    canon_changed+=("$f")
  fi
done

if [[ ${#canon_changed[@]} -eq 0 ]]; then
  echo "canon-gate: no canon files changed; pass."
  exit 0
fi

P256_PUB="$PUB_DIR/p256.pub.der"
ED_PUB_DER="$PUB_DIR/ed25519.pub.der"
ED_PUB_PEM="$PUB_DIR/ed25519.pub.pem"

if [[ ! -f "$P256_PUB" ]]; then
  echo "canon-gate: P-256 public key missing at $P256_PUB" >&2
  exit 2
fi

# Prefer PEM; derive from DER if needed.
if [[ ! -f "$ED_PUB_PEM" ]]; then
  if [[ -f "$ED_PUB_DER" ]]; then
    openssl pkey -pubin -inform DER -in "$ED_PUB_DER" -out "$ED_PUB_PEM" 2>/dev/null || true
  fi
fi
if [[ ! -f "$ED_PUB_PEM" ]]; then
  echo "canon-gate: Ed25519 public key missing at $ED_PUB_PEM (or $ED_PUB_DER)" >&2
  exit 2
fi

# P-256 pubkey → PEM for openssl dgst -verify.
P256_PUB_PEM="$(mktemp -t canon-gate-p256.XXXXXX.pem)"
trap 'rm -f "$P256_PUB_PEM"' EXIT
openssl pkey -pubin -inform DER -in "$P256_PUB" -out "$P256_PUB_PEM" 2>/dev/null

fail=0
for f in "${canon_changed[@]}"; do
  abs="$REPO_ROOT/$f"
  p256_sig="$abs.p256.sig"
  ed_sig="$abs.ed25519.sig"

  if [[ ! -f "$p256_sig" ]]; then
    echo "canon-gate: FAIL $f — missing $f.p256.sig"
    fail=1; continue
  fi
  if [[ ! -f "$ed_sig" ]]; then
    echo "canon-gate: FAIL $f — missing $f.ed25519.sig"
    fail=1; continue
  fi

  if ! openssl dgst -sha256 -verify "$P256_PUB_PEM" -signature "$p256_sig" "$abs" >/dev/null 2>&1; then
    echo "canon-gate: FAIL $f — P-256 signature invalid"
    fail=1; continue
  fi

  if ! openssl pkeyutl -verify -rawin -pubin -inkey "$ED_PUB_PEM" -in "$abs" -sigfile "$ed_sig" >/dev/null 2>&1; then
    echo "canon-gate: FAIL $f — Ed25519 signature invalid"
    fail=1; continue
  fi

  echo "canon-gate: OK   $f"
done

exit $fail
