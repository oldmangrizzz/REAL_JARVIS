#!/bin/bash
# Auto-Promote Memory
# Promotes high-confidence items to MEMORY.md from:
# 1. .learnings/LEARNINGS.md (Recurrence-Count >= 3)
# 2. Wiki syntheses with PROMOTE markers
# 3. memory/pending-promotion.md (manual candidates)
#
# Usage: ./auto-promote-memory.sh

set -e

WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
MEMORY_DIR="$WORKSPACE_DIR/memory"
LEARNINGS_DIR="$WORKSPACE_DIR/.learnings"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
LEARNINGS_FILE="$LEARNINGS_DIR/LEARNINGS.md"
PENDING_FILE="$MEMORY_DIR/pending-promotion.md"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Ensure directories exist
mkdir -p "$MEMORY_DIR" "$LEARNINGS_DIR"

# Create MEMORY.md if it doesn't exist
if [ ! -f "$MEMORY_FILE" ]; then
    log_info "Creating MEMORY.md"
    cat > "$MEMORY_FILE" << 'EOF'
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

EOF
fi

log_info "Starting memory promotion pass..."

PROMOTED=0

# 1. Promote from .learnings/LEARNINGS.md (Recurrence-Count >= 3)
if [ -f "$LEARNINGS_FILE" ]; then
    log_info "Checking .learnings/LEARNINGS.md for promotable items..."
    
    # Extract items with Recurrence-Count >= 3 and Status: pending
    # This is a simplified extraction - adjust based on your actual format
    while IFS= read -r line; do
        if [[ "$line" =~ ^-.*\[.*\].*Recurrence-Count:[[:space:]]*([0-9]+) ]]; then
            count="${BASH_REMATCH[1]}"
            if [ "$count" -ge 3 ]; then
                # Check if already in MEMORY.md (simple dedupe)
                if ! grep -qF "$line" "$MEMORY_FILE"; then
                    log_info "Promoting learning (recurrence=$count): ${line:0:60}..."
                    echo "" >> "$MEMORY_FILE"
                    echo "## Promoted $(date +%Y-%m-%d)" >> "$MEMORY_FILE"
                    echo "- $line" >> "$MEMORY_FILE"
                    PROMOTED=$((PROMOTED + 1))
                fi
            fi
        fi
    done < "$LEARNINGS_FILE"
fi

# 2. Promote from pending-promotion.md
if [ -f "$PENDING_FILE" ]; then
    log_info "Checking pending-promotion.md..."
    
    while IFS= read -r line; do
        # Skip empty lines and headers
        if [[ -z "$line" ]] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # Check if already in MEMORY.md
        if ! grep -qF "$line" "$MEMORY_FILE"; then
            log_info "Promoting pending item: ${line:0:60}..."
            echo "" >> "$MEMORY_FILE"
            echo "## Promoted $(date +%Y-%m-%d)" >> "$MEMORY_FILE"
            echo "$line" >> "$MEMORY_FILE"
            PROMOTED=$((PROMOTED + 1))
        fi
    done < "$PENDING_FILE"
    
    # Clear pending file after promotion
    > "$PENDING_FILE"
    log_info "Cleared pending-promotion.md"
fi

# 3. Check wiki syntheses for PROMOTE markers (if wiki exists)
WIKI_DIR="$WORKSPACE_DIR/../wiki"
if [ -d "$WIKI_DIR" ]; then
    log_info "Checking wiki syntheses for PROMOTE markers..."
    
    while IFS= read -r -d '' file; do
        if grep -q "PROMOTE" "$file"; then
            log_info "Found PROMOTE marker in: $file"
            # Extract content between PROMOTE marker and next heading
            # This is simplified - adjust based on your wiki format
            while IFS= read -r line; do
                if [[ "$line" =~ ^PROMOTE: ]]; then
                    content="${line#PROMOTE: }"
                    if ! grep -qF "$content" "$MEMORY_FILE"; then
                        log_info "Promoting from wiki: ${content:0:60}..."
                        echo "" >> "$MEMORY_FILE"
                        echo "## Promoted from Wiki $(date +%Y-%m-%d)" >> "$MEMORY_FILE"
                        echo "- $content" >> "$MEMORY_FILE"
                        PROMOTED=$((PROMOTED + 1))
                    fi
                fi
            done < "$file"
        fi
    done < <(find "$WIKI_DIR/syntheses" -name "*.md" -print0 2>/dev/null)
fi

log_info "Promotion pass complete: $PROMOTED items promoted"

# Optional: Run QMD reindex if content changed
if [ $PROMOTED -gt 0 ]; then
    log_info "MEMORY.md updated. Consider running: npx qmd update --collection memory"
fi
