"""
JARVIS VibeVoice TTS service.
Single bearer-protected POST /tts/synthesize endpoint.
GET /healthz, GET /readyz, GET /stats.
Idle-shutdown thread exits the process if no requests arrive within
VIBEVOICE_IDLE_SECONDS so the GCP spot instance can deallocate.
"""
from __future__ import annotations

import base64
import os
import signal
import sys
import threading
import time
from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from synthesizer import VibeVoiceSynthesizer

BEARER_TOKEN = os.environ.get("VIBEVOICE_BEARER")
if not BEARER_TOKEN:
    print("FATAL: VIBEVOICE_BEARER env var not set; refusing to start.", file=sys.stderr)
    sys.exit(2)

IDLE_SECONDS = int(os.environ.get("VIBEVOICE_IDLE_SECONDS", "1800"))
RETURN_FORMAT = os.environ.get("VIBEVOICE_RETURN_FORMAT", "wav").lower()  # "wav" | "json"

app = FastAPI(title="JARVIS VibeVoice TTS", version="1.0.0")
_started_at = time.time()


class SynthesizeRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=8192)
    reference_audio_b64: str = Field(..., min_length=1)
    reference_text: Optional[str] = Field(default=None, description="Ignored — VibeVoice uses audio only.")
    temperature: Optional[float] = Field(default=None, description="Unused (kept for backend-protocol parity).")
    top_p: Optional[float] = Field(default=None, description="Unused (kept for backend-protocol parity).")
    cfg_scale: float = Field(default=1.3, ge=0.5, le=4.0)
    ddpm_steps: int = Field(default=10, ge=1, le=50)
    seed: Optional[int] = None
    speaker_label: str = Field(default="Jarvis", min_length=1, max_length=64)
    max_new_tokens: Optional[int] = None  # accepted, ignored


def _require_bearer(authorization: Optional[str]) -> None:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token.")
    presented = authorization.split(" ", 1)[1].strip()
    # constant-time-ish compare
    a = presented.encode("utf-8")
    b = BEARER_TOKEN.encode("utf-8")
    if len(a) != len(b):
        raise HTTPException(status_code=401, detail="Invalid bearer token.")
    diff = 0
    for x, y in zip(a, b):
        diff |= x ^ y
    if diff != 0:
        raise HTTPException(status_code=401, detail="Invalid bearer token.")


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "uptime_s": int(time.time() - _started_at)}


@app.get("/readyz")
def readyz() -> dict:
    s = VibeVoiceSynthesizer.shared()
    return {
        "ok": s._loaded,
        "model_path": s.model_path,
        "device": s.device,
        "sample_rate": s.sample_rate,
        "last_use_ts": int(s.last_use_ts),
        "idle_seconds": int(time.time() - s.last_use_ts),
        "idle_shutdown_after": IDLE_SECONDS,
    }


@app.get("/stats")
def stats(authorization: Optional[str] = Header(default=None)) -> dict:
    _require_bearer(authorization)
    s = VibeVoiceSynthesizer.shared()
    return {
        "loaded": s._loaded,
        "model_path": s.model_path,
        "device": s.device,
        "sample_rate": s.sample_rate,
        "uptime_s": int(time.time() - _started_at),
        "idle_s": int(time.time() - s.last_use_ts),
    }


@app.post("/tts/synthesize")
def synthesize(req: SynthesizeRequest, request: Request, authorization: Optional[str] = Header(default=None)):
    _require_bearer(authorization)

    try:
        ref_bytes = base64.b64decode(req.reference_audio_b64, validate=True)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"reference_audio_b64 invalid base64: {exc}")
    if not ref_bytes:
        raise HTTPException(status_code=400, detail="reference_audio_b64 was empty after decode.")

    s = VibeVoiceSynthesizer.shared()
    try:
        result = s.synthesize(
            text=req.text,
            reference_audio_bytes=ref_bytes,
            cfg_scale=req.cfg_scale,
            ddpm_steps=req.ddpm_steps,
            seed=req.seed,
            speaker_label=req.speaker_label,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"synthesis failure: {type(exc).__name__}: {exc}")

    headers = {
        "X-Audio-Duration-Seconds": f"{result.audio_duration_seconds:.3f}",
        "X-Generation-Seconds": f"{result.generation_time_seconds:.3f}",
        "X-RTF": f"{result.rtf:.3f}",
        "X-Sample-Rate": str(result.sample_rate),
    }
    if RETURN_FORMAT == "json":
        return JSONResponse(
            content={
                "audio_b64": base64.b64encode(result.wav_bytes).decode("ascii"),
                "sample_rate": result.sample_rate,
                "audio_duration_seconds": result.audio_duration_seconds,
                "generation_time_seconds": result.generation_time_seconds,
                "rtf": result.rtf,
            },
            headers=headers,
        )
    return Response(content=result.wav_bytes, media_type="audio/wav", headers=headers)


def _idle_watchdog() -> None:
    """Exit the process if no synthesis happens for IDLE_SECONDS so the
    spot instance auto-shutdown / instance-group scale-to-zero policy
    can deallocate the T4."""
    if IDLE_SECONDS <= 0:
        return
    while True:
        time.sleep(60)
        s = VibeVoiceSynthesizer.shared()
        if not s._loaded:
            continue
        idle = time.time() - s.last_use_ts
        if idle >= IDLE_SECONDS:
            print(f"[idle-watchdog] idle for {idle:.0f}s >= {IDLE_SECONDS}s, exiting.", flush=True)
            os.kill(os.getpid(), signal.SIGTERM)
            return


@app.on_event("startup")
def _on_startup() -> None:
    threading.Thread(target=_idle_watchdog, daemon=True).start()
    if os.environ.get("VIBEVOICE_PRELOAD", "1") == "1":
        threading.Thread(target=lambda: VibeVoiceSynthesizer.shared().ensure_loaded(), daemon=True).start()
