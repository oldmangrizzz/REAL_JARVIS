#!/bin/bash
# Memory Stack Integration - Setup Script
# Run this after installing the kit to configure your environment
#
# Usage: ./scripts/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo ""
echo "========================================"
echo "  Memory Stack Integration - Setup"
echo "========================================"
echo ""

# Step 1: Create directory structure
log_step "Creating directory structure..."

mkdir -p "$WORKSPACE_DIR/memory/system-sync"
mkdir -p "$WORKSPACE_DIR/memory/trend-alerts"
mkdir -p "$WORKSPACE_DIR/memory/pending-promotion"
mkdir -p "$WORKSPACE_DIR/.learnings"

log_info "Created memory directories"

# Step 2: Create MEMORY.md if it doesn't exist
if [ ! -f "$WORKSPACE_DIR/memory/MEMORY.md" ]; then
    log_step "Creating MEMORY.md template..."
    cat > "$WORKSPACE_DIR/memory/MEMORY.md" << 'EOF'
# MEMORY.md — Long-Term Memory

## Current Focus
[Your active priorities]

## Standing Rules
[Your operational rules]

## Recurring Tasks
| Task | Schedule |
|------|----------|

## Known Issues
| # | Priority | Issue | Status | Workaround |
|---|----------|-------|--------|------------|

## Active Integrations
[Your active integrations]

EOF
    log_info "Created MEMORY.md"
else
    log_info "MEMORY.md already exists"
fi

# Step 3: Create today's daily log if it doesn't exist
TODAY=$(date +%Y-%m-%d)
if [ ! -f "$WORKSPACE_DIR/memory/$TODAY.md" ]; then
    log_step "Creating today's daily log..."
    cat > "$WORKSPACE_DIR/memory/$TODAY.md" << EOF
# $TODAY

## Sessions
[Log what happened today]

## Decisions
[Key decisions made]

## Follow-ups
[Things to remember for tomorrow]

EOF
    log_info "Created $TODAY.md"
else
    log_info "Today's log already exists"
fi

# Step 4: Create .learnings/LEARNINGS.md if it doesn't exist
if [ ! -f "$WORKSPACE_DIR/.learnings/LEARNINGS.md" ]; then
    log_step "Creating LEARNINGS.md template..."
    cat > "$WORKSPACE_DIR/.learnings/LEARNINGS.md" << 'EOF'
# LEARNINGS.md — Pattern Detection & Behavioral Corrections

## Active Corrections
[Items with Recurrence-Count >= 3 get promoted to MEMORY.md]

EOF
    log_info "Created LEARNINGS.md"
else
    log_info "LEARNINGS.md already exists"
fi

# Step 5: Configure NotebookLM (optional)
echo ""
log_step "NotebookLM Second Brain Setup (optional)"
echo ""
echo "NotebookLM provides long-term synthesis and cross-document insights."
echo ""
read -p "Do you want to configure NotebookLM sync? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "To get your Notebook ID:"
    echo "1. Go to https://notebooklm.google.com"
    echo "2. Create a new notebook (or use existing)"
    echo "3. Copy the ID from the URL (looks like: b2625942-7590-4246-a12d-0184566a79f2)"
    echo ""
    read -p "Enter your Notebook ID: " NOTEBOOK_ID
    
    if [ -n "$NOTEBOOK_ID" ]; then
        # Update sync script with the ID
        sed -i "s/{NOTEBOOK_ID}/$NOTEBOOK_ID/g" "$SCRIPT_DIR/sync-to-notebooklm.sh"
        log_info "NotebookLM configured with ID: $NOTEBOOK_ID"
        
        # Test authentication
        echo ""
        log_step "Testing NotebookLM authentication..."
        if command -v notebooklm &> /dev/null; then
            if [ ! -f ~/.notebooklm/storage_state.json ]; then
                log_warn "Not authenticated. Running: notebooklm login"
                ~/.local/bin/notebooklm login
            else
                log_info "Already authenticated"
            fi
        else
            log_warn "notebooklm CLI not found. Install with: npm install -g @openclaw/notebooklm"
        fi
    else
        log_warn "Notebook ID not provided. Skipping NotebookLM setup."
    fi
else
    log_info "Skipping NotebookLM setup (can configure later by editing sync-to-notebooklm.sh)"
fi

# Step 6: Install QMD (if not present)
echo ""
log_step "Checking QMD installation..."
if command -v qmd &> /dev/null; then
    QMD_VERSION=$(qmd --version 2>/dev/null || echo "unknown")
    log_info "QMD installed: $QMD_VERSION"
