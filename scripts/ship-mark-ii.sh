#!/usr/bin/env bash
#
# ship-mark-ii.sh
#
# Operator‑invoked ship script for Mark II.
#   * Validates the git repository state.
#   * Runs the unified smoke suite.
#   * Signs and notarizes the macOS app.
#   * Deploys the F5‑TTS service.
#   * Syncs the PWA to the production host.
#   * Reloads LaunchAgents.
#   * Records the ship in Convex.
#   * Sends an iMessage notification.
#
# Supports:
#   --dry-run   : Echo commands instead of executing them.
#   --rollback  : Attempt to roll back the most recent ship.
#   -h|--help   : Show usage.

set -euo pipefail

# ------------------------------
# Configuration (adjust as needed)
# ------------------------------

# Git
GIT_REMOTE="origin"
GIT_BRANCH="main"

# Smoke suite
SMOKE_SCRIPT="./scripts/smoke-mark-ii.sh"

# App signing
APP_BUNDLE="./dist/MarkII.app"
ENTITLEMENTS="./signing/entitlements.plist"
SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)"
NOTARIZE_API_KEY="YOUR_NOTARIZE_API_KEY"
NOTARIZE_API_ISSUER="YOUR_NOTARIZE_API_ISSUER"

# Deployment
APP_INSTALL_DIR="/Applications"
F5_TTS_SERVICE_DIR="/usr/local/f5-tts"
PWA_SOURCE_DIR="./pwa"
PWA_REMOTE_USER="deploy"
PWA_REMOTE_HOST="pwa.example.com"
PWA_REMOTE_PATH="/var/www/pwa"

# LaunchAgent
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.example.markii.plist"

# Convex
CONVEX_ENDPOINT="https://api.convex.dev/shipments"
CONVEX_API_KEY="YOUR_CONVEX_API_KEY"

# iMessage
IMESSAGE_RECIPIENT="John Doe"
IMESSAGE_SERVICE="iMessage"

# ------------------------------
# Helper functions
# ------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "DRY RUN: $*"
    else
        eval "$@"
    fi
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--rollback] [-h|--help]

  --dry-run   Echo commands instead of executing them.
  --rollback  Attempt to roll back the most recent ship.
  -h, --help  Show this help message.
EOF
    exit 0
}

# ------------------------------
# Argument parsing
# ------------------------------

DRY_RUN=0
ROLLBACK=0

while (( "$#" )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --rollback)
            ROLLBACK=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# ------------------------------
# Git validation
# ------------------------------

validate_git() {
    log "Validating git repository state..."

    # Ensure we are on the expected branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "$GIT_BRANCH" ]]; then
        die "Current branch is '$current_branch'; expected '$GIT_BRANCH'."
    fi

    # Ensure there are no uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        die "Uncommitted changes detected. Please commit or stash them before shipping."
    fi

    # Fetch and ensure local is up‑to‑date with remote
    run "git fetch $GIT_REMOTE"
    local_hash=$(git rev-parse "$GIT_BRANCH")
    remote_hash=$(git rev-parse "$GIT_REMOTE/$GIT_BRANCH")
    if [[ "$local_hash" != "$remote_hash" ]]; then
        die "Local branch is not up‑to‑date with $GIT_REMOTE/$GIT_BRANCH."
    fi

    log "Git repository is clean and up‑to‑date."
}

# ------------------------------
# Smoke suite
# ------------------------------

run_smoke() {
    log "Running smoke suite..."
    if [[ ! -x "$SMOKE_SCRIPT" ]]; then
        die "Smoke script not found or not executable: $SMOKE_SCRIPT"
    fi
    run "\"$SMOKE_SCRIPT\""
    log "Smoke suite passed."
}

# ------------------------------
# Signing & notarization
# ------------------------------

