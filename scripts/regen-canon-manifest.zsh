#!/usr/bin/env zsh
# scripts/regen-canon-manifest.zsh
#
# Regenerate CANON/corpus/MANIFEST.sha256 from the current contents of the
# corpus directory. This file is the on-disk manifest consumed by
# jarvis-lockdown.zsh. It is ALSO mirrored by the Swift CanonRegistry; the
# two must agree. Regenerating the manifest is a deliberate act — after
# adding or revising canon, run:
#
#   scripts/regen-canon-manifest.zsh
#   (then update expected hashes in Jarvis/Sources/JarvisCore/Canon/CanonRegistry.swift
#    and re-run the Swift test suite)

SCRIPT_DIR=$(cd $(dirname "$0") && pwd)
CORPUS_DIR=$(cd "$SCRIPT_DIR/../CANON/corpus" && pwd)

if [[ ! -d "$CORPUS_DIR" ]]; then
    echo "Canon corpus directory missing: $CORPUS_DIR" >&2
    exit 1
fi

pushd "$CORPUS_DIR" > /dev/null
tmp=$(mktemp)
shasum -a 256 *.md *.pdf | LC_ALL=C sort -k 2 > "$tmp"
mv "$tmp" MANIFEST.sha256
popd > /dev/null

echo "✓ Regenerated $CORPUS_DIR/MANIFEST.sha256"
wc -l "$CORPUS_DIR/MANIFEST.sha256"
