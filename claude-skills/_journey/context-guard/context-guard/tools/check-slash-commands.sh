#!/bin/bash
# Context Guard — Slash command enforcement hook
# Detects when the user types a /command matching an installed skill
# and reminds Claude to invoke it via the Skill tool.
# Runs as a UserPromptSubmit hook.

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.user_message // empty')

if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Find the project directory (where .claude/skills/ lives)
SKILLS_DIR="$CLAUDE_PROJECT_DIR/.claude/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  exit 0
fi

# Extract /word patterns from the message
COMMANDS=$(echo "$MESSAGE" | grep -oE '(^|[ \t])/([a-zA-Z]+)' | sed 's/^[ \t]*//' | sed 's/^\///')

if [ -z "$COMMANDS" ]; then
  exit 0
fi

# Check each command against installed skills
for CMD in $COMMANDS; do
  if [ -d "$SKILLS_DIR/$CMD" ] && [ -f "$SKILLS_DIR/$CMD/SKILL.md" ]; then
    echo "SLASH COMMAND DETECTED: /$CMD — You MUST invoke this via the Skill tool: Skill(skill=\"$CMD\"). Do NOT manually replicate the skill's steps." >&2
  fi
done

exit 0