sign_and_notarize() {
    log "Signing the app bundle..."
    run "codesign --deep --force --options runtime \\
        --entitlements \"$ENTITLEMENTS\" \\
        -s \"$SIGN_IDENTITY\" \"$APP_BUNDLE\""

    log "Creating zip for notarization..."
    ZIP_PATH="${APP_BUNDLE}.zip"
    run "ditto -c -k --keepParent \"$APP_BUNDLE\" \"$ZIP_PATH\""

    log "Submitting for notarization..."
    NOTARIZE_UUID=$(run "xcrun altool --notarize-app \\
        --primary-bundle-id com.example.markii \\
        --username \"$NOTARIZE_API_KEY\" \\
        --password \"@keychain:$NOTARIZE_API_ISSUER\" \\
        --file \"$ZIP_PATH\" \\
        --output-format xml | xmllint --xpath 'string(//notarization-upload-request/@id)' -")
    log "Notarization request ID: $NOTARIZE_UUID"

    log "Waiting for notarization to complete (polling every 30s)..."
    while true; do
        STATUS=$(run "xcrun altool --notarization-info \"$NOTARIZE_UUID\" \\
            --username \"$NOTARIZE_API_KEY\" \\
            --password \"@keychain:$NOTARIZE_API_ISSUER\" \\
            --output-format xml | xmllint --xpath 'string(//notarization-info/@status)' -")
        if [[ "$STATUS" == "success" ]]; then
            log "Notarization succeeded."
            break
        elif [[ "$STATUS" == "invalid" ]]; then
            die "Notarization failed."
        else
            log "Notarization status: $STATUS – sleeping..."
            sleep 30
        fi
    done

    log "Stapling notarization ticket..."
    run "xcrun stapler staple \"$APP_BUNDLE\""
    log "Signing and notarization complete."
}

# ------------------------------
# Deploy F5‑TTS service
# ------------------------------

deploy_f5_tts() {
    log "Deploying F5‑TTS service..."
    # Example: copy built service binary and resources
    SERVICE_SRC="./dist/f5-tts"
    if [[ ! -d "$SERVICE_SRC" ]]; then
        die "F5‑TTS service directory not found: $SERVICE_SRC"
    fi
    run "sudo mkdir -p \"$F5_TTS_SERVICE_DIR\""
    run "sudo cp -R \"$SERVICE_SRC\"/* \"$F5_TTS_SERVICE_DIR\""
    run "sudo chmod -R 755 \"$F5_TTS_SERVICE_DIR\""
    log "F5‑TTS service deployed to $F5_TTS_SERVICE_DIR."
}

# ------------------------------
# Sync PWA
# ------------------------------

sync_pwa() {
    log "Syncing PWA to production host..."
    if [[ ! -d "$PWA_SOURCE_DIR" ]]; then
        die "PWA source directory not found: $PWA_SOURCE_DIR"
    fi
    run "rsync -avz --delete \"$PWA_SOURCE_DIR/\" \"$PWA_REMOTE_USER@$PWA_REMOTE_HOST:$PWA_REMOTE_PATH/\""
    log "PWA sync complete."
}

# ------------------------------
# Reload LaunchAgents
# ------------------------------

reload_launch_agents() {
    log "Reloading LaunchAgent..."
    if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
        run "launchctl unload \"$LAUNCH_AGENT_PLIST\" || true"
        run "launchctl load \"$LAUNCH_AGENT_PLIST\""
        log "LaunchAgent reloaded."
    else
        log "LaunchAgent plist not found at $LAUNCH_AGENT_PLIST – skipping."
    fi
}

# ------------------------------
# Record ship in Convex
# ------------------------------

record_ship() {
    log "Recording ship in Convex..."
    COMMIT_HASH=$(git rev-parse HEAD)
    VERSION=$(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString || echo "unknown")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    JSON=$(cat <<EOF
{
    "commit": "$COMMIT_HASH",
    "version": "$VERSION",
    "timestamp": "$TIMESTAMP",
    "dryRun": $(($DRY_RUN))
}
EOF
)
    run "curl -s -X POST \"$CONVEX_ENDPOINT\" \\
        -H \"Authorization: Bearer $CONVEX_API_KEY\" \\
        -H \"Content-Type: application/json\" \\
        -d '$JSON'"
    log "Ship recorded."
}

# ------------------------------
# iMessage notification
# ------------------------------

notify_imessage() {
    log "Sending iMessage notification..."
    MESSAGE="🚢 Mark II shipped: version $VERSION (commit $COMMIT_HASH)"
    run "osascript -e 'tell application \"Messages\"' \\
        -e 'set targetService to 1st service whose service type = iMessage' \\
        -e 'set targetBuddy to buddy \"$IMESSAGE_RECIPIENT\" of targetService' \\
        -e 'send \"$MESSAGE\" to targetBuddy' \\
        -e 'end tell'"
    log "Notification sent."
}

# ------------------------------
# Rollback logic
# ------------------------------

rollback() {
    log "Starting rollback procedure..."

    # 1. Revert git to previous commit (assumes last ship was a tag named ship-<timestamp>)
    LAST_TAG=$(git tag --list "ship-*" --sort=-creatordate | head -n1 || true)
    if [[ -z "$LAST_TAG" ]]; then
        die "No ship tag found to roll back to."
    fi
    log "Rolling back to tag $LAST_TAG"
    run "git checkout $LAST_TAG"

    # 2. Remove deployed app
    APP_PATH="$APP_INSTALL_DIR/MarkII.app"
    if [[ -d "$APP_PATH" ]]; then
        log "Removing deployed app at $APP_PATH"
        run "sudo rm -rf \"$APP_PATH\""
    fi

    # 3. Stop and remove F5‑TTS service
    if [[ -d "$F5_TTS_SERVICE_DIR" ]]; then
        log "Removing F5‑TTS service directory $F5_TTS_SERVICE_DIR"
        run "sudo rm -rf \"$F5_TTS_SERVICE_DIR\""
    fi

    # 4. Revert PWA sync (best‑effort: rsync from a backup if available)
    # Placeholder – implement as needed.

    # 5. Unload LaunchAgent
    if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
        log "Unloading LaunchAgent"
        run "launchctl unload \"$LAUNCH_AGENT_PLIST\" || true"
    fi

    # 6. Record rollback in Convex
    COMMIT_HASH=$(git rev-parse HEAD)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    JSON=$(cat <<EOF
{
    "commit": "$COMMIT_HASH",
    "action": "rollback",
    "timestamp": "$TIMESTAMP",
    "dryRun": $(($DRY_RUN))
}
EOF
)
    run "curl -s -X POST \"$CONVEX_ENDPOINT\" \\
        -H \"Authorization: Bearer $CONVEX_API_KEY\" \\
        -H \"Content-Type: application/json\" \\
        -d '$JSON'"

    log "Rollback complete."
    exit 0
}

# ------------------------------
# Main execution flow
# ------------------------------

if [[ "$ROLLBACK" -eq 1 ]]; then
    rollback
fi

log "=== Starting Mark II ship process ==="

validate_git
run_smoke
sign_and_notarize

# Deploy artifacts
run "cp -R \"$APP_BUNDLE\" \"$APP_INSTALL_DIR/\""
deploy_f5_tts
sync_pwa
reload_launch_agents

record_ship
notify_imessage

log "=== Ship process completed successfully ==="
