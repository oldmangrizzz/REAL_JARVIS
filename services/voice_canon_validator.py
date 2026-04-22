#!/usr/bin/env python3
"""voice_canon_validator.py

Guardian service for Jarvis's voice CANON LAW (PRINCIPLES.md §"CANON LAW — VOICE",
locked 2026-04-21). Rejects any rendering/approval request that is not:

  - speaker_label == "Jarvis" (or an approved Jarvis alias), AND
  - reference clip = voice-samples/0299_TINCANS_CANONICAL.wav (SHA-256 match), AND
  - backend = xtts-v2 (Coqui), AND
  - TTS endpoint = Delta tunnel (xtts.grizzlymedicine.icu or tts.grizzlymedicine.icu
    or 127.0.0.1:8787 via local port-forward), AND
  - voice token (if persona_framing_version provided) matches the active canon
    framing version.

Supports two modes:
  1. CLI validator:   python3 voice_canon_validator.py validate --speaker Jarvis \
                            --ref voice-samples/0299_TINCANS_CANONICAL.wav \
                            --backend xtts-v2 --endpoint xtts.grizzlymedicine.icu
     Exit 0 on pass, non-zero on canon violation. Prints violation reasons.

  2. FastAPI sidecar: uvicorn voice_canon_validator:app --host 127.0.0.1 --port 8799
     POST /validate  { speaker_label, reference_path, backend, endpoint,
                       persona_framing_version? } -> { ok, violations[] }

The validator is intentionally deterministic and offline-capable. It reads
canon from disk (PRINCIPLES.md + the canonical reference wav fingerprint) so a
tampered Letta block cannot weaken it.

Canon sources of truth:
  - /Users/grizzmed/REAL_JARVIS/PRINCIPLES.md §"CANON LAW — VOICE"
  - /Users/grizzmed/REAL_JARVIS/voice-samples/0299_TINCANS_CANONICAL.wav
  - /Users/grizzmed/REAL_JARVIS/Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift
    (personaFramingVersion string)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(
    os.environ.get("JARVIS_REPO_ROOT", "/Users/grizzmed/REAL_JARVIS")
).resolve()

CANON_REF_REL = "voice-samples/0299_TINCANS_CANONICAL.wav"
CANON_REF_SHA256 = "177689466c87fb93ff3b4760c05eae6459cadea25f15b5a8fa83f53189500f03"

# Approved speaker labels — Jarvis only. Case-insensitive match.
APPROVED_SPEAKER_LABELS = {"jarvis", "j.a.r.v.i.s", "jarvis-canonical"}

# Approved backends.
APPROVED_BACKENDS = {"xtts-v2", "xtts_v2", "xtts", "coqui-xtts-v2"}

# Approved endpoints (hosts) for the Delta tunnel.
APPROVED_ENDPOINTS = {
    "xtts.grizzlymedicine.icu",
    "tts.grizzlymedicine.icu",
    "127.0.0.1",
    "localhost",
    "delta.local",
    os.environ.get("JARVIS_DELTA_HOST", "delta.grizzlymedicine.icu"),
}

# Canon framing version string — sourced from VoiceSynthesis.swift at runtime.
VOICE_SWIFT = (
    REPO_ROOT
    / "Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift"
)
PERSONA_FRAMING_RE = re.compile(
    r'personaFramingVersion\s*[:=]\s*"([^"]+)"'
)


def canon_framing_version() -> Optional[str]:
    if not VOICE_SWIFT.exists():
        return None
    try:
        text = VOICE_SWIFT.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    m = PERSONA_FRAMING_RE.search(text)
    return m.group(1) if m else None


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


@dataclass
class ValidationRequest:
    speaker_label: str = ""
    reference_path: str = ""
    backend: str = ""
    endpoint: str = ""
    persona_framing_version: Optional[str] = None


@dataclass
class ValidationResult:
    ok: bool = True
    violations: list[str] = field(default_factory=list)
    canon: dict = field(default_factory=dict)

    def fail(self, reason: str) -> None:
        self.ok = False
        self.violations.append(reason)


def _host_of(endpoint: str) -> str:
    e = (endpoint or "").strip().lower()
    for prefix in ("https://", "http://", "wss://", "ws://"):
        if e.startswith(prefix):
            e = e[len(prefix):]
            break
    e = e.split("/", 1)[0]
    e = e.split(":", 1)[0]
    return e


def validate(req: ValidationRequest) -> ValidationResult:
    result = ValidationResult()
    canon = {
        "approved_speaker_labels": sorted(APPROVED_SPEAKER_LABELS),
        "approved_backends": sorted(APPROVED_BACKENDS),
        "approved_endpoints": sorted(APPROVED_ENDPOINTS),
        "canon_reference_path": CANON_REF_REL,
        "canon_reference_sha256": CANON_REF_SHA256,
        "canon_framing_version": canon_framing_version(),
    }
    result.canon = canon

    # Speaker label
    sl = (req.speaker_label or "").strip().lower()
    if not sl:
        result.fail("speaker_label missing")
    elif sl not in APPROVED_SPEAKER_LABELS:
        result.fail(
            f"speaker_label '{req.speaker_label}' not in approved set "
            f"{sorted(APPROVED_SPEAKER_LABELS)} (CANON LAW — VOICE)"
        )

    # Backend
    be = (req.backend or "").strip().lower()
    if not be:
        result.fail("backend missing")
    elif be not in APPROVED_BACKENDS:
        result.fail(
            f"backend '{req.backend}' not in approved set "
            f"{sorted(APPROVED_BACKENDS)} — XTTS v2 only"
        )

    # Endpoint
    host = _host_of(req.endpoint)
    if not host:
        result.fail("endpoint missing")
    elif host not in APPROVED_ENDPOINTS:
        result.fail(
            f"endpoint host '{host}' not in approved Delta tunnel set "
            f"{sorted(APPROVED_ENDPOINTS)}"
        )

    # Reference clip fingerprint
    if not req.reference_path:
        result.fail("reference_path missing")
    else:
        rpath = Path(req.reference_path)
        if not rpath.is_absolute():
            rpath = (REPO_ROOT / req.reference_path).resolve()
        if not rpath.exists():
            result.fail(
                f"reference clip '{req.reference_path}' does not exist at {rpath}"
            )
        else:
            actual = sha256_of(rpath)
            if actual != CANON_REF_SHA256:
                result.fail(
                    f"reference clip SHA-256 mismatch. "
                    f"expected={CANON_REF_SHA256} actual={actual} "
                    f"(canon = voice-samples/0299_TINCANS_CANONICAL.wav)"
                )

    # Persona framing version (optional; if provided must match disk canon)
    if req.persona_framing_version is not None:
        disk = canon["canon_framing_version"]
        if disk is None:
            result.fail(
                "cannot verify persona_framing_version — VoiceSynthesis.swift "
                "not readable"
            )
        elif req.persona_framing_version != disk:
            result.fail(
                f"persona_framing_version drift: caller='"
                f"{req.persona_framing_version}' disk='{disk}' — rotate"
            )

    return result


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cli_validate(args: argparse.Namespace) -> int:
    req = ValidationRequest(
        speaker_label=args.speaker or "",
        reference_path=args.ref or CANON_REF_REL,
        backend=args.backend or "",
        endpoint=args.endpoint or "",
        persona_framing_version=args.framing,
    )
    result = validate(req)
    print(json.dumps(asdict(result), indent=2))
    return 0 if result.ok else 1


def _cli_fingerprint(_args: argparse.Namespace) -> int:
    p = (REPO_ROOT / CANON_REF_REL)
    if not p.exists():
        print(f"ERROR: canon reference missing: {p}", file=sys.stderr)
        return 2
    actual = sha256_of(p)
    ok = actual == CANON_REF_SHA256
    print(json.dumps({
        "path": str(p),
        "expected_sha256": CANON_REF_SHA256,
        "actual_sha256": actual,
        "ok": ok,
    }, indent=2))
    return 0 if ok else 1


def main(argv: Optional[list[str]] = None) -> int:
    p = argparse.ArgumentParser(
        description="Jarvis voice CANON LAW validator (XTTS v2 / Jarvis / Delta)."
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pv = sub.add_parser("validate", help="Validate a voice render request.")
    pv.add_argument("--speaker", help="speaker_label (must be 'Jarvis')")
    pv.add_argument("--ref", help="reference clip path (relative to repo or absolute)")
    pv.add_argument("--backend", help="tts backend (must be xtts-v2)")
    pv.add_argument("--endpoint", help="tts endpoint host/url")
    pv.add_argument("--framing", help="optional persona_framing_version to verify")
    pv.set_defaults(func=_cli_validate)

    pf = sub.add_parser("fingerprint", help="Verify canonical ref-wav fingerprint.")
    pf.set_defaults(func=_cli_fingerprint)

    args = p.parse_args(argv)
    return args.func(args)


# ---------------------------------------------------------------------------
# Optional FastAPI sidecar (only if fastapi is installed)
# ---------------------------------------------------------------------------

try:
    from fastapi import FastAPI, HTTPException
    from pydantic import BaseModel

    class _ReqModel(BaseModel):
        speaker_label: str
        reference_path: str = CANON_REF_REL
        backend: str
        endpoint: str
        persona_framing_version: Optional[str] = None

    app = FastAPI(
        title="jarvis-voice-canon-validator",
        version="1.0.0",
        description="Guardian sidecar enforcing CANON LAW — VOICE (2026-04-21).",
    )

    @app.get("/health")
    def _health() -> dict:
        return {
            "ok": True,
            "canon_ref": CANON_REF_REL,
            "canon_framing_version": canon_framing_version(),
        }

    @app.post("/validate")
    def _validate(req: _ReqModel) -> dict:
        r = validate(ValidationRequest(**req.model_dump()))
        if not r.ok:
            raise HTTPException(status_code=422, detail=asdict(r))
        return asdict(r)

except ImportError:  # fastapi not installed — CLI still works
    app = None  # type: ignore[assignment]


if __name__ == "__main__":
    sys.exit(main())
