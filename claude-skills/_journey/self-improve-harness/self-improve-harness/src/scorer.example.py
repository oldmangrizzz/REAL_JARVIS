#!/usr/bin/env python3
"""Example scorer adapter for the Self-Improve Harness.

Contract:
- reads current file content from stdin
- receives TARGET_PATH in env
- writes one float from 0.0 to 1.0 to stdout
- exits 0 on success

This example is still heuristic, but clearer and easier to replace than the
built-in scorer. Use it as a contract example, not as a serious evaluator.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def score_markdown_or_text(content: str) -> float:
    score = 0.45
    if len(content) > 200:
        score += 0.10
    if "\n\n" in content:
        score += 0.10
    if any(token in content.lower() for token in ["todo", "fixme", "tbd", "broken"]):
        score -= 0.15
    if content.endswith("\n"):
        score += 0.02
    return clamp(score)


def score_json_yaml_python(content: str) -> float:
    score = 0.50
    if len(content) > 100:
        score += 0.08
    if any(token in content.lower() for token in ["todo", "fixme", "pass", "broken"]):
        score -= 0.15
    return clamp(score)


def main() -> int:
    content = sys.stdin.read()
    target_path = Path(os.environ.get("TARGET_PATH", "unknown"))
    suffix = target_path.suffix.lower()
    if suffix in {".md", ".txt"}:
        score = score_markdown_or_text(content)
    elif suffix in {".json", ".yaml", ".yml", ".py"}:
        score = score_json_yaml_python(content)
    else:
        score = clamp(0.50 if content else 0.30)
    sys.stdout.write(f"{score:.3f}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
