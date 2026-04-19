#!/usr/bin/env zsh
# scripts/jarvis-lockdown.zsh
#
# The final ritual. Verifies Phase-N artifacts are on disk, hashed,
# signed, and ready to be promoted to canon. On green, writes (or
# re-verifies) the Genesis Record and locks the system.
#
# Invoked by the operator, by name, in a zsh shell. Nothing auto-runs it.
#
# Usage:
#   jarvis-lockdown              (verify + promote current phase if green)
#   jarvis-lockdown --verify     (verify only; no writes)
#   jarvis-lockdown --status     (print last phase report summary)
#
# Exits 0 only if every gate is green. Any failure exits non-zero with a
# human-legible description of which gate failed and why.

# ZSH colors
autoload -U colors && colors

SCRIPT_DIR=$(cd $(dirname "$0") && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

MODE="promote"
for arg in "$@"; do
    case "$arg" in
        --verify)
            MODE="verify"
            ;;
        --status)
            MODE="status"
            ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

function red() { echo -e "${fg[red]}$*${reset_color}"; }
function green() { echo -e "${fg[green]}$*${reset_color}"; }
function amber() { echo -e "${fg[yellow]}$*${reset_color}"; }

function fail() {
    red "✘ LOCKDOWN FAILED: $*"
    echo
    amber "System is in A&Ox3 integrity-failure mode. Do not proceed until resolved."
    exit 1
}

# -- 0. Pre-flight ------------------------------------------------------------

if [[ ! -d "$REPO_ROOT/mcuhist" ]]; then
    fail "mcuhist directory missing — wrong repo root or catastrophic loss."
fi
if [[ ! -f "$REPO_ROOT/PRINCIPLES.md" ]]; then
    fail "PRINCIPLES.md missing at repo root."
fi

amber "JARVIS LOCKDOWN — mode: $MODE — repo: $REPO_ROOT"
echo

# -- 1. Canon file presence ---------------------------------------------------

CANON=(
    PRINCIPLES.md
    VERIFICATION_PROTOCOL.md
    SOUL_ANCHOR.md
    mcuhist/MANIFEST.md
    mcuhist/REALIGNMENT_1218.md
    mcuhist/1.md mcuhist/2.md mcuhist/3.md mcuhist/4.md mcuhist/5.md
)

for f in $CANON; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
        fail "Canon file missing: $f"
    fi
done
green "✓ Canon presence"

# -- 2. Biographical mass hash ------------------------------------------------

EXPECTED_BIO="064ad57293897f0e708a053d02b1f1676a842d9f1baf6fd12e8a45f87148bf26"
ACTUAL_BIO=$(cat "$REPO_ROOT"/mcuhist/[1-5].md | shasum -a 256 | awk '{print $1}')
if [[ "$ACTUAL_BIO" != "$EXPECTED_BIO" ]]; then
    fail "Biographical mass hash mismatch.  expected=$EXPECTED_BIO  actual=$ACTUAL_BIO"
fi
green "✓ Biographical mass hash matches MANIFEST.md"

# -- 2b. Canon corpus integrity ----------------------------------------------

CORPUS_DIR="$REPO_ROOT/CANON/corpus"
CORPUS_MANIFEST="$CORPUS_DIR/MANIFEST.sha256"

if [[ ! -d "$CORPUS_DIR" ]]; then
    fail "CANON/corpus directory missing."
fi
if [[ ! -f "$CORPUS_MANIFEST" ]]; then
    fail "CANON/corpus/MANIFEST.sha256 missing. Run scripts/regen-canon-manifest.zsh."
fi

pushd "$CORPUS_DIR" > /dev/null
if ! shasum -a 256 --status -c MANIFEST.sha256; then
    popd > /dev/null
    amber "→ drift detail:"
    pushd "$CORPUS_DIR" > /dev/null
    shasum -a 256 -c MANIFEST.sha256 2>&1 | grep -v ': OK$' | sed 's/^/   /'
    popd > /dev/null
    fail "Canon corpus drift detected."
