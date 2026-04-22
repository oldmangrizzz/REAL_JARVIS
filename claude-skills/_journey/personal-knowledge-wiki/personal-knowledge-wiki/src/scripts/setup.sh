#!/bin/bash
# Setup script for Personal Knowledge Wiki
# Usage: bash scripts/setup.sh /path/to/your/vault

VAULT_DIR="${1:-.}"

echo "Setting up wiki structure in: $VAULT_DIR"

# Create wiki directories
mkdir -p "$VAULT_DIR/wiki/entities"
mkdir -p "$VAULT_DIR/wiki/concepts"
mkdir -p "$VAULT_DIR/wiki/sources"
mkdir -p "$VAULT_DIR/wiki/comparisons"
mkdir -p "$VAULT_DIR/wiki/syntheses"

# Create raw source directories
mkdir -p "$VAULT_DIR/raw/articles"
mkdir -p "$VAULT_DIR/raw/transcripts"
mkdir -p "$VAULT_DIR/raw/books"
mkdir -p "$VAULT_DIR/raw/threads"
mkdir -p "$VAULT_DIR/raw/assets"

# Create index if it doesn't exist
if [ ! -f "$VAULT_DIR/wiki/index.md" ]; then
  cat > "$VAULT_DIR/wiki/index.md" << 'EOF'
# Wiki Index

Master catalog of all wiki pages. Updated by the Librarian on every ingest.

## Entities

## Concepts

## Sources

## Comparisons

## Syntheses
EOF
  echo "Created wiki/index.md"
fi

# Create log if it doesn't exist
if [ ! -f "$VAULT_DIR/wiki/log.md" ]; then
  cat > "$VAULT_DIR/wiki/log.md" << 'EOF'
# Wiki Activity Log

Chronological record of all Librarian actions.

---
EOF
  echo "Created wiki/log.md"
fi

echo "Wiki structure ready!"
echo ""
echo "Next steps:"
echo "1. Copy WIKI.md to $VAULT_DIR/WIKI.md"
echo "2. Drop source documents into raw/ subdirectories"
echo "3. Ask your AI agent to read WIKI.md and start ingesting"
