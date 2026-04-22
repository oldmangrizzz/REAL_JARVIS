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
REPO_ROOT="${CANON_GATE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PUB_DIR="${CANON_GATE_PUB_DIR:-$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys}"

if [[ "${1:-}" == "--self-test" ]]; then
  # Inline self-test harness covering MK2-EPIC-08 §2 acceptance list:
  #   1. valid_dual_signature_pass
  #   2. missing_p256_sig_reject
  #   3. missing_ed25519_sig_reject
  #   4. tampered_canon_file_reject
  #   5. unrelated_file_ignored
  # Each case builds an ephemeral git repo + ephemeral dual-root keypair,
  # invokes the gate, and asserts exit code. No real canon is touched; no
  # private key material leaves the sandbox's tmpdir.
  set +e
  SANDBOX="$(mktemp -d -t canon-gate-selftest.XXXXXX)"
  trap 'rm -rf "$SANDBOX"' EXIT
  pass=0; fail=0
  assert_exit() {
    local label="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
      echo "canon-gate selftest: PASS $label (exit=$got)"
      pass=$((pass+1))
    else
      echo "canon-gate selftest: FAIL $label (want=$want got=$got)"
      fail=$((fail+1))
    fi
  }
  make_case() {
    local name="$1"
    local dir="$SANDBOX/$name"
    mkdir -p "$dir/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"
    git -C "$dir" init -q
    git -C "$dir" config user.email selftest@local
    git -C "$dir" config user.name selftest
    openssl ecparam -name prime256v1 -genkey -noout -out "$dir/p256.key.pem" 2>/dev/null
    openssl ec -in "$dir/p256.key.pem" -pubout -outform DER \
      -out "$dir/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/p256.pub.der" 2>/dev/null
    openssl genpkey -algorithm ED25519 -out "$dir/ed.key.pem" 2>/dev/null
    openssl pkey -in "$dir/ed.key.pem" -pubout \
      -out "$dir/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/ed25519.pub.pem" 2>/dev/null
    echo "$dir"
  }
  sign_dual() {
    local dir="$1" file="$2"
    openssl dgst -sha256 -sign "$dir/p256.key.pem" \
      -out "$dir/$file.p256.sig" "$dir/$file"
    openssl pkeyutl -sign -rawin -inkey "$dir/ed.key.pem" \
      -in "$dir/$file" -out "$dir/$file.ed25519.sig"
  }
  run_gate() {
    local dir="$1" base="$2" head="$3"
    ( cd "$dir" && CANON_GATE_REPO_ROOT="$dir" \
        CANON_GATE_PUB_DIR="$dir/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys" \
        bash "$SCRIPT_DIR/canon-gate.sh" "$base" "$head" >/dev/null 2>&1 )
    echo $?
  }

  # Case 1: valid_dual_signature_pass
  d=$(make_case valid)
  ( cd "$d" && git add . && git commit -q -m base )
  BASE_SHA=$(git -C "$d" rev-parse HEAD)
  echo "v1" > "$d/PRINCIPLES.md"
  sign_dual "$d" PRINCIPLES.md
  ( cd "$d" && git add . && git commit -q -m canon )
  assert_exit valid_dual_signature_pass 0 "$(run_gate "$d" "$BASE_SHA" HEAD)"

  # Case 2: missing_p256_sig_reject
  d=$(make_case miss_p256)
  ( cd "$d" && git add . && git commit -q -m base )
  BASE_SHA=$(git -C "$d" rev-parse HEAD)
  echo "v1" > "$d/PRINCIPLES.md"
  sign_dual "$d" PRINCIPLES.md
  rm "$d/PRINCIPLES.md.p256.sig"
  ( cd "$d" && git add -A && git commit -q -m canon )
  assert_exit missing_p256_sig_reject 1 "$(run_gate "$d" "$BASE_SHA" HEAD)"

  # Case 3: missing_ed25519_sig_reject
  d=$(make_case miss_ed)
  ( cd "$d" && git add . && git commit -q -m base )
  BASE_SHA=$(git -C "$d" rev-parse HEAD)
  echo "v1" > "$d/PRINCIPLES.md"
  sign_dual "$d" PRINCIPLES.md
  rm "$d/PRINCIPLES.md.ed25519.sig"
  ( cd "$d" && git add -A && git commit -q -m canon )
  assert_exit missing_ed25519_sig_reject 1 "$(run_gate "$d" "$BASE_SHA" HEAD)"

  # Case 4: tampered_canon_file_reject
  d=$(make_case tampered)
  ( cd "$d" && git add . && git commit -q -m base )
  BASE_SHA=$(git -C "$d" rev-parse HEAD)
  echo "v1" > "$d/PRINCIPLES.md"
  sign_dual "$d" PRINCIPLES.md
  echo "tamper" >> "$d/PRINCIPLES.md"
  ( cd "$d" && git add -A && git commit -q -m canon )
  assert_exit tampered_canon_file_reject 1 "$(run_gate "$d" "$BASE_SHA" HEAD)"

  # Case 5: unrelated_file_ignored
  d=$(make_case unrelated)
  ( cd "$d" && git add . && git commit -q -m base )
  BASE_SHA=$(git -C "$d" rev-parse HEAD)
  mkdir -p "$d/Jarvis/Sources/JarvisCore/Other"
  echo "noncanon" > "$d/Jarvis/Sources/JarvisCore/Other/Plain.swift"
  echo "also noncanon" > "$d/README-extra.md"
  ( cd "$d" && git add -A && git commit -q -m noncanon )
  assert_exit unrelated_file_ignored 0 "$(run_gate "$d" "$BASE_SHA" HEAD)"

  echo "canon-gate selftest: $pass passed, $fail failed"
  [[ $fail -eq 0 ]] && exit 0 || exit 1
fi

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
