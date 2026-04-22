#!/bin/bash
# Context Guard — Pre-commit safety hook
# Reminds Claude to update safeguard files before every git commit
# Runs as a PreToolUse hook on Bash commands

# 1. SECTION: Input parsing
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# end of 1

# 2. SECTION: Commit detection and checklist
# Only trigger on git commit commands
if [[ "$COMMAND" == *"git commit"* ]]; then
  echo "PRE-COMMIT CHECK: Before committing, ensure you have:" >&2
  echo "  1. Logged any new user comments to COMMENTS.md" >&2
  echo "  2. Updated TASK_REGISTRY.md with any new/completed tasks" >&2
  echo "  3. Updated SESSION_LOG.md if this is a significant milestone" >&2
  echo "  4. Updated FEATURE_LIST.json if any feature status changed" >&2
  echo "  5. Archived any approved plans to plans/ directory" >&2
  echo "  (This is a reminder — the commit will proceed either way.)" >&2
fi
# end of 2

# Always allow — this is a reminder, not a blocker
exit 0