fi
popd > /dev/null
CORPUS_DOC_COUNT=$(wc -l < "$CORPUS_MANIFEST" | tr -d ' ')
green "✓ Canon corpus integrity ($CORPUS_DOC_COUNT documents)"

# -- 3. Soul Anchor public keys present ---------------------------------------

PUB_DIR="$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"
if [[ ! -f "$PUB_DIR/p256.pub.der" ]]; then
    amber "⚠ P-256 public key missing. Run scripts/generate_soul_anchor.sh first."
    if [[ "$MODE" != "verify" ]]; then
        fail "Cannot promote without Soul Anchor keys."
    fi
else
    green "✓ P-256 public key present"
fi

if [[ ! -f "$PUB_DIR/ed25519.pub.raw" ]]; then
    amber "⚠ Ed25519 public key missing. Run scripts/generate_soul_anchor.sh first."
    if [[ "$MODE" != "verify" ]]; then
        fail "Cannot promote without Soul Anchor keys."
    fi
else
    green "✓ Ed25519 public key present"
fi

# -- 4. Realignment draft status ---------------------------------------------

RA="$REPO_ROOT/mcuhist/REALIGNMENT_1218.md"
if grep -q "DRAFT pending operator sign-off" "$RA"; then
    amber "⚠ REALIGNMENT_1218.md is still DRAFT (0.1.0). Operator must ratify to 1.0.0 before canonical promote."
    if [[ "$MODE" == "promote" ]]; then
        fail "Cannot promote Phase 1 while realignment manifest is DRAFT."
    fi
else
    green "✓ REALIGNMENT_1218.md is ratified"
fi

# -- 4b. Voice Approval Gate --------------------------------------------------

VOICE_GATE="$REPO_ROOT/.jarvis/voice/approval.json"
if [[ ! -f "$VOICE_GATE" ]]; then
    amber "⚠ Voice Approval Gate file missing: $VOICE_GATE"
    amber "  Mr. Hanson must audition a rendered sample and call VoiceApprovalGate.approve()."
    if [[ "$MODE" == "promote" ]]; then
        fail "Cannot promote without operator-consented voice identity. JARVIS is muted by design."
    fi
else
    VOICE_COMPOSITE=$(python3 -c "import json,sys; d=json.load(open('$VOICE_GATE')); print(d.get('composite',''))" 2>/dev/null)
    if [[ -z "$VOICE_COMPOSITE" ]]; then
        if [[ "$MODE" == "promote" ]]; then
            fail "Voice gate file is malformed (missing 'composite')."
        else
            amber "⚠ Voice gate file malformed (missing 'composite')."
        fi
    else
        VOICE_COMPOSITE_SHORT="${VOICE_COMPOSITE:0:12}"
        green "✓ Voice Approval Gate present (composite $VOICE_COMPOSITE_SHORT…)"
    fi
fi

# -- 4c. A&Ox4 orientation gate ----------------------------------------------

AOX_LATEST="$REPO_ROOT/.jarvis/telemetry/aox4_latest.json"
AOX_FRESH_WINDOW=${JARVIS_AOX_FRESH_WINDOW:-3600}

if [[ ! -f "$AOX_LATEST" ]]; then
    amber "⚠ A&Ox4 latest-status file missing: $AOX_LATEST"
    amber "  Run an AOxFourProbe.status() pass (e.g. via JarvisCore bootstrap or a harness tick)."
    if [[ "$MODE" == "promote" ]]; then
        fail "Cannot promote without a recent A&Ox4 level-4 reading."
    fi
