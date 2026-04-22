#!/usr/bin/env python3
"""Real proposer for the Self-Improve Harness.

Uses the Anthropic SDK to generate genuine improvement proposals.
Framework-agnostic: works from Claude Code, Claude Code, Hermes, cron, or any agent.

Contract:
- Reads current file content from stdin
- Receives TARGET_PATH, TARGET_TYPE, TARGET_CATEGORY, TARGET_NAME in env
- Writes full replacement file content to stdout
- Exits 0 on success, non-zero on hard failure
- Empty stdout = no improvement warranted

Requirements:
- ANTHROPIC_API_KEY environment variable (or ~/.anthropic/api_key file)
- anthropic Python package

Configuration (env vars, all optional):
- PROPOSER_MODEL: model to use (default: claude-sonnet-4-20250514)
- PROPOSER_MAX_TOKENS: max response tokens (default: 8192)
- PROPOSER_TEMPERATURE: sampling temperature (default: 0.3)

Version: 2
Changes: Added retry logic, content size guards, file-type-specific prompts, version constant
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path


__version__ = "2.0.0"


def get_api_key() -> str | None:
    """Resolve API key from env or fallback file."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key
    keyfile = Path.home() / ".anthropic" / "api_key"
    if keyfile.exists():
        return keyfile.read_text().strip()
    return None


def build_system_prompt(target_type: str, target_category: str, target_path: str) -> str:
    """Build type-specific system prompt with enhanced guidance."""
    base_prompt = f"""You are a file improvement agent in a self-improvement harness.
Your job: review one tracked file and return an improved version.

Target type: {target_type}
Target category: {target_category}
Target path: {target_path}

Rules — follow these exactly:
1. Return ONLY the full replacement file content. No markdown fences, no commentary, no explanation.
2. Preserve all factual content, data, and semantics unless clearly wrong.
3. Improve: clarity, structure, consistency, completeness, safety, and correctness.
4. For skills/prompts: sharpen trigger conditions, fix ambiguities, add missing edge cases.
5. For docs: fix formatting, remove stale info, improve readability.
6. For configs: fix unsafe defaults, add missing fields, improve comments.
7. For code: fix bugs, improve error handling, simplify where possible.
8. Do NOT add secrets, fabricated data, or placeholder content.
9. Do NOT add emojis unless they were already present.
10. Do NOT change the file format (md stays md, yaml stays yaml, etc).
11. If the file is already good and no meaningful improvement exists, return EXACTLY the string: NO_CHANGE
12. Keep changes conservative. Small, correct improvements beat ambitious rewrites."""

    # Add file-type-specific guidance
    if target_path.endswith(".py"):
        base_prompt += """

PYTHON-SPECIFIC:
- Preserve all import statements and their order (move stdlib to top, then 3rd-party, then local)
- Do NOT change function signatures, class names, or module-level constants
- Maintain docstring format and style
- Keep function and class hierarchies intact
- Only improve: docstrings, comments, error handling, type hints, and internal logic
- Do NOT remove or rename functions/classes used by external code"""

    elif target_path.endswith((".yaml", ".yml")):
        base_prompt += """

YAML-SPECIFIC:
- Preserve all keys and their nesting structure
- Do NOT add comments to YAML files (comments can break parsers in some contexts)
- Only improve: spacing, indentation consistency, value clarity, and field descriptions
- Maintain all existing fields and their types
- Do NOT remove or rename configuration keys"""

    elif target_path.endswith(".json"):
        base_prompt += """

JSON-SPECIFIC:
- JSON does NOT support comments; do NOT add them
- Preserve all keys, values, and structure exactly as-is
- Only improve: formatting, spacing consistency, and value correctness
- Do NOT add comments or explanatory text
- Maintain strict JSON syntax (no trailing commas, proper escaping)"""

    elif target_path.endswith(".md"):
        base_prompt += """

MARKDOWN-SPECIFIC:
- Preserve heading hierarchy: do NOT skip levels (no # to ### without ##)
- Maintain all links, code blocks, and list structures
- Only improve: wording clarity, formatting consistency, and organization
- Do NOT change heading levels or remove sections
- Keep inline code and code block fences intact"""

    return base_prompt


def build_user_prompt(current: str, target_path: str, target_name: str) -> str:
    return f"""File: {target_path}
Name: {target_name}

Current content:
---
{current}
---

Review this file and return the improved version. If no improvement is warranted, return exactly: NO_CHANGE"""


