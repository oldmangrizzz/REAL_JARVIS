#!/bin/bash
# Test harness for mesh-display-agent URL allowlist (H10)
# Validates that file:// and javascript: URIs are rejected

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

python3 << 'PYTEST'
#!/usr/bin/env python3
"""Test harness for mesh-display-agent URL allowlist."""

import sys
import os

# Mock the server components (we only want to test _is_url_allowed)
# Import the module's functions by exec'ing it
with open('./mesh-display-agent.py', 'r') as f:
    code = f.read()
    # Extract just the _is_url_allowed function and its dependencies
    exec(code.split('class Handler')[0])

# Test cases
test_cases = [
    # (url, should_allow, description)
    ("https://grizzlymedicine.icu/dash", True, "HTTPS on allowed domain"),
    ("https://sub.grizzlymedicine.icu/dash", True, "HTTPS on allowed subdomain"),
    ("http://localhost/local", True, "HTTP on localhost allowed"),
    ("http://127.0.0.1/local", True, "HTTP on 127.0.0.1 allowed"),
    ("file:///etc/passwd", False, "file:// scheme rejected"),
    ("javascript:alert('xss')", False, "javascript: scheme rejected"),
    ("data:text/html,<script>alert('xss')</script>", False, "data: scheme rejected"),
    ("about:blank", True, "about: scheme allowed"),
    ("https://evil.com/", False, "External domain rejected"),
    ("http://grizzlymedicine.icu/", False, "HTTP remote rejected (not localhost)"),
]

print("Testing mesh-display-agent URL allowlist (H10):")
passed = 0
failed = 0

for url, should_allow, desc in test_cases:
    result = _is_url_allowed(url)
    status = "✓" if result == should_allow else "✗"
    if result == should_allow:
        passed += 1
    else:
        failed += 1
    print(f"{status} {desc}")
    if result != should_allow:
        print(f"  URL: {url}")
        print(f"  Expected: {should_allow}, Got: {result}")

print(f"\nResult: {passed}/{len(test_cases)} tests passed")
sys.exit(0 if failed == 0 else 1)
PYTEST
