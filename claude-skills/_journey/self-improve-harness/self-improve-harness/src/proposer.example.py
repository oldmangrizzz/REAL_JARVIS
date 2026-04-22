#!/usr/bin/env python3
"""Example proposer adapter for the Self-Improve Harness.

Contract:
- reads the current file content from stdin
- receives TARGET_PATH, TARGET_TYPE, TARGET_CATEGORY, TARGET_NAME in env
- writes the full replacement file content to stdout
- exits 0 on success, non-zero on hard failure

This example is intentionally conservative. By default it returns no proposal.
Replace `call_your_model()` with your own model or agent integration.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def build_prompt(current: str) -> str:
    target_path = os.environ.get("TARGET_PATH", "")
    target_type = os.environ.get("TARGET_TYPE", "")
    target_category = os.environ.get("TARGET_CATEGORY", "")
    target_name = os.environ.get("TARGET_NAME", Path(target_path).name if target_path else "")
    return f"""You are improving one tracked file in a self-improvement loop.

Target path: {target_path}
Target name: {target_name}
Target type: {target_type}
Target category: {target_category}

Rules:
- Return the full replacement file content, not a patch.
- Preserve factual content unless you are clearly improving wording, structure, or safety.
- Do not add secrets or fabricated data.
- If no meaningful improvement is warranted, return an empty string.

Current file:
{current}
"""


def call_your_model(prompt: str, current: str) -> str:
    """Replace this stub with your real provider call.

    Options:
    - OpenAI, Anthropic, Gemini, local model, or another agent wrapper
    - keep the result as full-file replacement text
    - return "" when no change should be made
    """
    _ = prompt
    _ = current
    return ""


def main() -> int:
    current = sys.stdin.read()
    prompt = build_prompt(current)
    proposal = call_your_model(prompt, current)
    if not proposal.strip():
        return 0
    sys.stdout.write(proposal)
    if not proposal.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
