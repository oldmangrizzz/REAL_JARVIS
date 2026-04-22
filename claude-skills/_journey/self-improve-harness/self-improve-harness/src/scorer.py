#!/usr/bin/env python3
"""Real scorer for the Self-Improve Harness.

Uses the Anthropic SDK to meaningfully evaluate file quality.
Framework-agnostic: works from Claude Code, Claude Code, Hermes, cron, or any agent.

Contract:
- Reads current file content from stdin
- Receives TARGET_PATH in env
- Writes a single float 0.0-1.0 to stdout
- Exits 0 on success

Requirements:
- ANTHROPIC_API_KEY environment variable (or ~/.anthropic/api_key file)
- anthropic Python package

Configuration (env vars, all optional):
- SCORER_MODEL: model to use (default: claude-haiku-4-5-20251001)
- SCORER_MAX_TOKENS: max response tokens (default: 256)

Version: 2
Changes: Added retry logic, improved heuristic fallback, scoring dimension breakdown with SCORER_VERBOSE
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path


__version__ = "2.0.0"


def get_api_key() -> str | None:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key
    keyfile = Path.home() / ".anthropic" / "api_key"
    if keyfile.exists():
        return keyfile.read_text().strip()
    return None


SYSTEM_PROMPT = """You are a file quality scorer. Rate the given file on a 0.0-1.0 scale.

Scoring criteria:
- 0.0-0.2: broken, empty, or fundamentally wrong
- 0.2-0.4: exists but has major issues (stale, disorganized, missing key info)
- 0.4-0.6: functional but mediocre (works but could be better structured, more complete)
- 0.6-0.8: good quality (well-organized, mostly complete, minor improvements possible)
- 0.8-1.0: excellent (clear, complete, well-structured, production-ready)

Consider for the file type:
- Skills/prompts: trigger precision, instruction clarity, edge case coverage, safety
- Docs: accuracy, completeness, readability, structure, freshness
- Config: safety of defaults, completeness, documentation of options
- Code: correctness, error handling, readability, maintainability

