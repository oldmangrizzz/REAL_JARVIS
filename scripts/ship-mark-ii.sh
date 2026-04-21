#!/usr/bin/env bash

# scripts/ship-mark-ii.sh
# Unified deployment script for Mark II with optional rollback, smoke testing,
# macOS code signing & notarization, F5‑TTS deployment, PWA sync, LaunchAgent reload,
# Convex mutation recording, and iMessage notification.

set -euo pipefail

# -------------------------- Configuration --------------------------

# Paths (adjust as needed for your repo layout)
APP_BUNDLE="build/MarkII.app"
SMOKE_RUNNER="scripts/smoke-runner.sh"
F5_TTS_DEPLOY="services/f5-tts/deploy/gcp-up.sh"
PWA_SOURCE="pwa/dist/"
PWA_DEST="user@remote.server:/var/www/pwa/"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.example.markii.plist"

# Convex API
CONVEX_ENDPOINT="https://api.convex.dev/ships:record"
# Expect CONVEX_TOKEN env var to be set with a bearer token.

# iMessage
# Set MESSAGE_RECIPIENT env var to the iMessage handle (e.g., "+1234567890" or "john@example.com")
# Set MESSAGE_SENDER   env var to your own iMessage handle if needed.
# If not set, the script will skip the notification step.

# Apple notarization (requires APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD env vars)
# APPLE_ID: your Apple developer Apple ID
# APPLE_APP_SPECIFIC_PASSWORD: app‑specific password for notarization

# -------------------------- Helper Functions --------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --dry-run               Show what would be done without executing commands.
  --rollback <sha>        Roll back the repository to the given commit SHA and exit.
  -h, --help              Show this help message.
EOF
    exit 1
}

log() {
    echo "[${BASH_SOURCE[0]}] $*"
}

run() {
    if $DRY_RUN; then
        echo "[DRY RUN] $*"
    else
        log "Running: $*"
        eval "$@"
    fi
}

require_env() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        log "ERROR: Environment variable $var_name is not set."
        exit 1
    fi
}

# -------------------------- Argument Parsing --------------------------

DRY_RUN=false
ROLLBACK_SHA=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --rollback)
            if [[ -z "${2:-}" ]]; then
                log "ERROR: --rollback requires a commit SHA."
                usage
            fi
            ROLLBACK_SHA="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log "ERROR: Unknown argument: $1"
            usage
            ;;
    esac
done

# -------------------------- Rollback Path --------------------------

if [[ -n "$ROLLBACK_SHA" ]]; then
    log "Rolling back repository to commit $ROLLBACK_SHA"
    run "git fetch --all"
    run "git checkout $ROLLBACK_SHA"
    log "Rollback complete. Exiting."
    exit 0
fi

# -------------------------- Pre‑flight Checks --------------------------

log "Starting pre‑flight checks..."

# Ensure we are on a clean working tree
if [[ -n "$(git status --porcelain)" ]]; then
    log "ERROR: Working tree is dirty. Please commit or stash changes before deploying."
    exit 1
fi

# Ensure we are on the expected branch (e.g., main)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    log "WARNING: You are on branch '$CURRENT_BRANCH'. Deployment is usually performed from 'main' or 'master'."
    read -rp "Continue anyway? (y/N): " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log "Aborting deployment."
        exit 1
    fi
fi

# Verify required tools are available
for cmd in git codesign xcrun launchctl rsync curl osascript; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "ERROR: Required command '$cmd' not found in PATH."
        exit 1
    fi
done

# Verify optional env vars for later steps
if [[ -n "${CONVEX_TOKEN:-}" ]]; then
    log "Convex token detected."
else
    log "INFO: CONVEX_TOKEN not set – Convex mutation recording will be skipped."
fi

if [[ -n "${MESSAGE_RECIPIENT:-}" ]]; then
    log "iMessage recipient detected."
else
    log "INFO: MESSAGE_RECIPIENT not set – iMessage notification will be skipped."
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    log "Apple notarization credentials detected."
else
    log "INFO: Apple notarization credentials not set – notarization will be skipped."
fi

log "Pre‑flight checks passed."

# -------------------------- Smoke Test --------------------------

if [[ -x "$SMOKE_RUNNER" ]]; then
    log "Running smoke tests via $SMOKE_RUNNER"
    run "\"$SMOKE_RUNNER\""
