#!/usr/bin/env python3
"""Self-Improve Harness orchestrator.

A small, dependency-light orchestrator for recurring self-improvement cycles over
skills, docs, prompts, and config files.

What this starter actually ships:
- manifest loading and validation
- state, queue, and audit log persistence
- priority scoring
- regression and plateau locks
- quiet-hours gating
- manual approval queue persistence
- proposal validation (syntax, security, size, structure)
- atomic apply with rollback copies
- process lockfile (prevent concurrent runs)
- CLI commands for run, queue, state, approvals, health, reconcile, and bootstrap

What it intentionally does not ship:
- an LLM proposer implementation
- outbound notifications
- sandboxed test execution

Replace `generate_proposal()` with your own model or agent integration.

Iteration 2 improvements:
- Python syntax validation via compile()
- Markdown structure validation (no skipped heading levels)
- Max-size-change guard (reject >300% size changes)
"""

from __future__ import annotations

import argparse
import difflib
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG = Path(__file__).parent.parent / "config" / "integration.yaml"

# Exit codes -- use these in scripts and cron health checks.
EXIT_OK = 0           # at least one target processed successfully
EXIT_ERROR = 1        # fatal error (bad config, missing manifest, etc.)
EXIT_QUIET_HOURS = 2  # run skipped by quiet-hours gating
EXIT_IDLE = 3         # nothing actionable in queue
EXIT_ALL_FAILED = 4   # every target in batch was rejected or failed
EXIT_LOCKED = 5       # another run is in progress (lockfile held)
ISO_FORMAT = "%Y-%m-%dT%H:%M:%S%z"

# Lockfile constants
LOCK_STALE_HOURS = 1
LOCK_TIMEOUT_SECONDS = 60  # fcntl.flock timeout


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def json_dump(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False, default=str)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def append_jsonl(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, ensure_ascii=False, default=str) + "\n")


def expand_value(value: Any) -> Any:
    if isinstance(value, str) and value.startswith("~/"):
        return str(Path(value).expanduser())
    if isinstance(value, dict):
        return {k: expand_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [expand_value(v) for v in value]
    return value


def load_config(config_path: str | None = None) -> dict[str, Any]:
    path = Path(config_path).expanduser() if config_path else DEFAULT_CONFIG
    raw = yaml.safe_load(read_text(path)) or {}
    cfg = expand_value(raw)
    cfg.setdefault("resources", {})
    cfg.setdefault("paths", {})
    cfg.setdefault("orchestrator", {})
    cfg.setdefault("approval", {})
    cfg.setdefault("validator", {})
    cfg.setdefault("notifications", {})
    cfg.setdefault("locks", {})
    cfg["_config_path"] = str(path)
    return cfg


def manifest_path_from_args(manifest_path: str) -> Path:
    return Path(manifest_path).expanduser()


def load_manifest(manifest_path: str) -> list[dict[str, Any]]:
    path = manifest_path_from_args(manifest_path)
    manifest = json.loads(read_text(path))
    if not isinstance(manifest, list):
        raise ValueError("Manifest must be a JSON array.")
    # An empty manifest is valid; return early so callers get an empty list rather
    # than falling through to the queue-fallback path with stale data.
    if len(manifest) == 0:
        return []
    validated: list[dict[str, Any]] = []
    for index, item in enumerate(manifest):
        if not isinstance(item, dict):
            raise ValueError(f"Manifest entry {index} must be an object.")
        # Skip metadata-only entries that have no path (like _comment, _schema entries).
        if "path" not in item:
            if any(k.startswith("_") for k in item):
                continue
            raise ValueError(f"Manifest entry {index} is missing required field 'path'.")
        entry = dict(item)
        # Validate weight is a positive number.
        try:
            entry["weight"] = max(0.0, float(entry.get("weight", 1.0) or 1.0))
        except (TypeError, ValueError):
            entry["weight"] = 1.0
        entry.setdefault("type", "doc")
        entry.setdefault("category", entry["type"])
        entry.setdefault("auto_approve", True)
        validated.append(entry)
    return validated


def get_path(cfg: dict[str, Any], *keys: str, fallback: str | None = None) -> Path:
    cursor: Any = cfg
    for key in keys:
        cursor = cursor[key]
    if fallback is not None and not cursor:
        cursor = fallback
    return Path(str(cursor)).expanduser()


def state_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "state_file")


def queue_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "queue_file")


def proposals_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "proposals_file")


def scores_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "scores_file")


def validation_log_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "validation_log")


def apply_log_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "orchestrator", "apply_log")


def approval_queue_file(cfg: dict[str, Any]) -> Path:
    configured = cfg.get("approval", {}).get("queue_file")
    if configured:
        return Path(configured).expanduser()
    return get_path(cfg, "paths", "harness_base") / "data" / "approval-queue.json"


def rollback_dir(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "paths", "rollback_dir")


def lock_file(cfg: dict[str, Any]) -> Path:
    return get_path(cfg, "paths", "harness_base") / "data" / "run.lock"