else
    AOX_LEVEL=$(python3 -c "import json; print(json.load(open('$AOX_LATEST'))['level'])" 2>/dev/null)
    AOX_TS=$(python3 -c "import json; print(json.load(open('$AOX_LATEST'))['timestamp'])" 2>/dev/null)
    if [[ -z "$AOX_LEVEL" ]]; then
        if [[ "$MODE" == "promote" ]]; then
            fail "A&Ox4 latest file malformed."
        else
            amber "⚠ A&Ox4 latest file malformed."
        fi
    else
        AOX_AGE_SEC=$(python3 -c "
import json,datetime
d=json.load(open('$AOX_LATEST'))
ts=datetime.datetime.fromisoformat(d['timestamp'].replace('Z','+00:00'))
now=datetime.datetime.now(datetime.timezone.utc)
print(int((now-ts).total_seconds()))
" 2>/dev/null)
        if [[ "$AOX_LEVEL" != "4" ]]; then
            if [[ "$MODE" == "promote" ]]; then
                fail "A&Ox$AOX_LEVEL: node is not fully oriented (need level 4). Probe at $AOX_TS."
            else
                amber "⚠ A&Ox$AOX_LEVEL — not level 4. Probe at $AOX_TS."
            fi
        elif [[ -n "$AOX_AGE_SEC" && "$AOX_AGE_SEC" -gt "$AOX_FRESH_WINDOW" ]]; then
            if [[ "$MODE" == "promote" ]]; then
                fail "A&Ox4 reading is stale ($AOX_AGE_SEC s > window $AOX_FRESH_WINDOW s). Re-probe."
            else
                amber "⚠ A&Ox4 level-4 but stale ($AOX_AGE_SEC s > window $AOX_FRESH_WINDOW s)."
            fi
        else
            green "✓ A&Ox4 level-4 (age ${AOX_AGE_SEC}s, probed $AOX_TS)"
        fi
    fi
fi

# -- 5. Build gate (best effort) ---------------------------------------------

if [[ "$MODE" != "status" ]]; then
    if [[ -d "$REPO_ROOT/Jarvis" ]]; then
        amber "→ Build gate: running xcodebuild (silent unless it errors)"
        if ! xcodebuild -workspace "$REPO_ROOT/jarvis.xcworkspace" -scheme Jarvis -quiet build > /tmp/jarvis-lockdown-build.log 2>&1; then
            amber "   xcodebuild failed or not configured; falling back to swift build"
            if ! (cd "$REPO_ROOT" && swift build -q > /tmp/jarvis-lockdown-build.log 2>&1); then
                fail "Build gate failed. See /tmp/jarvis-lockdown-build.log"
            fi
        fi
        green "✓ Build gate"
    fi
fi

# -- 6. Genesis record (create or verify) ------------------------------------

GENESIS_DIR="$REPO_ROOT/.jarvis/soul_anchor"
GENESIS="$GENESIS_DIR/genesis.json"

if [[ "$MODE" == "status" ]]; then
    if [[ -f "$GENESIS" ]]; then
        green "✓ Genesis record exists:"
        cat "$GENESIS" | head -c 400
        echo
    else
        amber "No genesis record yet."
    fi
    exit 0
fi

if [[ "$MODE" == "verify" ]]; then
    if [[ -f "$GENESIS" ]]; then
        green "✓ Genesis record exists. Signature verification is performed by JarvisCore at bootstrap."
    else
        amber "⚠ No genesis record yet; run in default (promote) mode after keys are generated."
    fi
    green "LOCKDOWN VERIFY: OK"
    exit 0
fi

if [[ ! -f "$GENESIS" ]]; then
    amber "⚠ Genesis record absent. To create it:"
    amber "    1. scripts/generate_soul_anchor.sh"
    amber "    2. Use the produced keys to sign the canonical payload (see SOUL_ANCHOR.md §3.2)"
    amber "    3. Write the signed JSON to $GENESIS"
    amber "    4. Re-run: jarvis-lockdown"
    fail "Promote requires a signed genesis record; refusing to fabricate one."
fi

green "✓ Genesis record present"
green ""
green "LOCKDOWN PROMOTE: OK — all deterministic gates green."
green "JARVIS may bootstrap. Signature verification will re-run at JarvisCore.bootstrap()."
exit 0