def call_claude_sdk(system: str, user: str) -> str | None:
    """Try Anthropic SDK with retry logic. Returns None if unavailable, empty string if no change."""
    api_key = get_api_key()
    if not api_key:
        return None
    try:
        import anthropic
    except ImportError:
        return None

    model = os.environ.get("PROPOSER_MODEL", "claude-sonnet-4-20250514")
    max_tokens = int(os.environ.get("PROPOSER_MAX_TOKENS", "8192"))
    temperature = float(os.environ.get("PROPOSER_TEMPERATURE", "0.3"))
    max_retries = 1  # Try once more on failure
    initial_backoff = 2.0  # Start with 2s backoff

    client = anthropic.Anthropic(api_key=api_key)
    
    last_exc = None
    for attempt in range(max_retries + 1):
        try:
            response = client.messages.create(
                model=model,
                max_tokens=max_tokens,
                temperature=temperature,
                system=system,
                messages=[{"role": "user", "content": user}],
            )
            text = response.content[0].text.strip()
            return "" if text == "NO_CHANGE" else text
        except Exception as exc:
            last_exc = exc
            if attempt < max_retries:
                backoff = initial_backoff * (2 ** attempt)
                print(f"[proposer] SDK error on attempt {attempt + 1}, retrying in {backoff:.1f}s: {exc}", file=sys.stderr)
                time.sleep(backoff)
            else:
                print(f"[proposer] SDK error after {max_retries + 1} attempts: {exc}", file=sys.stderr)
    
    return None


def call_claude_cli(system: str, user: str) -> str | None:
    """Try claude CLI (auto-authenticated in Claude Code). Returns None if unavailable."""
    import shutil
    import subprocess

    claude_bin = shutil.which("claude")
    if not claude_bin:
        return None

    prompt = f"{system}\n\n{user}"
    try:
        proc = subprocess.run(
            [claude_bin, "--print", "--model", "sonnet", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if proc.returncode != 0:
            print(f"[proposer] claude CLI exited {proc.returncode}", file=sys.stderr)
            return None
        text = proc.stdout.strip()
        return "" if text == "NO_CHANGE" else text
    except subprocess.TimeoutExpired:
        print("[proposer] claude CLI timed out", file=sys.stderr)
        return None
    except Exception as exc:
        print(f"[proposer] claude CLI error: {exc}", file=sys.stderr)
        return None


def validate_content_size(current: str, proposal: str) -> tuple[bool, str]:
    """Check proposal size relative to original. Returns (valid, message)."""
    if not current.strip():
        return True, "original empty"
    
    current_size = len(current)
    proposal_size = len(proposal)
    
    # More than 3x original size: likely hallucination
    if proposal_size > current_size * 3:
        return False, f"proposal is {proposal_size / current_size:.1f}x original size (hallucination risk)"
    
    # Less than 10% of original: likely truncation
    if proposal_size < current_size * 0.1:
        return False, f"proposal is only {proposal_size / current_size * 100:.0f}% of original size (truncation risk)"
    
    return True, "ok"


def call_claude(system: str, user: str, current: str) -> str:
    """Call Claude via SDK first, then CLI fallback. Returns proposed content or empty string."""
    # Try SDK first (fastest, works in cron/automation)
    result = call_claude_sdk(system, user)
    if result is not None:
        valid, msg = validate_content_size(current, result)
        if not valid:
            print(f"[proposer] content size guard rejected: {msg}", file=sys.stderr)
            return ""
        return result
    
    # Try CLI fallback (works in Claude Code, Claude Code, etc.)
    result = call_claude_cli(system, user)
    if result is not None:
        valid, msg = validate_content_size(current, result)
        if not valid:
            print(f"[proposer] content size guard rejected: {msg}", file=sys.stderr)
            return ""
        return result
    
    print("[proposer] no API key and no claude CLI available", file=sys.stderr)
    return ""


def main() -> int:
    current = sys.stdin.read()
    if not current.strip():
        # Empty file — nothing to improve
        return 0

    target_path = os.environ.get("TARGET_PATH", "")
    target_type = os.environ.get("TARGET_TYPE", "doc")
    target_category = os.environ.get("TARGET_CATEGORY", "")
    target_name = os.environ.get("TARGET_NAME", Path(target_path).name if target_path else "")

    system = build_system_prompt(target_type, target_category, target_path)
    user = build_user_prompt(current, target_path, target_name)
    proposal = call_claude(system, user, current)

    if not proposal.strip():
        return 0

    # Safety: if the proposal is identical to current, skip
    if proposal.strip() == current.strip():
        return 0

    sys.stdout.write(proposal)
    if not proposal.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