def load_state(cfg: dict[str, Any]) -> dict[str, Any]:
    path = state_file(cfg)
    if path.exists():
        try:
            data = json.loads(read_text(path))
            if not isinstance(data, dict):
                raise ValueError("state file must be a JSON object")
            return data
        except Exception as exc:
            print(f"[warn] state file corrupt, resetting: {exc}", file=sys.stderr)
    return {
        "version": 2,
        "locks": {},
        "scores": {},
        "last_run": None,
        "cycle_count": 0,
    }


def save_state(cfg: dict[str, Any], state: dict[str, Any]) -> None:
    write_text(state_file(cfg), json_dump(state))
    append_jsonl(scores_file(cfg), {
        "ts": utc_now().isoformat(),
        "scores": state.get("scores", {}),
        "cycle_count": state.get("cycle_count", 0),
    })


def load_queue(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    path = queue_file(cfg)
    if path.exists():
        try:
            data = json.loads(read_text(path))
            if not isinstance(data, list):
                raise ValueError("queue file must be a JSON array")
            return data
        except Exception as exc:
            print(f"[warn] queue file corrupt, returning empty: {exc}", file=sys.stderr)
    return []


def save_queue(cfg: dict[str, Any], queue: list[dict[str, Any]]) -> None:
    write_text(queue_file(cfg), json_dump(queue))


def load_approval_queue(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    path = approval_queue_file(cfg)
    if path.exists():
        try:
            data = json.loads(read_text(path))
            if not isinstance(data, list):
                raise ValueError("approval queue must be a JSON array")
            return data
        except Exception as exc:
            print(f"[warn] approval queue file corrupt, returning empty: {exc}", file=sys.stderr)
    return []


def save_approval_queue(cfg: dict[str, Any], queue: list[dict[str, Any]]) -> None:
    write_text(approval_queue_file(cfg), json_dump(queue))


def acquire_lock(cfg: dict[str, Any]) -> tuple[bool, str | None]:
    """Acquire a process lock. Returns (success, error_message).
    
    Detects and breaks stale locks (older than LOCK_STALE_HOURS).
    """
    lock_path = lock_file(cfg)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Check for stale lock
    if lock_path.exists():
        try:
            lock_data = json.loads(read_text(lock_path))
            lock_time = datetime.fromisoformat(lock_data.get("timestamp", ""))
            if utc_now() - lock_time > timedelta(hours=LOCK_STALE_HOURS):
                # Stale lock, remove it
                lock_path.unlink()
            else:
                # Fresh lock is held
                pid = lock_data.get("pid")
                return False, f"Another run in progress (PID: {pid})"
        except (json.JSONDecodeError, ValueError, KeyError):
            # Corrupted lock, remove and proceed
            try:
                lock_path.unlink()
            except OSError:
                pass
    
    # Try to acquire lock
    try:
        with lock_path.open("w") as f:
            lock_data = {
                "pid": os.getpid(),
                "timestamp": utc_now().isoformat(),
                "command": " ".join(sys.argv),
            }
            f.write(json_dump(lock_data))
            f.flush()
            # Try non-blocking lock
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Store file handle globally so we can unlock later
                acquire_lock._lock_handle = f  # type: ignore
                return True, None
            except IOError:
                return False, "Could not acquire lock (another process may be running)"
    except Exception as exc:
        return False, f"Lock acquire failed: {exc}"


def release_lock(cfg: dict[str, Any]) -> None:
    """Release the process lock."""
    try:
        if hasattr(acquire_lock, '_lock_handle'):
            f = acquire_lock._lock_handle  # type: ignore
            try:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                f.close()
            except OSError:
                pass
            delattr(acquire_lock, '_lock_handle')
    except (AttributeError, OSError):
        pass
    
    # Remove lock file
    try:
        lock_path = lock_file(cfg)
        if lock_path.exists():
            lock_path.unlink()
    except OSError:
        pass


def is_quiet_hours(cfg: dict[str, Any], now: datetime | None = None) -> bool:
    now = now or utc_now()
    resources = cfg.get("resources", {})
    start = resources.get("quiet_hours_start")
    end = resources.get("quiet_hours_end")
    if start is None or end is None:
        return False
    try:
        start = int(start)
        end = int(end)
    except (TypeError, ValueError):
        return False
    hour = now.astimezone().hour
    if start == end:
        return False
    if start < end:
        return start <= hour < end
    return hour >= start or hour < end


def get_score_history(state: dict[str, Any], path: str) -> list[float]:
    return state.get("scores", {}).get(path, [])


def get_priority(target: dict[str, Any], state: dict[str, Any]) -> float:
    score = float(target.get("last_score", 0.5) or 0.5)
    weight = float(target.get("weight", 1.0) or 1.0)
    base = (1.0 - score) * weight
    last_improved = target.get("last_improved")
    if last_improved:
        try:
            days_since = (utc_now() - datetime.fromisoformat(last_improved)).total_seconds() / 86400
            recency_weight = min(2.0, 1.0 + max(days_since, 0) * 0.1)
        except (ValueError, TypeError):
            recency_weight = 2.0
    else:
        recency_weight = 2.0
    lock = state.get("locks", {}).get(target["path"])
    if lock:
        try:
            if utc_now() < datetime.fromisoformat(lock["until"]):
                return -1.0
        except (ValueError, TypeError):
            pass
    return base * recency_weight


def apply_lock(path: str, state: dict[str, Any], hours: int, reason: str) -> None:
    until = utc_now() + timedelta(hours=max(0, hours))
    state.setdefault("locks", {})[path] = {
        "until": until.isoformat(),
        "reason": reason,
        "locked_at": utc_now().isoformat(),
    }


def check_regression(path: str, state: dict[str, Any], threshold: float = -0.05) -> bool:
    scores = get_score_history(state, path)
    if len(scores) < 3:
        return False
    try:
        recent = [float(s) for s in scores[-3:]]
    except (TypeError, ValueError):
        return False
    deltas = [recent[i + 1] - recent[i] for i in range(2)]
    return all(delta < threshold for delta in deltas)


def check_plateau(path: str, state: dict[str, Any], threshold: float = 0.02) -> bool:
    scores = get_score_history(state, path)
    if len(scores) < 4:
        return False
    try:
        recent = [float(s) for s in scores[-4:]]
    except (TypeError, ValueError):
        return False
    deltas = [abs(recent[i + 1] - recent[i]) for i in range(3)]
    return all(delta < threshold for delta in deltas)


def score_target(path: Path, cfg: dict[str, Any]) -> float:
    """Return a quality score for the file at *path* between 0.0 and 1.0.

    If ``scorer.command`` is set in config, that command is run with:
    - current file content on stdin
    - TARGET_PATH as an env var
    The command must write a single float (0.0-1.0) to stdout and exit 0.

    Otherwise falls back to a built-in keyword heuristic suitable only for
    bootstrapping. Replace or configure a real scorer before trusting lock
    decisions.
    """
    scorer_cfg = cfg.get("scorer", {})
    command = scorer_cfg.get("command") if scorer_cfg else None
    if command:
        timeout = int(scorer_cfg.get("timeout_seconds", 30))
        current = read_text(path) if path.exists() else ""
        env = os.environ.copy()
        env["TARGET_PATH"] = str(path)
        try:
            proc = subprocess.run(
                command,
                shell=True,
                input=current,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env,
            )
            if proc.returncode == 0:
                return min(1.0, max(0.0, float(proc.stdout.strip())))
            print(
                f"[scorer] exited {proc.returncode} for {path}: {proc.stderr[:200]}",
                file=sys.stderr,
            )
        except (subprocess.TimeoutExpired, ValueError):
            print(f"[scorer] error for {path}, using heuristic", file=sys.stderr)
        except Exception as exc:
            print(f"[scorer] error for {path}: {exc}, using heuristic", file=sys.stderr)

    # Built-in heuristic fallback -- weak signal, fine for bootstrapping only.
    if not path.exists():
        return 0.3
    content = read_text(path)
    size = len(content)
    score = 0.5
    if size > 100:
        score += 0.1
    if "\n\n" in content:
        score += 0.1
    if any(word in content.lower() for word in ["error", "todo", "fixme", "broken"]):
        score -= 0.1
    if path.suffix in {".md", ".txt", ".json", ".yaml", ".yml", ".py"}:
        score += 0.05
    return min(1.0, max(0.0, score))


def estimate_delta(proposal: str, current_score: float, cfg: dict[str, Any]) -> float:
    if not proposal:
        return 0.0
    words = len(proposal.split())
    if words > 250:
        return 0.07
    if words > 100:
        return 0.05
    return 0.02


def generate_proposal(path: Path, target: dict[str, Any], cfg: dict[str, Any]) -> str:
    """Return proposed replacement content for the file at *path*.

    If ``proposer.command`` is set in config, that command is run with:
    - current file content on stdin
    - TARGET_PATH, TARGET_TYPE, TARGET_CATEGORY, TARGET_NAME as env vars
    The command must write the full proposed replacement content to stdout
    and exit 0. Any non-zero exit is treated as no proposal.

    Without a configured command this returns an empty string (no-op).
    Replace this function or set ``proposer.command`` to activate the loop.
    """
    proposer_cfg = cfg.get("proposer", {})
    command = proposer_cfg.get("command") if proposer_cfg else None
    if not command:
        return ""
    timeout = int(proposer_cfg.get("timeout_seconds", 120))
    current = read_text(path) if path.exists() else ""
    env = os.environ.copy()
    env["TARGET_PATH"] = str(path)
    env["TARGET_TYPE"] = str(target.get("type", "doc"))
    env["TARGET_CATEGORY"] = str(target.get("category", ""))
    env["TARGET_NAME"] = str(target.get("name", path.name))
    try:
        proc = subprocess.run(
            command,
            shell=True,
            input=current,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        if proc.returncode != 0:
            print(
                f"[proposer] exited {proc.returncode} for {path}: {proc.stderr[:200]}",
                file=sys.stderr,
            )
            return ""
        return proc.stdout
    except subprocess.TimeoutExpired:
        print(f"[proposer] timed out after {timeout}s for {path}", file=sys.stderr)
        return ""
    except Exception as exc:
        print(f"[proposer] error for {path}: {exc}", file=sys.stderr)
        return ""


def proposal_diff(original: str, proposal: str, path: Path, max_lines: int) -> str:
    diff = list(difflib.unified_diff(
        original.splitlines(),
        proposal.splitlines(),
        fromfile=str(path),
        tofile=f"{path} (proposal)",
        lineterm="",
    ))
    if len(diff) > max_lines:
        diff = diff[:max_lines] + [f"... diff truncated after {max_lines} lines"]
    return "\n".join(diff)


def validate_python_syntax(content: str) -> tuple[bool, str]:
    """Validate Python syntax using compile(). Returns (valid, message)."""
    try:
        compile(content, "<proposal>", "exec")
        return True, "ok"
    except SyntaxError as exc:
        return False, f"python syntax error at line {exc.lineno}: {exc.msg}"
    except Exception as exc:
        return False, f"python validation error: {exc}"


def validate_markdown_structure(content: str) -> tuple[bool, str]:
    """Validate markdown heading hierarchy. Returns (valid, message)."""
    lines = content.split("\n")
    last_level = 0
    for i, line in enumerate(lines, 1):
        if line.startswith("#"):
            # Count leading hashes
            level = len(line) - len(line.lstrip("#"))
            if level < 1 or level > 6:
                return False, f"invalid heading level at line {i}"
            # Check for skipped levels (e.g., # then ### without ##)
            if level > last_level + 1:
                return False, f"heading hierarchy skipped at line {i}: jumped from level {last_level} to {level}"
            last_level = level
    return True, "ok"


def validate_size_change(original: str, proposal: str) -> tuple[bool, str]:
    """Validate that proposal size is reasonable. Returns (valid, message)."""
    if not original:
        return True, "ok"
    orig_size = len(original)
    prop_size = len(proposal)
    # Reject if size changed by more than 300%
    if prop_size > orig_size * 4:
        pct = (prop_size / orig_size * 100) - 100
        return False, f"proposal size increased by {pct:.0f}% (max 300% allowed)"
    if prop_size < orig_size / 4:
        pct = 100 - (prop_size / orig_size * 100)
        return False, f"proposal size decreased by {pct:.0f}% (max 300% allowed)"
    return True, "ok"


def validate_proposal(proposal: str, target_path: Path, cfg: dict[str, Any]) -> tuple[bool, str]:
    """Validate proposal: syntax, security, size, and structure. Returns (valid, message)."""
    if not proposal:
        return True, "no proposal"
    
    suffix = target_path.suffix.lower()
    original = read_text(target_path) if target_path.exists() else ""
    
    # Check size change first (common across all file types)
    valid, msg = validate_size_change(original, proposal)
    if not valid:
        return False, msg
    
    # File-type-specific validation
    try:
        if suffix == ".json":
            json.loads(proposal)
        elif suffix in {".yaml", ".yml"}:
            yaml.safe_load(proposal)
        elif suffix == ".py":
            # Python: validate syntax
            valid, msg = validate_python_syntax(proposal)
            if not valid:
                return False, msg
        elif suffix == ".md":
            # Markdown: validate structure
            valid, msg = validate_markdown_structure(proposal)
            if not valid:
                return False, msg
    except Exception as exc:
        return False, f"syntax validation failed: {exc}"

    # Security check: forbidden patterns
    forbidden = [
        ("rm", "-rf", "/"),
        ("DROP", "TABLE"),
        ("DELETE", "FROM"),
        ("eval", "("),
        ("exec", "("),
        ("__import__",),
    ]
    upper = proposal.upper()
    for tokens in forbidden:
        haystack = proposal if any(token.islower() for token in tokens) else upper
        token_set = tokens if any(token.islower() for token in tokens) else tuple(token.upper() for token in tokens)
        if all(token in haystack for token in token_set):
            return False, f"forbidden pattern detected: {' '.join(tokens)}"
    
    return True, "ok"


def requires_manual_approval(target: dict[str, Any], cfg: dict[str, Any], target_path: Path) -> bool:
    if not target.get("auto_approve", True):
        return True
    required = cfg.get("validator", {}).get("require_manual_approval", [])
    if not required:
        return False
    if not isinstance(required, list):
        required = [str(required)]
    target_name = target.get("name", "")
    candidates = {str(target_path), target_path.name, target_name, target.get("type", "")}
    return any(rule in candidate for candidate in candidates for rule in required if rule)


def apply_proposal(proposal: str, target_path: Path, cfg: dict[str, Any]) -> tuple[bool, str, str | None]:
    if not proposal:
        return False, "empty proposal", None
    # Prevent path traversal: target must be an absolute resolved path.
    try:
        resolved = target_path.resolve(strict=False)
    except Exception as exc:
        return False, f"path resolution failed: {exc}", None
    if not resolved.is_absolute():
        return False, "target_path must be absolute", None
    rb_dir = rollback_dir(cfg)
    rb_dir.mkdir(parents=True, exist_ok=True)
    stamp = utc_now().strftime("%Y%m%dT%H%M%SZ")
    backup_dir = rb_dir / stamp
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path: Path | None = None
    if target_path.exists():
        backup_path = backup_dir / target_path.name
        shutil.copy2(target_path, backup_path)
        write_text(backup_dir / "original_hash.txt", hashlib.sha256(target_path.read_bytes()).hexdigest())
        # Also save the resolved original path so rollback can be targeted correctly.
        write_text(backup_dir / "original_path.txt", str(resolved))
    tmp = target_path.with_suffix(target_path.suffix + ".new")
    try:
        write_text(tmp, proposal)
        new_hash = hashlib.sha256(tmp.read_bytes()).hexdigest()
        tmp.replace(target_path)
        append_jsonl(apply_log_file(cfg), {
            "ts": utc_now().isoformat(),
            "path": str(target_path),
            "status": "applied",
            "sha256": new_hash,
            "rollback_dir": str(backup_dir),
        })
        return True, "ok", str(backup_dir)
    except Exception as exc:
        # Clean up the temp file if it survived.
        try:
            if tmp.exists():
                tmp.unlink()
        except OSError:
            pass
        if backup_path and backup_path.exists():
            shutil.copy2(backup_path, target_path)
        append_jsonl(apply_log_file(cfg), {
            "ts": utc_now().isoformat(),
            "path": str(target_path),
            "status": "apply_failed",
            "reason": str(exc),
            "rollback_dir": str(backup_dir),
        })
        return False, f"apply failed: {exc}", str(backup_dir)


def queue_manual_review(target: dict[str, Any], proposal: str, delta: float, cfg: dict[str, Any], target_path: Path) -> dict[str, Any]:
    queue = load_approval_queue(cfg)
    timeout_hours = int(cfg.get("approval", {}).get("timeout_hours", 2))
    max_diff_lines = int(cfg.get("approval", {}).get("diff_max_lines", 100))
    original = read_text(target_path) if target_path.exists() else ""
    entry = {
        "id": f"approval-{utc_now().strftime('%Y%m%dT%H%M%S%fZ')}",
        "path": str(target_path),
        "category": target.get("category"),
        "type": target.get("type"),
        "created_at": utc_now().isoformat(),
        "expires_at": (utc_now() + timedelta(hours=timeout_hours)).isoformat(),
        "delta": delta,
        "proposal": proposal,
        "diff": proposal_diff(original, proposal, target_path, max_diff_lines),
        "status": "pending",
    }
    queue.append(entry)
    save_approval_queue(cfg, queue)
    append_jsonl(validation_log_file(cfg), {
        "ts": utc_now().isoformat(),
        "path": str(target_path),
        "status": "pending_approval",
        "approval_id": entry["id"],
        "delta": delta,
    })
    return entry


def expire_approval_queue(cfg: dict[str, Any]) -> int:
    queue = load_approval_queue(cfg)
    now = utc_now()
    changed = 0
    for entry in queue:
        if entry.get("status") != "pending":
            continue
        expires_at = entry.get("expires_at")
        if not expires_at:
            continue
        try:
            if now >= datetime.fromisoformat(expires_at):
                entry["status"] = "expired"
                entry["expired_at"] = now.isoformat()
                changed += 1
        except (ValueError, TypeError):
            # Malformed expiry: expire defensively so it doesn't block the queue forever.
            entry["status"] = "expired"
            entry["expired_at"] = now.isoformat()
            entry["expiry_error"] = f"could not parse expires_at: {expires_at!r}"
            changed += 1
    if changed:
        save_approval_queue(cfg, queue)
    return changed


def purge_expired_approvals(cfg: dict[str, Any]) -> int:
    """Remove expired entries from the approval queue. Returns count removed.

    expired entries stay in the file after expire_approval_queue() marks them;
    this function physically removes them to prevent unbounded file growth.
    Call from run_cycle on every pass.
    """
    queue = load_approval_queue(cfg)
    active = [e for e in queue if e.get("status") != "expired"]
    removed = len(queue) - len(active)
    if removed:
        save_approval_queue(cfg, active)
    return removed


def process_target(target: dict[str, Any], state: dict[str, Any], cfg: dict[str, Any], dry_run: bool = False) -> dict[str, Any]:
    path = target["path"]
    resolved = Path(path).expanduser()
    current_score = score_target(resolved, cfg)
    target["last_score"] = current_score
    proposal = generate_proposal(resolved, target, cfg)
    proposal_generated = bool(proposal)
    delta = estimate_delta(proposal, current_score, cfg) if proposal else 0.0
    if proposal:
        append_jsonl(proposals_file(cfg), {
            "ts": utc_now().isoformat(),
            "path": path,
            "delta": delta,
            "proposal_len": len(proposal),
        })
    valid, validation_msg = validate_proposal(proposal, resolved, cfg)
    append_jsonl(validation_log_file(cfg), {
        "ts": utc_now().isoformat(),
        "path": path,
        "status": "validated" if valid else "rejected",
        "message": validation_msg,
    })
    if not valid:
        return {
            "path": path,
            "status": "rejected",
            "reason": validation_msg,
            "score": current_score,
            "current_score": current_score,
            "proposal_generated": proposal_generated,
            "validation_status": validation_msg,
            "applied": False,
            "delta": delta,
        }
    if dry_run:
        return {
            "path": path,
            "status": "dry_run",
            "score": current_score,
            "current_score": current_score,
            "proposal_generated": proposal_generated,
            "validation_status": validation_msg,
            "applied": False,
            "delta": delta,
        }
    if not proposal:
        return {
            "path": path,
            "status": "no_proposal",
            "score": current_score,
            "current_score": current_score,
            "proposal_generated": False,
            "validation_status": validation_msg,
            "applied": False,
            "delta": delta,
        }
    if requires_manual_approval(target, cfg, resolved):
        approval = queue_manual_review(target, proposal, delta, cfg, resolved)
        return {
            "path": path,
            "status": "pending_approval",
            "approval_id": approval["id"],
            "score": current_score,
            "current_score": current_score,
            "proposal_generated": proposal_generated,
            "validation_status": validation_msg,
            "applied": False,
            "delta": delta,
        }
    applied, apply_msg, rollback_path = apply_proposal(proposal, resolved, cfg)
    return {
        "path": path,
        "status": "applied" if applied else "apply_failed",
        "reason": apply_msg,
        "rollback_path": rollback_path,
        "delta": delta,
        "score": current_score,
        "current_score": current_score,
        "proposal_generated": proposal_generated,
        "validation_status": validation_msg,
        "applied": applied,
    }


def run_cycle(manifest_path: str, config_path: str | None = None, dry_run: bool = False) -> dict[str, Any]:
    cfg = load_config(config_path)
    
    # Acquire process lock
    locked, lock_error = acquire_lock(cfg)
    if not locked:
        return {"status": "locked", "reason": lock_error}
    
    try:
        manifest = load_manifest(manifest_path)
        state = load_state(cfg)
        expired = expire_approval_queue(cfg)
        purged = purge_expired_approvals(cfg)
        if is_quiet_hours(cfg):
            state["last_run"] = utc_now().isoformat()
            state["cycle_count"] = state.get("cycle_count", 0) + 1
            save_state(cfg, state)
            return {"status": "quiet_hours", "cycle": state["cycle_count"], "expired_approvals": expired, "purged_approvals": purged}
        # Use persisted queue if it is non-empty; otherwise reset from manifest.
        # When the queue runs dry, reload the full manifest so targets cycle again.
        persisted_queue = load_queue(cfg)
        queue = persisted_queue if persisted_queue else manifest
        now = utc_now()
        active_queue: list[dict[str, Any]] = []
        locked_queue: list[dict[str, Any]] = []
        for item in queue:
            lock = state.get("locks", {}).get(item.get("path", ""))
            locked = False
            if lock:
                try:
                    if now < datetime.fromisoformat(lock["until"]):
                        locked = True
                except (ValueError, TypeError):
                    pass
            if locked:
                locked_queue.append(item)
            else:
                active_queue.append(item)
        if not active_queue:
            state["last_run"] = now.isoformat()
            state["cycle_count"] = state.get("cycle_count", 0) + 1
            save_state(cfg, state)
            return {
                "status": "idle",
                "cycle": state["cycle_count"],
                "expired_approvals": expired,
                "purged_approvals": purged,
                "locked_count": len(locked_queue),
            }
        active_queue.sort(key=lambda t: get_priority(t, state), reverse=True)
        try:
            max_iter = max(1, int(cfg.get("orchestrator", {}).get("max_iterations_per_cycle", 3)))
        except (TypeError, ValueError):
            max_iter = 3
        batch = active_queue[:max_iter]
        remaining = active_queue[max_iter:] + locked_queue
        save_queue(cfg, remaining)
        results: list[dict[str, Any]] = []
        try:
            regression_hours = max(0, int(cfg.get("locks", {}).get("regression_hours", 72)))
        except (TypeError, ValueError):
            regression_hours = 72
        try:
            plateau_hours = max(0, int(cfg.get("locks", {}).get("plateau_hours", 48)))
        except (TypeError, ValueError):
            plateau_hours = 48
        try:
            delay = max(0, int(cfg.get("orchestrator", {}).get("iteration_delay_seconds", 0)))
        except (TypeError, ValueError):
            delay = 0
        for i, target in enumerate(batch):
            result = process_target(target, state, cfg, dry_run=dry_run)
            results.append(result)
            score = result.get("score")
            if score is not None:
                state.setdefault("scores", {}).setdefault(target["path"], []).append(score)
                if check_regression(target["path"], state):
                    apply_lock(target["path"], state, regression_hours, "regression")
                elif check_plateau(target["path"], state):
                    apply_lock(target["path"], state, plateau_hours, "plateau")
            if delay > 0 and i < len(batch) - 1:
                time.sleep(delay)
        state["last_run"] = utc_now().isoformat()
        state["cycle_count"] = state.get("cycle_count", 0) + 1
        save_state(cfg, state)
        return {"status": "ok", "cycle": state["cycle_count"], "expired_approvals": expired, "purged_approvals": purged, "results": results}
    finally:
        release_lock(cfg)


def approve_proposal(approval_id: str, config_path: str | None = None) -> dict[str, Any]:
    """Approve a pending proposal by ID. Applies the change with rollback."""
    cfg = load_config(config_path)
    queue = load_approval_queue(cfg)
    for entry in queue:
        if entry.get("id") == approval_id and entry.get("status") == "pending":
            target_path = Path(entry["path"]).expanduser()
            proposal = entry.get("proposal", "")
            if not proposal:
                entry["status"] = "rejected"
                entry["rejected_at"] = utc_now().isoformat()
                entry["reason"] = "empty proposal"
                save_approval_queue(cfg, queue)
                return {"status": "rejected", "reason": "empty proposal", "id": approval_id}
            applied, msg, rb_path = apply_proposal(proposal, target_path, cfg)
            entry["status"] = "approved" if applied else "apply_failed"
            entry["resolved_at"] = utc_now().isoformat()
            entry["apply_message"] = msg
            entry["rollback_path"] = rb_path
            save_approval_queue(cfg, queue)
            return {
                "status": "approved" if applied else "apply_failed",
                "id": approval_id,
                "path": str(target_path),
                "message": msg,
                "rollback_path": rb_path,
            }
    return {"status": "not_found", "id": approval_id}


def reject_proposal(approval_id: str, reason: str = "", config_path: str | None = None) -> dict[str, Any]:
    """Reject a pending proposal by ID."""
    cfg = load_config(config_path)
    queue = load_approval_queue(cfg)
    for entry in queue:
        if entry.get("id") == approval_id and entry.get("status") == "pending":
            entry["status"] = "rejected"
            entry["rejected_at"] = utc_now().isoformat()
            entry["reason"] = reason or "manually rejected"
            save_approval_queue(cfg, queue)
            append_jsonl(validation_log_file(cfg), {
                "ts": utc_now().isoformat(),
                "path": entry.get("path"),
                "status": "rejected",
                "approval_id": approval_id,
                "reason": reason or "manually rejected",
            })
            return {"status": "rejected", "id": approval_id, "path": entry.get("path")}
    return {"status": "not_found", "id": approval_id}


def rollback_file(rollback_path: str, config_path: str | None = None) -> dict[str, Any]:
    """Restore a file from a rollback backup directory."""
    cfg = load_config(config_path)
    rb = Path(rollback_path).expanduser()
    if not rb.exists() or not rb.is_dir():
        return {"status": "error", "reason": f"rollback dir not found: {rollback_path}"}
    original_path_file = rb / "original_path.txt"
    if not original_path_file.exists():
        return {"status": "error", "reason": "no original_path.txt in rollback dir"}
    target = Path(read_text(original_path_file).strip())
    # Find the backup file (the one that isn't metadata)
    backup_file = None
    for child in rb.iterdir():
        if child.name not in {"original_hash.txt", "original_path.txt"} and child.is_file():
            backup_file = child
            break
    if not backup_file:
        return {"status": "error", "reason": "no backup file found in rollback dir"}
    try:
        shutil.copy2(backup_file, target)
        append_jsonl(apply_log_file(cfg), {
            "ts": utc_now().isoformat(),
            "path": str(target),
            "status": "rolled_back",
            "from_rollback": str(rb),
        })
        return {"status": "restored", "path": str(target), "from": str(rb)}
    except Exception as exc:
        return {"status": "error", "reason": str(exc)}


def list_rollbacks(config_path: str | None = None) -> list[dict[str, Any]]:
    """List available rollback directories with metadata."""
    cfg = load_config(config_path)
    rb_root = rollback_dir(cfg)
    results: list[dict[str, Any]] = []
    if not rb_root.exists():
        return results
    for child in sorted(rb_root.iterdir(), reverse=True):
        if not child.is_dir():
            continue
        entry: dict[str, Any] = {"dir": str(child), "timestamp": child.name}
        orig_path = child / "original_path.txt"
        if orig_path.exists():
            entry["original_path"] = read_text(orig_path).strip()
        orig_hash = child / "original_hash.txt"
        if orig_hash.exists():
            entry["original_hash"] = read_text(orig_hash).strip()
        results.append(entry)
    return results


def health_check(config_path: str | None = None) -> dict[str, Any]:
    """Report health status: lock status, last run, queue depth, etc."""
    cfg = load_config(config_path)
    state = load_state(cfg)
    lock_path = lock_file(cfg)
    lock_held = False
    lock_pid = None
    lock_timestamp = None
    
    if lock_path.exists():
        try:
            lock_data = json.loads(read_text(lock_path))
            lock_pid = lock_data.get("pid")
            lock_timestamp = lock_data.get("timestamp")
            # Check if lock is stale
            try:
                lock_time = datetime.fromisoformat(lock_timestamp)
                if utc_now() - lock_time <= timedelta(hours=LOCK_STALE_HOURS):
                    lock_held = True
            except (ValueError, TypeError):
                lock_held = True
        except (json.JSONDecodeError, ValueError):
            pass
    
    queue = load_queue(cfg) or []
    approval_queue = load_approval_queue(cfg)
    approval_pending = [a for a in approval_queue if a.get("status") == "pending"]
    
    locks = state.get("locks", {})
    active_locks = {path: info for path, info in locks.items() if utc_now() < datetime.fromisoformat(info.get("until", "1970-01-01"))}
    
    return {
        "lock_held": lock_held,
        "lock_pid": lock_pid,
        "lock_timestamp": lock_timestamp,
        "last_run": state.get("last_run"),
        "cycle_count": state.get("cycle_count", 0),
        "queue_depth": len(queue),
        "approval_pending_count": len(approval_pending),
        "active_lock_count": len(active_locks),
        "stale_locks_present": False,
    }


def reconcile_queue(manifest_path: str, config_path: str | None = None, reset: bool = False) -> dict[str, Any]:
    """Compare manifest to queue. Optionally reset queue from manifest."""
    cfg = load_config(config_path)
    manifest = load_manifest(manifest_path)
    queue = load_queue(cfg)
    
    manifest_paths = {m.get("path") for m in manifest if "path" in m}
    queue_paths = {q.get("path") for q in queue if "path" in q}
    
    missing_from_queue = manifest_paths - queue_paths
    extra_in_queue = queue_paths - manifest_paths
    
    result = {
        "manifest_count": len(manifest),
        "queue_count": len(queue),
        "missing_from_queue": list(missing_from_queue),
        "extra_in_queue": list(extra_in_queue),
        "reset": reset,
    }
    
    if reset:
        save_queue(cfg, manifest)
        result["reset_status"] = "ok"
        result["new_queue_count"] = len(manifest)
    
    return result


def bootstrap_runtime(config_path: str | None = None) -> dict[str, str]:
    cfg = load_config(config_path)
    created = {}
    for path in [
        get_path(cfg, "paths", "harness_base"),
        get_path(cfg, "paths", "harness_base") / "logs",
        rollback_dir(cfg),
        state_file(cfg).parent,
        queue_file(cfg).parent,
        approval_queue_file(cfg).parent,
    ]:
        path.mkdir(parents=True, exist_ok=True)
        created[str(path)] = "ok"
    if not approval_queue_file(cfg).exists():
        save_approval_queue(cfg, [])
    if not queue_file(cfg).exists():
        save_queue(cfg, [])
    return created


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Self-Improve Harness orchestrator")
    parser.add_argument(
        "command", nargs="?", default="run",
        choices=["run", "queue", "state", "approvals", "bootstrap",
                 "approve", "reject", "rollback", "rollbacks",
                 "health", "reconcile"],
    )
    parser.add_argument("--manifest", required=False, help="Path to manifest JSON")
    parser.add_argument("--config", help="Path to integration.yaml")
    parser.add_argument("--dry-run", action="store_true", help="Score and validate only, never apply")
    parser.add_argument("--id", help="Approval ID for approve/reject commands")
    parser.add_argument("--reason", default="", help="Reason for reject command")
    parser.add_argument("--path", help="Rollback directory path for rollback command")
    parser.add_argument("--reset", action="store_true", help="Reset queue from manifest (reconcile command)")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command in {"run", "queue", "reconcile"} and not args.manifest:
        parser.error("--manifest is required for run, queue, and reconcile")
    if args.command in {"approve", "reject"} and not args.id:
        parser.error("--id is required for approve and reject")
    if args.command == "rollback" and not args.path:
        parser.error("--path is required for rollback")
    try:
        if args.command == "bootstrap":
            print(json_dump(bootstrap_runtime(args.config)))
            return EXIT_OK
        if args.command == "health":
            print(json_dump(health_check(args.config)))
            return EXIT_OK
        if args.command == "reconcile":
            print(json_dump(reconcile_queue(args.manifest, args.config, reset=args.reset)))
            return EXIT_OK
        if args.command == "run":
            result = run_cycle(args.manifest, args.config, dry_run=args.dry_run)
            print(json_dump(result))
            status = result.get("status")
            if status == "locked":
                return EXIT_LOCKED
            if status == "quiet_hours":
                return EXIT_QUIET_HOURS
            if status == "idle":
                return EXIT_IDLE
            results = result.get("results", [])
            if results and all(
                r.get("status") in {"rejected", "apply_failed"} for r in results
            ):
                return EXIT_ALL_FAILED
            return EXIT_OK
        if args.command == "queue":
            cfg = load_config(args.config)
            queue = load_queue(cfg) or load_manifest(args.manifest)
            print(json_dump(queue))
            return EXIT_OK
        if args.command == "state":
            print(json_dump(load_state(load_config(args.config))))
            return EXIT_OK
        if args.command == "approvals":
            print(json_dump(load_approval_queue(load_config(args.config))))
            return EXIT_OK
        if args.command == "approve":
            print(json_dump(approve_proposal(args.id, args.config)))
            return EXIT_OK
        if args.command == "reject":
            print(json_dump(reject_proposal(args.id, args.reason, args.config)))
            return EXIT_OK
        if args.command == "rollback":
            print(json_dump(rollback_file(args.path, args.config)))
            return EXIT_OK
        if args.command == "rollbacks":
            print(json_dump(list_rollbacks(args.config)))
            return EXIT_OK
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_ERROR
    return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
