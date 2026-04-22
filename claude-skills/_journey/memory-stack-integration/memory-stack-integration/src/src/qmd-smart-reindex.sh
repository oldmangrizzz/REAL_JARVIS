#!/bin/bash
# QMD Smart Reindex
# Only reindexes collections if content has changed (based on file checksums)
#
# Usage: ./qmd-smart-reindex.sh [collection_name]
# If no collection specified, checks all configured collections

set -e

WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
STATE_FILE="$WORKSPACE_DIR/.qmd-index-state.json"
COLLECTIONS_FILE="$WORKSPACE_DIR/qmd.config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    log_info "Initializing QMD index state file"
    echo '{}' > "$STATE_FILE"
fi

# Get current checksums for a collection
get_collection_checksum() {
    local collection_path="$1"
    local mask="$2"
    
    if [ -d "$collection_path" ]; then
        find "$collection_path" -type f -name "*.md" -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1
    else
        echo "missing"
    fi
}

# Check if reindex is needed
needs_reindex() {
    local collection_name="$1"
    local current_checksum="$2"
    local stored_checksum
    
    stored_checksum=$(jq -r ".collections[\"$collection_name\"] // \"none\"" "$STATE_FILE" 2>/dev/null)
    
    if [ "$stored_checksum" = "none" ] || [ "$stored_checksum" != "$current_checksum" ]; then
        return 0  # Needs reindex
    else
        return 1  # No reindex needed
    fi
}

# Update state file with new checksum
update_state() {
    local collection_name="$1"
    local checksum="$2"
    
    local temp_file=$(mktemp)
    jq ".collections[\"$collection_name\"] = \"$checksum\"" "$STATE_FILE" > "$temp_file" && mv "$temp_file" "$STATE_FILE"
}

# Main logic
log_info "QMD Smart Reindex starting..."

# If specific collection requested
if [ -n "$1" ]; then
    COLLECTIONS_TO_CHECK="$1"
else
    # Get all collections from config
    if [ -f "$COLLECTIONS_FILE" ]; then
        COLLECTIONS_TO_CHECK=$(jq -r '.collections[].name' "$COLLECTIONS_FILE" 2>/dev/null)
    else
        log_warn "No qmd.config.json found, reindexing default collections"
        COLLECTIONS_TO_CHECK="memory skills docs workspace"
    fi
fi

REINDEXED=0
SKIPPED=0

for collection in $COLLECTIONS_TO_CHECK; do
    # Get collection path from config or use default
    if [ -f "$COLLECTIONS_FILE" ]; then
        collection_path=$(jq -r ".collections[] | select(.name==\"$collection\") | .path" "$COLLECTIONS_FILE" 2>/dev/null)
        collection_mask=$(jq -r ".collections[] | select(.name==\"$collection\") | .mask" "$COLLECTIONS_FILE" 2>/dev/null)
    fi
    
    # Default paths if not in config
    case "$collection" in
        memory) collection_path="${collection_path:-$WORKSPACE_DIR/memory}" ;;
        skills) collection_path="${collection_path:-$WORKSPACE_DIR/skills}" ;;
        docs) collection_path="${collection_path:-$WORKSPACE_DIR/docs}" ;;
        workspace) collection_path="${collection_path:-$WORKSPACE_DIR}" ;;
        *) collection_path="${collection_path:-$WORKSPACE_DIR/$collection}" ;;
    esac
    
    collection_mask="${collection_mask:-**/*.md}"
    
    if [ ! -d "$collection_path" ]; then
        log_warn "Collection '$collection' path not found: $collection_path (skipping)"
        continue
    fi
    
    log_info "Checking collection: $collection"
    current_checksum=$(get_collection_checksum "$collection_path" "$collection_mask")
    
    if needs_reindex "$collection" "$current_checksum"; then
        log_info "Changes detected in '$collection', reindexing..."
        npx qmd update --collection "$collection" 2>/dev/null || npx qmd update 2>/dev/null
        update_state "$collection" "$current_checksum"
        REINDEXED=$((REINDEXED + 1))
    else
        log_info "No changes in '$collection', skipping"
        SKIPPED=$((SKIPPED + 1))
    fi
done

log_info "Smart reindex complete: $REINDEXED reindexed, $SKIPPED skipped"
