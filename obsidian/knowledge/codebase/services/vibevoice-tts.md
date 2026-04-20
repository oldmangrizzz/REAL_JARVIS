# vibevoice-tts

**Path:** `services/vibevoice-tts/`
**Files:**
- `app.py` — FastAPI service.
- `synthesizer.py` — `VibeVoiceSynthesizer` wrapper.
- `Dockerfile`, `requirements.txt`, `deploy/`, `README.md`.

## Purpose
Remote **VibeVoice** TTS backend hosted on a GCP spot instance.
JARVIS's [[codebase/modules/Voice]] module calls this when local
synthesis is insufficient or unavailable.

## Endpoints
- `POST /tts/synthesize` — bearer-protected, accepts
  `{ text, reference_audio_b64, reference_text?, temperature? }`.
- `GET /healthz` — liveness.
- `GET /readyz` — readiness.
- `GET /stats` — counters.

## Security
- Bearer token via `VIBEVOICE_BEARER` env; service refuses to start
  without it.
- Idle-shutdown thread exits the process after `VIBEVOICE_IDLE_SECONDS`
  so the GCP spot VM can deallocate (cost control).
- Output is **not** played back unless the
  [[concepts/Voice-Approval-Gate|Voice Approval Gate]] ratifies it on
  the Mac.

## Invariants
- `reference_text` is accepted but **ignored** — VibeVoice uses audio only.
- Text length capped at 8192 chars.

## Related
- [[codebase/modules/Voice]]
- [[concepts/Voice-Approval-Gate]]
- [[reference/DEPLOYMENT]]
