#!/usr/bin/env python3
"""
Backlinks Indexer
Discovers wikilinks [[like this]] and named entities across memory files.
Detects cross-file thematic patterns.

Usage:
    python3 backlinks.py build          # Build/update index
    python3 backlinks.py query "Cora"   # Find mentions of a topic
    python3 backlinks.py patterns       # Show cross-file patterns
    python3 backlinks.py who "Dr. X"    # Find specific person/entity mentions
"""

import os
import re
import json
import sys
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# Configuration
WORKSPACE_DIR = os.environ.get('WORKSPACE_DIR', str(Path.home() / 'workspace'))
MEMORY_DIR = os.path.join(WORKSPACE_DIR, 'memory')
BACKLINKS_INDEX = os.path.join(MEMORY_DIR, '_backlinks.json')

# Patterns
WIKILINK_PATTERN = re.compile(r'\[\[([^\]]+)\]\]')
HEADING_PATTERN = re.compile(r'^#{2,}\s+(.+)$', re.MULTILINE)
COMMON_SKIP = {
    'overview', 'introduction', 'summary', 'notes', 'references', 'see also',
    'related', 'todos', 'todo', 'tasks', 'agenda', 'minutes', 'action items',
    'follow-up', 'follow ups', 'followups', 'decisions', 'decided', 'context',
    'background', 'goal', 'goals', 'when to use', 'setup', 'usage', 'examples'
}

def log_info(msg):
    print(f"[INFO] {msg}")

def log_warn(msg):
    print(f"[WARN] {msg}")

def log_error(msg):
    print(f"[ERROR] {msg}")

def extract_wikilinks(content):
    """Extract all [[wikilinks]] from content."""
    return WIKILINK_PATTERN.findall(content)

def extract_headings(content):
    """Extract level-2+ headings, filtering generic ones."""
    headings = HEADING_PATTERN.findall(content)
    return [h.strip() for h in headings if h.strip().lower() not in COMMON_SKIP]

def scan_file(filepath):
    """Scan a single markdown file for wikilinks and headings."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        wikilinks = extract_wikilinks(content)
        headings = extract_headings(content)
        
        # Count occurrences
        link_counts = defaultdict(int)
        for link in wikilinks:
            link_counts[link] += 1
        
        return {
            'wikilinks': dict(link_counts),
            'headings': list(set(headings)),
            'all_entities': list(set(wikilinks + headings))
        }
    except Exception as e:
        log_warn(f"Error reading {filepath}: {e}")
        return None

def build_index():
    """Build the backlinks index across all memory files."""
    log_info(f"Scanning memory directory: {MEMORY_DIR}")
    
    if not os.path.exists(MEMORY_DIR):
        log_error(f"Memory directory not found: {MEMORY_DIR}")
        sys.exit(1)
    
    index = {
        'built_at': datetime.now().isoformat(),
        'files': {},
        'backlinks': defaultdict(list),  # topic -> [files that mention it]
        'entities': defaultdict(list),   # entity -> [files]
        'patterns': []                   # entities appearing in 2+ files
    }
    
    # Scan all .md files
    md_files = list(Path(MEMORY_DIR).glob('**/*.md'))
    log_info(f"Found {len(md_files)} markdown files")
    
    for filepath in md_files:
        # Skip index file itself
        if filepath.name == '_backlinks.json':
            continue
        
        rel_path = str(filepath.relative_to(MEMORY_DIR))
        result = scan_file(str(filepath))
        
        if result:
            index['files'][rel_path] = result
            
            # Build backlinks map
            for entity in result['all_entities']:
                index['backlinks'][entity].append(rel_path)
    
    # Find patterns (entities in 2+ files)
    for entity, files in index['backlinks'].items():
        if len(files) >= 2:
            index['patterns'].append({
                'entity': entity,
                'file_count': len(files),
                'files': files
            })
    
    # Sort patterns by frequency
    index['patterns'].sort(key=lambda x: x['file_count'], reverse=True)
    
    # Convert defaultdicts to regular dicts for JSON serialization
    index['backlinks'] = dict(index['backlinks'])
    index['entities'] = dict(index['entities'])
    
    # Write index
    with open(BACKLINKS_INDEX, 'w', encoding='utf-8') as f:
        json.dump(index, f, indent=2)
    
    log_info(f"Index built: {BACKLINKS_INDEX}")
    log_info(f"Total files scanned: {len(index['files'])}")
    log_info(f"Unique entities: {len(index['backlinks'])}")
    log_info(f"Cross-file patterns: {len(index['patterns'])}")
    
    return index

def query_index(search_term):
    """Find all files mentioning a search term."""
    if not os.path.exists(BACKLINKS_INDEX):
        log_error("Index not found. Run 'build' first.")
        sys.exit(1)
    
    with open(BACKLINKS_INDEX, 'r') as f:
        index = json.load(f)
    
    # Case-insensitive search
    search_lower = search_term.lower()
    matches = []
    
    for entity, files in index['backlinks'].items():
        if search_lower in entity.lower():
            matches.append({
                'entity': entity,
                'files': files,
                'count': len(files)
            })
    
    if not matches:
        print(f"No matches found for '{search_term}'")
        return
    
    # Sort by frequency
    matches.sort(key=lambda x: x['count'], reverse=True)
    
    print(f"\nFound {len(matches)} matches for '{search_term}':\n")
    for match in matches[:20]:  # Limit to top 20
        print(f"  [[{match['entity']}]] - mentioned in {match['count']} file(s)")
        for f in match['files'][:5]:  # Show up to 5 files
            print(f"    - {f}")
        if len(match['files']) > 5:
            print(f"    ... and {len(match['files']) - 5} more")
        print()

def show_patterns():
    """Display cross-file entity patterns."""
    if not os.path.exists(BACKLINKS_INDEX):
        log_error("Index not found. Run 'build' first.")
        sys.exit(1)
    
    with open(BACKLINKS_INDEX, 'r') as f:
        index = json.load(f)
    
    patterns = index.get('patterns', [])
    
    if not patterns:
        print("No cross-file patterns found.")
        return
    
    print(f"\nCross-file entity patterns ({len(patterns)} entities in 2+ files):\n")
    print(f"{'Entity':<40} {'Files':>6}")
    print("-" * 50)
    
    for pattern in patterns[:50]:  # Top 50
        entity = pattern['entity'][:38] + '..' if len(pattern['entity']) > 40 else pattern['entity']
        print(f"{entity:<40} {pattern['file_count']:>6}")

def who_search(name):
    """Find all mentions of a specific person/entity."""
    query_index(name)

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == 'build':
        build_index()
    elif command == 'query':
        if len(sys.argv) < 3:
            log_error("Usage: python3 backlinks.py query <search_term>")
            sys.exit(1)
        query_index(sys.argv[2])
    elif command == 'patterns':
        show_patterns()
    elif command == 'who':
        if len(sys.argv) < 3:
            log_error("Usage: python3 backlinks.py who <name>")
            sys.exit(1)
        who_search(sys.argv[2])
    else:
        log_error(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)

if __name__ == '__main__':
    main()
