#!/bin/bash
# Context Guard — Pre-Compaction Backup Hook
# Fires before context compaction. Backs up safeguard files so nothing is lost.

BACKUP_DIR="$CLAUDE_PROJECT_DIR/compaction-backups/$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

FILES=(SESSION_LOG.md TASK_REGISTRY.md COMMENTS.md DECISIONS.md FEATURE_LIST.json)
COPIED=0

for f in "${FILES[@]}"; do
  if [ -f "$CLAUDE_PROJECT_DIR/$f" ]; then
    cp "$CLAUDE_PROJECT_DIR/$f" "$BACKUP_DIR/"
    COPIED=$((COPIED + 1))
  fi
done

echo "Context Guard: backed up $COPIED safeguard files to compaction-backups/" >&2
exit 0
