#!/usr/bin/env python3
"""Pull new YouTube channel transcripts into a local JARVIS intake folder."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "transcripts" / "youtube-intake"
DEFAULT_STATE_PATH = REPO_ROOT / "storage" / "youtube-intake-state.json"
YOUTUBE_FEED = "https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"

CHANNELS = [
    {
        "name": "Github Awesome",
        "channel_id": "UC9Rrud-8CaHokDtK9FszvRg",
        "placement_bias": ["memory", "forge", "maker_shop", "mac", "gcp"],
    },
    {
        "name": "ManuAGI",
        "channel_id": "UC1weYqfDgX0ALlNOSzcyblQ",
        "placement_bias": ["forge", "memory", "gcp", "alpha", "mac"],
    },
    {
        "name": "AI Agents Studio / ManuAgents",
        "channel_id": "UCAawqobkJZ28OLcYcMgqYaw",
        "placement_bias": ["forge", "memory", "gcp", "alpha", "mac"],
    },
]

HIGH_SIGNAL_TERMS = {
    "maker_shop": ["3d print", "3d printing", "cad", "stl", "step", "dxf", "urdf", "robot", "hardware"],
    "mac": ["mac", "macos", "desktop", "computer use", "background", "screen", "browser"],
    "quest": ["quest", "xr", "spatial", "webgpu", "three.js", "3js", "webgl", "unity"],
    "memory": ["memory", "knowledge", "wiki", "obsidian", "mcp", "postgres", "pgvector", "neo4j"],
    "forge": ["agent", "agents", "swarm", "orchestration", "tdd", "workflow", "code review"],
    "gcp": ["gpu", "nvidia", "kernel", "inference", "cloud", "server"],
    "alpha": ["home assistant", "proxmox", "vm", "cluster", "docker", "sqlite", "queue"],
    "mobile_watch": ["ios", "iphone", "ipad", "watch", "watchos", "shortcut", "haptic"],
    "security": ["credential", "password", "token", "zero trust", "proxy", "auth", "encrypted"],
}


@dataclass(frozen=True)
class FeedEntry:
    channel: str
    channel_id: str
    video_id: str
    title: str
    url: str
    published: str


def load_state(path: Path) -> dict[str, list[str]]:
    if not path.exists():
        return {"seen_video_ids": []}
    return json.loads(path.read_text(encoding="utf-8"))


def save_state(path: Path, state: dict[str, list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def fetch_feed(channel: dict[str, object]) -> list[FeedEntry]:
    channel_id = str(channel.get("channel_id", "")).strip()
    if not channel_id:
        return []
    with urllib.request.urlopen(YOUTUBE_FEED.format(channel_id=channel_id), timeout=20) as response:
        xml = response.read()
    root = ET.fromstring(xml)
    ns = {
        "atom": "http://www.w3.org/2005/Atom",
        "yt": "http://www.youtube.com/xml/schemas/2015",
    }
    entries: list[FeedEntry] = []
    for entry in root.findall("atom:entry", ns):
        video_id = entry.findtext("yt:videoId", default="", namespaces=ns)
        title = entry.findtext("atom:title", default="", namespaces=ns)
        published = entry.findtext("atom:published", default="", namespaces=ns)
        link = entry.find("atom:link", ns)
        url = link.attrib.get("href", f"https://www.youtube.com/watch?v={video_id}") if link is not None else f"https://www.youtube.com/watch?v={video_id}"
        if video_id:
            entries.append(FeedEntry(str(channel["name"]), channel_id, video_id, title, url, published))
    return entries


def run_yt_dlp(entry: FeedEntry, output_dir: Path) -> tuple[Path | None, Path | None]:
    output_dir.mkdir(parents=True, exist_ok=True)
    output_template = str(output_dir / "%(id)s.%(ext)s")
    command = [
        "yt-dlp",
        "--skip-download",
        "--write-auto-subs",
        "--write-subs",
        "--sub-langs",
        "en.*",
        "--convert-subs",
        "vtt",
        "--write-description",
        "--write-info-json",
        "-o",
        output_template,
        entry.url,
    ]
    subprocess.run(command, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    transcript = first_existing(output_dir.glob(f"{entry.video_id}*.vtt"))
    info = output_dir / f"{entry.video_id}.info.json"
    return transcript, info if info.exists() else None


def first_existing(paths: Iterable[Path]) -> Path | None:
    return next((path for path in sorted(paths) if path.exists()), None)


def vtt_to_text(path: Path) -> str:
    lines: list[str] = []
    seen: set[str] = set()
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line == "WEBVTT" or "-->" in line or line.isdigit():
            continue
        line = re.sub(r"<[^>]+>", "", line)
        if line and line not in seen:
            seen.add(line)
            lines.append(line)
    return "\n".join(lines).strip()


def placement_scores(text: str, channel_bias: list[str]) -> dict[str, int]:
    lowered = text.lower()
    scores: dict[str, int] = {key: 0 for key in HIGH_SIGNAL_TERMS}
    for key, terms in HIGH_SIGNAL_TERMS.items():
        scores[key] = sum(lowered.count(term) for term in terms)
    for key in channel_bias:
        if key in scores:
            scores[key] += 1
    return {key: value for key, value in sorted(scores.items(), key=lambda item: item[1], reverse=True) if value > 0}


def write_intake(entry: FeedEntry, output_dir: Path, transcript_path: Path | None, info_path: Path | None, channel_bias: list[str]) -> Path:
    transcript_text = vtt_to_text(transcript_path) if transcript_path else ""
    info = json.loads(info_path.read_text(encoding="utf-8")) if info_path else {}
    body = {
        "video_id": entry.video_id,
        "channel": entry.channel,
        "channel_id": entry.channel_id,
        "title": entry.title,
        "url": entry.url,
        "published": entry.published,
        "ingested_at": datetime.now(timezone.utc).isoformat(),
        "placement_scores": placement_scores(f"{entry.title}\n{transcript_text}", channel_bias),
        "description": info.get("description", ""),
        "transcript_text": transcript_text,
    }
    path = output_dir / f"{entry.video_id}.intake.json"
    path.write_text(json.dumps(body, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Pull new YouTube RSS entries and transcript artifacts for JARVIS review.")
    parser.add_argument("--limit-per-channel", type=int, default=2)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--state-path", type=Path, default=DEFAULT_STATE_PATH)
    parser.add_argument("--include-seen", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    state = load_state(args.state_path)
    seen = set(state.get("seen_video_ids", []))
    written: list[str] = []

    for channel in CHANNELS:
        entries = fetch_feed(channel)[: max(1, args.limit_per_channel)]
        bias = list(channel.get("placement_bias", []))
        for entry in entries:
            if entry.video_id in seen and not args.include_seen:
                continue
            if args.dry_run:
                print(f"{entry.channel}: {entry.title} ({entry.url})")
                continue
            transcript_path, info_path = run_yt_dlp(entry, args.output_dir)
            intake_path = write_intake(entry, args.output_dir, transcript_path, info_path, bias)
            written.append(str(intake_path.relative_to(REPO_ROOT)))
            seen.add(entry.video_id)

    if not args.dry_run:
        state["seen_video_ids"] = sorted(seen)
        save_state(args.state_path, state)
    print(json.dumps({"written": written}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
