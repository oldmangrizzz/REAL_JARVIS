# JARVIS VibeVoice TTS service

Bearer-protected FastAPI service that wraps the
[community VibeVoice fork](https://github.com/vibevoice-community/VibeVoice)
(MIT license) and runs on a GCP T4 spot instance. Speaks to
`HTTPTTSBackend` in JarvisCore via a single endpoint.

## Why this exists
The 8 GB Mac swap-thrashes on every cloning-quality TTS model published
to date. VibeVoice 1.5B at bf16 needs ~6 GB of GPU VRAM and 4–8 GB of
host RAM working set. A T4 has 16 GB VRAM and clears that with
headroom; on spot pricing it's ~$0.11/hr — under $30/mo even at heavy
use, well inside the $1k/yr GCP Dev Pro credit.

## Endpoints
- `POST /tts/synthesize` — bearer required. JSON body:
  ```
  {
    "text": "...",
    "reference_audio_b64": "<base64 wav bytes>",
    "cfg_scale": 1.3,
    "ddpm_steps": 10,
    "seed": null,
    "speaker_label": "Jarvis"
  }
  ```
  Returns `audio/wav` raw bytes by default, or JSON
  `{"audio_b64": "..."}` if `VIBEVOICE_RETURN_FORMAT=json`.
  Response headers: `X-Audio-Duration-Seconds`, `X-Generation-Seconds`,
  `X-RTF`, `X-Sample-Rate`.
- `GET /healthz` — liveness, no auth.
- `GET /readyz` — model load state, no auth.
- `GET /stats` — bearer required.

`reference_text`, `temperature`, `top_p`, `max_new_tokens` are accepted
but ignored — VibeVoice uses only the audio sample.

## Env vars
| Name | Default | Notes |
|---|---|---|
| `VIBEVOICE_BEARER` | _required_ | Service refuses to start without it. |
| `VIBEVOICE_MODEL_PATH` | `vibevoice/VibeVoice-1.5B` | HF repo or local path. |
| `VIBEVOICE_DEVICE` | auto (cuda/mps/cpu) | |
| `VIBEVOICE_IDLE_SECONDS` | `1800` | Process exits after this much idle so the spot VM can deallocate. Set to `0` to disable. |
| `VIBEVOICE_RETURN_FORMAT` | `wav` | `wav` or `json`. |
| `VIBEVOICE_PRELOAD` | `1` | Preload the model on startup. |

## Local dev (CPU smoke only — no cloning quality)
```
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
pip install "git+https://github.com/vibevoice-community/VibeVoice.git@main"
VIBEVOICE_BEARER=dev VIBEVOICE_DEVICE=cpu uvicorn app:app --port 8000
```

## Build + push the image
```
export GCP_PROJECT_ID=your-project
export GCP_REGION=us-central1
docker build -t "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/vibevoice-tts:latest" .
docker push "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/jarvis/vibevoice-tts:latest"
```

## Bring up / tear down
```
export GCP_PROJECT_ID=your-project
./deploy/gcp-up.sh                    # creates spot T4, runs container
./deploy/gcp-tunnel.sh                # localhost:8000 <-> instance:8000
./deploy/gcp-down.sh                  # delete the instance when done
```

## Wire to JARVIS
After the tunnel is open:
```
set -x JARVIS_TTS_URL http://localhost:8000/tts/synthesize
set -x JARVIS_TTS_BEARER (gcloud secrets versions access latest --secret=jarvis-vibevoice-bearer)
set -x JARVIS_TTS_IDENTIFIER vibevoice/VibeVoice-1.5B
set -x JARVIS_TTS_VOICE_LABEL vibevoice-1.5b-clone
set -x JARVIS_TTS_SAMPLE_RATE 24000
```
JarvisCore picks `HTTPTTSBackend` whenever both `JARVIS_TTS_URL` and
`JARVIS_TTS_BEARER` are set. Backend identifier change auto-voids any
prior voice approval — re-audition before flipping the gate.

## Cost discipline
- Spot price for `n1-standard-4` + 1×T4 in `us-central1`: ~$0.11/hr
  compute + ~$0.11/hr GPU = ~$0.22/hr.
- Idle watchdog exits the process after 30 min idle. Pair with a
  managed instance group (size 0 default) if you want true scale-to-
  zero; otherwise just run `gcp-down.sh` when you're done.
- Set a $30/mo budget alarm in the GCP console as a hard tripwire.
