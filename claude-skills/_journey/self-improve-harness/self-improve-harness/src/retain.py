#!/usr/bin/env python3
"""Retention utility for the Self-Improve Harness.

What it does:
- deletes rollback directories older than N days
- archives JSONL entries older than N days into data/archive/
- rewrites active JSONL files to keep only recent entries

Safe by default with --dry-run.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "config" / "integration.yaml"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as tmp:
        tmp.write(content)
        tmp_name = tmp.name
    Path(tmp_name).replace(path)


def load_config(path: str | None) -> dict[str, Any]:
    cfg_path = Path(path).expanduser() if path else DEFAULT_CONFIG
    data = yaml.safe_load(read_text(cfg_path)) or {}
    return data if isinstance(data, dict) else {}


def get_path(cfg: dict[str, Any], *keys: str) -> Path:
    value: Any = cfg
    for key in keys:
        value = value[key]
    return Path(str(value)).expanduser()


def archive_dir(cfg: dict[str, Any]) -> Path:
    base = get_path(cfg, "paths", "harness_base")
    return base / "data" / "archive"


def split_jsonl_by_age(path: Path, cutoff: datetime) -> tuple[list[str], list[str]]:
    keep: list[str] = []
    archive: list[str] = []
    if not path.exists():
        return keep, archive
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        try:
            obj = json.loads(raw_line)
            ts = obj.get("ts")
            if not ts:
                keep.append(raw_line)
                continue
            when = datetime.fromisoformat(ts)
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
            if when < cutoff:
                archive.append(raw_line)
            else:
                keep.append(raw_line)
        except Exception:
            keep.append(raw_line)
    return keep, archive


def append_lines(path: Path, lines: list[str]) -> None:
    if not lines:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        for line in lines:
            handle.write(line)
            if not line.endswith("\n"):
                handle.write("\n")


def retain_jsonl(cfg: dict[str, Any], cutoff: datetime, dry_run: bool) -> list[dict[str, Any]]:
    files = [
        get_path(cfg, "orchestrator", "proposals_file"),
        get_path(cfg, "orchestrator", "scores_file"),
        get_path(cfg, "orchestrator", "validation_log"),
        get_path(cfg, "orchestrator", "apply_log"),
    ]
    archive_root = archive_dir(cfg)
    results: list[dict[str, Any]] = []
    for path in files:
        keep, archive = split_jsonl_by_age(path, cutoff)
        archive_path = archive_root / f"{path.stem}.archive.jsonl"
        result = {
            "file": str(path),
            "archive_file": str(archive_path),
            "archived_lines": len(archive),
            "kept_lines": len(keep),
        }
        if archive and not dry_run:
            append_lines(archive_path, archive)
            write_text(path, ("\n".join(keep) + ("\n" if keep else "")))
        results.append(result)
    return results


def retain_rollbacks(cfg: dict[str, Any], cutoff: datetime, dry_run: bool) -> list[dict[str, Any]]:
    rollback_root = get_path(cfg, "paths", "rollback_dir")
    results: list[dict[str, Any]] = []
    if not rollback_root.exists():
        return results
    for child in sorted(rollback_root.iterdir()):
        if not child.is_dir():
            continue
        mtime = datetime.fromtimestamp(child.stat().st_mtime, tz=timezone.utc)
        expired = mtime < cutoff
        result = {
            "path": str(child),
            "mtime": mtime.isoformat(),
            "expired": expired,
            "removed": False,
        }
        if expired and not dry_run:
            shutil.rmtree(child)
            result["removed"] = True
        results.append(result)
    return results


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Retention utility for Self-Improve Harness")
    parser.add_argument("--config", help="Path to integration.yaml")
    parser.add_argument("--rollback-days", type=int, default=14, help="Keep rollback dirs newer than this many days")
    parser.add_argument("--log-days", type=int, default=30, help="Keep JSONL entries newer than this many days")
    parser.add_argument("--dry-run", action="store_true", help="Report actions without changing files")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    cfg = load_config(args.config)
    rollback_cutoff = utc_now() - timedelta(days=max(0, args.rollback_days))
    log_cutoff = utc_now() - timedelta(days=max(0, args.log_days))

    rollback_results = retain_rollbacks(cfg, rollback_cutoff, args.dry_run)
    log_results = retain_jsonl(cfg, log_cutoff, args.dry_run)

    summary = {
        "dry_run": args.dry_run,
        "rollback_cutoff": rollback_cutoff.isoformat(),
        "log_cutoff": log_cutoff.isoformat(),
        "rollback_dirs_seen": len(rollback_results),
        "rollback_dirs_removed": sum(1 for item in rollback_results if item.get("removed")),
        "log_files_seen": len(log_results),
        "log_lines_archived": sum(item.get("archived_lines", 0) for item in log_results),
        "archive_dir": str(archive_dir(cfg)),
        "rollbacks": rollback_results,
        "logs": log_results,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