else
    log_warn "QMD not found. Installing..."
    if command -v npm &> /dev/null; then
        npm install -g qmd
        log_info "QMD installed"
    else
        log_error "npm not found. Please install Node.js/npm first, then run: npm install -g qmd"
    fi
fi

# Step 7: Initialize QMD collections
echo ""
log_step "Initializing QMD collections..."

# Create qmd.json if it doesn't exist
if [ ! -f "$WORKSPACE_DIR/qmd.json" ]; then
    cat > "$WORKSPACE_DIR/qmd.json" << 'EOF'
{
  "collections": {
    "memory": {
      "paths": ["memory/**/*.md"],
      "description": "Daily logs and long-term memory"
    },
    "skills": {
      "paths": ["skills/**/*.md"],
      "description": "Skill documentation"
    },
    "docs": {
      "paths": ["docs/**/*.md"],
      "description": "Workspace documentation"
    }
  }
}
EOF
    log_info "Created qmd.json"
fi

# Initial index
log_step "Building initial QMD index..."
npx qmd update --collection memory 2>/dev/null || log_warn "QMD index build skipped (run manually with: npx qmd update --collection memory)"

# Step 8: Make scripts executable
log_step "Setting script permissions..."
chmod +x "$SCRIPT_DIR"/*.sh
chmod +x "$SCRIPT_DIR"/*.py
log_info "Scripts are now executable"

# Step 9: Create cron job examples
echo ""
log_step "Creating cron job examples..."

# Detect system timezone; fall back to a placeholder the user must fill in
LOCAL_TZ=$(timedatectl show -p Timezone --value 2>/dev/null \
  || cat /etc/timezone 2>/dev/null \
  || defaults read NSGlobalDomain AppleLocale 2>/dev/null \
  || echo "YOUR_TIMEZONE")
log_info "Detected timezone: $LOCAL_TZ"

CRON_EXAMPLES="$KIT_DIR/cron-examples.md"
cat > "$CRON_EXAMPLES" << EOF
# Cron Job Examples for Memory Stack
# Timezone detected at setup time: $LOCAL_TZ
# Replace "$LOCAL_TZ" below if your cron runner uses a different timezone.

## Daily Memory Log Reminder (10 PM)
\`\`\`json
{
  "name": "daily-memory-log",
  "schedule": {"kind": "cron", "expr": "0 22 * * *", "tz": "$LOCAL_TZ"},
  "payload": {"kind": "scheduled automation run", "message": "Create today's memory log if missing. Check memory/$(date +%Y-%m-%d).md"}
}
\`\`\`

## QMD Reindex (Daily 3 AM)
\`\`\`json
{
  "name": "qmd-daily-reindex",
  "schedule": {"kind": "cron", "expr": "0 3 * * *", "tz": "$LOCAL_TZ"},
  "payload": {"kind": "scheduled automation run", "message": "Run: npx qmd update --collection memory"}
}
\`\`\`

## Backlinks Index (Daily 3:15 AM)
\`\`\`json
{
  "name": "backlinks-daily-build",
  "schedule": {"kind": "cron", "expr": "15 3 * * *", "tz": "$LOCAL_TZ"},
  "payload": {"kind": "scheduled automation run", "message": "Run: python3 scripts/backlinks.py build"}
}
\`\`\`

## Auto-Promote Memory (Daily 4 AM)
\`\`\`json
{
  "name": "auto-promote-memory",
  "schedule": {"kind": "cron", "expr": "0 4 * * *", "tz": "$LOCAL_TZ"},
  "payload": {"kind": "scheduled automation run", "message": "Run: scripts/auto-promote-memory.sh"}
}
\`\`\`

## NotebookLM Sync (Daily 3:30 AM)
\`\`\`json
{
  "name": "notebooklm-sync",
  "schedule": {"kind": "cron", "expr": "30 3 * * *", "tz": "$LOCAL_TZ"},
  "payload": {"kind": "scheduled automation run", "message": "Run: scripts/sync-to-notebooklm.sh"}
}
\`\`\`

EOF

log_info "Created cron-examples.md"

# Done
echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
log_info "Next steps:"
echo "  1. Review MEMORY.md and customize for your needs"
echo "  2. Run 'npx qmd update --collection memory' to build full index"
echo "  3. Set up cron jobs from cron-examples.md (optional)"
echo "  4. Start using memory tools in your sessions!"
echo ""
echo "Usage:"
echo "  - Semantic search: memory_search query=\"your query\""
echo "  - Backlinks: python3 scripts/backlinks.py build"
echo "  - Query backlinks: python3 scripts/backlinks.py query \"Cora\""
echo "  - Patterns: python3 scripts/backlinks.py patterns"
echo ""
