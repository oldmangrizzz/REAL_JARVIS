#!/bin/bash
# Sync to NotebookLM
# Syncs canonical workspace files to NotebookLM second brain
#
# Usage: ./sync-to-notebooklm.sh
#
# Setup:
# 1. Create notebook at https://notebooklm.google.com
# 2. Copy notebook ID from URL
# 3. Replace {NOTEBOOK_ID} below with your actual ID
# 4. Authenticate: ~/.local/bin/notebooklm login
# 5. Run this script

set -e

# CONFIGURATION - Replace with your values
NOTEBOOK_ID="{NOTEBOOK_ID}"  # Your NotebookLM notebook ID
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"

# Files to sync (canonical sources of truth)
SYNC_FILES=(
    "$WORKSPACE_DIR/SOUL.md"
    "$WORKSPACE_DIR/USER.md"
    "$WORKSPACE_DIR/MEMORY.md"
    "$WORKSPACE_DIR/MEMORY_FRAMEWORK.md"
    "$WORKSPACE_DIR/memory/$(date +%Y-%m-%d).md"  # Today's daily log only
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if notebook ID is configured
if [ "$NOTEBOOK_ID" = "{NOTEBOOK_ID}" ]; then
    log_error "NOTEBOOK_ID not configured. Edit this script and replace {NOTEBOOK_ID} with your actual notebook ID."
    exit 1
fi

# Check if notebooklm CLI is available
if ! command -v notebooklm &> /dev/null; then
    log_error "notebooklm CLI not found. Install with: npm install -g @openclaw/notebooklm"
    exit 1
fi

# Check if authenticated
if [ ! -f ~/.notebooklm/storage_state.json ]; then
    log_warn "Not authenticated. Running: notebooklm login"
    ~/.local/bin/notebooklm login
fi

log_info "Syncing to NotebookLM notebook: $NOTEBOOK_ID"

SYNCED=0
SKIPPED=0
ERRORS=0

for file in "${SYNC_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_warn "File not found (skipping): $file"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    filename=$(basename "$file")
    log_info "Syncing: $filename"
    
    # Use notebooklm_add_text (NOT notebooklm_add_source_text)
    if notebooklm_add_text --notebook "$NOTEBOOK_ID" --name "$filename" --file "$file" 2>/dev/null; then
        SYNCED=$((SYNCED + 1))
    else
        log_error "Failed to sync: $file"
        ERRORS=$((ERRORS + 1))
    fi
done

log_info "Sync complete: $SYNCED synced, $SKIPPED skipped, $ERRORS errors"

if [ $ERRORS -gt 0 ]; then
    log_warn "Some files failed to sync. Check authentication and notebook ID."
    exit 1
fi
