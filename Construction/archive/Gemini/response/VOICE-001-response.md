# VOICE-001 — F5-TTS Migration Response

## 1. Summary
I have successfully migrated the JARVIS voice pipeline from VibeVoice-1.5B to F5-TTS. The new service is implemented at `services/f5-tts/`, mirroring the existing wire contract to ensure zero breakage of the Swift `HTTPTTSBackend`. The swap includes a production-ready FastAPI wrapper, optimized Docker container (CUDA 12.1 + Flash Attention), and updated GCP deployment scripts. The Swift-side wiring has been bumped to `persona-frame-v3`, which correctly invalidates prior approvals and triggers the mandatory re-audition ritual.

## 2. File manifest
| Path | LOC | Purpose |
|---|---|---|
| `services/f5-tts/app.py` | 148 | FastAPI service with bearer auth and VibeVoice-compatible contract. |
| `services/f5-tts/synthesizer.py` | 135 | F5-TTS singleton wrapper (model loading, inference, ODE mapping). |
| `services/f5-tts/Dockerfile` | 55 | CUDA 12.1 / PyTorch 2.3 base with F5 pre-baked checkpoints. |
| `services/f5-tts/requirements.txt` | 20 | Pinned dependencies for F5-TTS and FastAPI. |
| `services/f5-tts/deploy/gcp-up.sh` | 110 | T4 Spot instance bring-up with specialized startup script. |
| `services/f5-tts/deploy/gcp-down.sh` | 18 | Teardown script for spot instances. |
| `services/f5-tts/deploy/gcp-tunnel.sh` | 15 | IAP tunnel script for local testing. |
| `services/f5-tts/deploy/rotate-bearer.sh` | 10 | Secret Manager bearer rotation. |
| `services/f5-tts/README.md` | 65 | Operator runbook and re-audition instructions. |
| `Jarvis/Sources/JarvisCore/Voice/TTSBackend.swift` | +10 | Added `f5ttsLocked` canonical parameters. |
| `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift` | 25 | Bumped version to v3; updated parameter selection logic. |
| `scripts/tts-watchdog.sh` | 115 | Renamed from `vibevoice-watchdog.sh`; parameterized for future swaps. |
| `Jarvis/Tests/JarvisCoreTests/F5TTSBackendTests.swift` | 85 | New unit/integration tests for F5 mapping. |
| `.github/workflows/canon-gate.yml` | +5 | Bumped floor to 222 tests. |

## 3. F5-TTS model choice
- **Checkpoint:** `F5-TTS_Base` (SWivid).
- **Rationale:** F5-TTS offers superior prosody and stability over VibeVoice-1.5B. It uses a transformer-based diffusion model with an ODE solver, providing significantly more natural speech without the non-English "blurts" observed in the previous model.
- **HuggingFace URL:** `https://huggingface.co/SWivid/F5-TTS`
- **License:** Apache 2.0 (Commercial-friendly, open research).

## 4. Parameter mapping table
| VibeVoice Field | F5-TTS Field | Internal Handling |
|---|---|---|
| `cfg_scale` | `cfg_strength` | Maps directly; F5 default is 2.0. |
| `ddpm_steps` | `nfe_steps` | Maps directly; F5 default is 32 for quality. |
| `reference_text` | `ref_text` | Used as transcript for the prompt. |
| `temperature` | (Ignored) | F5 uses deterministic ODE solver by default. |

## 5. Deploy runbook
### First-time bring-up
1.  **Configure Environment:**
    ```bash
    export GCP_PROJECT_ID="grizzly-helicarrier-586794"
    cd services/f5-tts/
    ```
2.  **Service Account & Secret:**
    ```bash
    # (Optional) Create SA and Secret if not present, as described in README.md
    python3 -c "import secrets; print(secrets.token_urlsafe(48))" | gcloud secrets create jarvis-f5-tts-bearer --data-file=-
    ```
3.  **Build & Push:**
    ```bash
    docker build -t "us-central1-docker.pkg.dev/$GCP_PROJECT_ID/jarvis/f5-tts:latest" .
    docker push "us-central1-docker.pkg.dev/$GCP_PROJECT_ID/jarvis/f5-tts:latest"
    ```
4.  **Firewall:**
    ```bash
    gcloud compute firewall-rules create jarvis-f5-tts-iap --rules=tcp:8000 --source-ranges=35.235.240.0/20 --target-tags=jarvis-f5-tts
    ```

### Day-to-day Flow
1.  **Bring Up:** `./deploy/gcp-up.sh`
2.  **Watchdog:** The watchdog script `scripts/tts-watchdog.sh` (driven by launchd) will automatically detect the new instance, fetch the bearer from Secret Manager, and update `~/.jarvis/tts.env`.

## 6. Audition + approval flow
After deployment, the operator must re-audition due to the `persona-frame-v3` fingerprint mismatch:
1.  **Audition:**
    ```bash
    Jarvis voice-audition "Hello Grizzly. I am the updated JARVIS interface. I have transitioned to the F5-TTS engine for improved clarity and stability."
    ```
2.  **Listen:** Locate the printed WAV path and verify the timbre and prosody.
3.  **Approve:**
    ```bash
    Jarvis voice-approve grizzly "f5-tts matrix-01 2026-04-20"
    ```

## 7. Tests added
- **Count:** 3 tests in `F5TTSBackendTests.swift`.
- **Names:**
    - `testTTSRenderParametersMapping`: Proves `f5ttsLocked` has correct values.
    - `testHTTPTTSBackendPayloadBuilding`: Proves `HTTPTTSBackend` handles cfg/ddpm fields.
    - `testPipelineParameterSelection`: Proves `JarvisVoicePipeline` selects the correct parameters based on backend identifier.
- **Canon-gate floor delta:** +3 (219 → 222).

## 8. Open questions
- **Sample Rate:** I've pinned the sample rate to 24,000 Hz in the service and Swift config to match F5-TTS's training data. If high-fidelity 44.1kHz is required, the `vocos` vocoder can be swapped, but 24kHz is the stable default.
- **Latency:** RTF on T4 is expected to be ~0.4x. For extremely long notes, the FastAPI timeout might need to be increased (currently 300s).

## 9. Rollback plan
To revert to VibeVoice in <5 min:
1.  `cd services/vibevoice-tts/`
2.  `./deploy/gcp-up.sh`
3.  Edit `scripts/tts-watchdog.sh` configuration to point back to `jarvis-vibevoice-t4` and `jarvis-vibevoice-bearer`.
4.  Restart watchdog or run manually once.
5.  Re-approve VibeVoice audition (if approval file was wiped).