Respond with ONLY a single decimal number between 0.0 and 1.0. Nothing else."""


def file_type_label(target_path: str) -> str:
    suffix = Path(target_path).suffix.lower()
    return {
        ".md": "markdown document",
        ".txt": "text file",
        ".json": "JSON configuration",
        ".yaml": "YAML configuration",
        ".yml": "YAML configuration",
        ".py": "Python code",
        ".js": "JavaScript code",
        ".ts": "TypeScript code",
    }.get(suffix, "file")


def score_with_sdk(content: str, target_path: str) -> float | None:
    """Try Anthropic SDK with retry logic. Returns None if unavailable."""
    api_key = get_api_key()
    if not api_key:
        return None
    try:
        import anthropic
    except ImportError:
        return None

    model = os.environ.get("SCORER_MODEL", "claude-haiku-4-5-20251001")
    max_tokens = int(os.environ.get("SCORER_MAX_TOKENS", "256"))
    ft = file_type_label(target_path)
    max_retries = 1
    initial_backoff = 2.0

    client = anthropic.Anthropic(api_key=api_key)
    
    for attempt in range(max_retries + 1):
        try:
            response = client.messages.create(
                model=model,
                max_tokens=max_tokens,
                temperature=0.0,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": f"File: {target_path}\nType: {ft}\n\n{content}"}],
            )
            text = response.content[0].text.strip()
            match = re.search(r"(\d+\.?\d*)", text)
            if match:
                return max(0.0, min(1.0, float(match.group(1))))
            return None
        except Exception as exc:
            if attempt < max_retries:
                backoff = initial_backoff * (2 ** attempt)
                print(f"[scorer] SDK error on attempt {attempt + 1}, retrying in {backoff:.1f}s: {exc}", file=sys.stderr)
                time.sleep(backoff)
            else:
                print(f"[scorer] SDK error after {max_retries + 1} attempts: {exc}", file=sys.stderr)
    
    return None


def score_with_cli(content: str, target_path: str) -> float | None:
    """Try claude CLI fallback. Returns None if unavailable."""
    import shutil
    import subprocess

    claude_bin = shutil.which("claude")
    if not claude_bin:
        return None

    ft = file_type_label(target_path)
    prompt = f"{SYSTEM_PROMPT}\n\nFile: {target_path}\nType: {ft}\n\n{content}"
    try:
        proc = subprocess.run(
            [claude_bin, "--print", "--model", "haiku", "-p", prompt],
            capture_output=True, text=True, timeout=30,
        )
        if proc.returncode != 0:
            return None
        match = re.search(r"(\d+\.?\d*)", proc.stdout.strip())
        if match:
            return max(0.0, min(1.0, float(match.group(1))))
        return None
    except Exception:
        return None


def score_with_claude(content: str, target_path: str) -> float | None:
    """Score via SDK first, then CLI fallback."""
    result = score_with_sdk(content, target_path)
    if result is not None:
        return result
    return score_with_cli(content, target_path)


def heuristic_fallback(content: str, target_path: str) -> dict[str, float]:
    """Fallback scorer when API is unavailable. Returns dimension breakdown."""
    suffix = Path(target_path).suffix.lower()
    
    # Initialize dimensions
    dimensions = {
        "completeness": 0.45,
        "structure": 0.45,
        "correctness": 0.45,
        "clarity": 0.45,
    }
    
    # Completeness: length and coverage signals
    lines = content.count("\n")
    if lines > 10:
        dimensions["completeness"] += 0.05
    if lines > 50:
        dimensions["completeness"] += 0.05
    
    # Structure: formatting and organization
    if suffix == ".md":
        headings = content.count("\n#")
        if headings >= 2:
            dimensions["structure"] += 0.10
        if "```" in content:
            dimensions["structure"] += 0.05
        if any(marker in content for marker in ["## ", "### "]):
            dimensions["structure"] += 0.05
    elif suffix in {".json", ".yaml", ".yml"}:
        try:
            import json as json_module
            import yaml
            if suffix == ".json":
                json_module.loads(content)
                dimensions["structure"] += 0.10
            else:
                yaml.safe_load(content)
                dimensions["structure"] += 0.10
        except Exception:
            dimensions["structure"] -= 0.15
            dimensions["correctness"] -= 0.15
    elif suffix == ".py":
        if "def " in content or "class " in content:
            dimensions["structure"] += 0.08
        if '"""' in content or "'''" in content:
            dimensions["clarity"] += 0.08
        if "try:" in content and "except" in content:
            dimensions["correctness"] += 0.10
    
    # Correctness: negative markers and well-formed signals
    neg_markers = ["todo", "fixme", "tbd", "broken", "hack", "xxx"]
    neg_count = sum(1 for marker in neg_markers if marker in content.lower())
    dimensions["correctness"] -= min(0.20, neg_count * 0.05)
    
    # Clarity: proper formatting
    if content.endswith("\n"):
        dimensions["clarity"] += 0.02
    
    # Python-specific correctness
    if suffix == ".py":
        if "import " in content:
            dimensions["structure"] += 0.05
        if "type hint" in content.lower() or "->" in content:
            dimensions["clarity"] += 0.05
    
    # Clamp all dimensions to 0.0-1.0
    for key in dimensions:
        dimensions[key] = max(0.0, min(1.0, dimensions[key]))
    
    return dimensions


def main() -> int:
    content = sys.stdin.read()
    target_path = os.environ.get("TARGET_PATH", "unknown")
    verbose = os.environ.get("SCORER_VERBOSE", "").lower() in {"1", "true", "yes"}

    if not content.strip():
        if verbose:
            sys.stdout.write(json.dumps({"dimensions": {"completeness": 0.15, "structure": 0.15, "correctness": 0.15, "clarity": 0.15}, "score": 0.15}) + "\n")
        else:
            sys.stdout.write("0.15\n")
        return 0

    # Try Claude first, fall back to heuristic
    score = score_with_claude(content, target_path)
    if score is not None:
        if verbose:
            # For Claude-scored files, return a simple breakdown
            sys.stdout.write(json.dumps({"dimensions": {"api": score}, "score": score}) + "\n")
        else:
            sys.stdout.write(f"{score:.3f}\n")
        return 0
    
    # Fallback to heuristic with dimension breakdown
    dimensions = heuristic_fallback(content, target_path)
    avg_score = sum(dimensions.values()) / len(dimensions)
    
    if verbose:
        sys.stdout.write(json.dumps({"dimensions": dimensions, "score": avg_score}) + "\n")
    else:
        sys.stdout.write(f"{avg_score:.3f}\n")
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