else
    log "ERROR: Smoke runner script not found or not executable at $SMOKE_RUNNER"
    exit 1
fi

# -------------------------- Code Signing & Notarization --------------------------

if [[ -d "$APP_BUNDLE" ]]; then
    log "Signing macOS app bundle at $APP_BUNDLE"
    # Adjust the signing identity as needed
    SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)"
    run "codesign --deep --force --verify --verbose --options runtime --sign \"$SIGN_IDENTITY\" \"$APP_BUNDLE\""

    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        log "Submitting app for notarization"
        # Create a zip for notarization
        ZIP_NAME="MarkII-${USER}-$(date +%s).zip"
        run "ditto -c -k --keepParent \"$APP_BUNDLE\" \"$ZIP_NAME\""
        run "xcrun altool --notarize-app -f \"$ZIP_NAME\" -u \"$APPLE_ID\" -p \"$APPLE_APP_SPECIFIC_PASSWORD\" --output-format xml"
        # Note: In a real script you would poll for notarization status and staple the ticket.
        # For brevity, we assume success here.
        run "rm \"$ZIP_NAME\""
    else
        log "Skipping notarization (Apple credentials not set)."
    fi
else
    log "ERROR: App bundle not found at $APP_BUNDLE"
    exit 1
fi

# -------------------------- Deploy F5‑TTS --------------------------

if [[ -x "$F5_TTS_DEPLOY" ]]; then
    log "Deploying F5‑TTS via $F5_TTS_DEPLOY"
    run "\"$F5_TTS_DEPLOY\""
else
    log "ERROR: F5‑TTS deploy script not found or not executable at $F5_TTS_DEPLOY"
    exit 1
fi

# -------------------------- Sync PWA --------------------------

if [[ -d "$PWA_SOURCE" ]]; then
    log "Syncing PWA from $PWA_SOURCE to $PWA_DEST"
    run "rsync -avz --delete \"$PWA_SOURCE\" \"$PWA_DEST\""
else
    log "ERROR: PWA source directory not found at $PWA_SOURCE"
    exit 1
fi

# -------------------------- Reload LaunchAgents --------------------------

if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
    log "Reloading LaunchAgent $LAUNCH_AGENT_PLIST"
    run "launchctl unload \"$LAUNCH_AGENT_PLIST\" || true"
    run "launchctl load \"$LAUNCH_AGENT_PLIST\""
else
    log "WARNING: LaunchAgent plist not found at $LAUNCH_AGENT_PLIST – skipping reload."
fi

# -------------------------- Record Convex Mutation --------------------------

if [[ -n "${CONVEX_TOKEN:-}" ]]; then
    CURRENT_SHA=$(git rev-parse HEAD)
    log "Recording deployment mutation to Convex (SHA=$CURRENT_SHA)"
    JSON_PAYLOAD=$(cat <<EOF
{
    "type": "mark-ii-deploy",
    "sha": "$CURRENT_SHA",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    run "curl -s -X POST \"$CONVEX_ENDPOINT\" \\
        -H \"Authorization: Bearer $CONVEX_TOKEN\" \\
        -H \"Content-Type: application/json\" \\
        -d '$JSON_PAYLOAD'"
else
    log "Skipping Convex mutation recording (CONVEX_TOKEN not set)."
fi

# -------------------------- iMessage Notification --------------------------

if [[ -n "${MESSAGE_RECIPIENT:-}" ]]; then
    SHORT_SHA=$(git rev-parse --short HEAD)
    MESSAGE="🚀 Mark II deployed – commit $SHORT_SHA"
    log "Sending iMessage to $MESSAGE_RECIPIENT"
    # AppleScript to send iMessage
    OSASCRIPT=$(cat <<'EOS'
on run argv
    set theMessage to item 1 of argv
    set theRecipient to item 2 of argv
    tell application "Messages"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to buddy theRecipient of targetService
        send theMessage to targetBuddy
    end tell
end run
EOS
)
    if $DRY_RUN; then
        echo "[DRY RUN] osascript would be executed with message: $MESSAGE"
    else
        echo "$OSASCRIPT" | osascript - "$MESSAGE" "$MESSAGE_RECIPIENT"
    fi
else
    log "Skipping iMessage notification (MESSAGE_RECIPIENT not set)."
fi

log "Mark II deployment completed successfully."

exit 0