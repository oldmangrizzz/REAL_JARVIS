# VOICE-001 — Swap VibeVoice-1.5B → F5-TTS

**Issued to:** DeepSeek v3.1 (Ollama cloud)
**Track:** Voice pipeline
**Canon sensitivity:** HIGH — touches `VoiceApprovalGate`, `SOUL_ANCHOR`, operator-only approval ritual.
**Priority:** P0. Current VibeVoice output is unusable (slow, drift, out-of-language blurts). Operator has rejected VibeVoice.

---

## Why

VibeVoice-1.5B on a T4 at `34.66.179.91:8000/tts/synthesize`:

- ~13 s render latency per ~1200-char chunk (unusable for live speech).
- Produces non-English phonemes and identity drift even with an approved reference.
- Model quality floor is too low for the medical-safety persona bond.

F5-TTS (SWivid):

- Sub-realtime on T4 (typ. 0.3–0.5× realtime) per public benchmarks.
- Strong zero-shot voice cloning from ~10 s reference + transcript.
- Natural prosody; no persona drift in short-form outputs.
- Active upstream, well-documented FastAPI/gradio server.

## Scope

### In

1. New FastAPI service at `services/f5-tts/` mirroring `services/vibevoice-tts/` layout:
   - `app.py` — FastAPI app with **identical wire contract** to VibeVoice service so `HTTPTTSBackend` doesn't change.
   - `synthesizer.py` — F5-TTS wrapper (load model once, render WAV bytes).
   - `Dockerfile` — CUDA 12.1 base, Python 3.10, F5-TTS from upstream git.
   - `requirements.txt`.
   - `README.md` — deploy + operator runbook.
2. Deploy scripts at `services/f5-tts/deploy/`:
   - `gcp-up.sh`, `gcp-down.sh`, `gcp-tunnel.sh`, `rotate-bearer.sh` (copy the VibeVoice ones; edit instance name, image tag, secret name).
   - New VM: `jarvis-f5-tts-t4`, same zone `us-central1-a`, same `n1-standard-4 + 1x T4` spot.
   - New Secret Manager secret: `jarvis-f5-tts-bearer`.
   - New Artifact Registry image: `jarvis/f5-tts:latest`.
3. Swift wiring:
   - Bump `VoiceSynthesis.personaFramingVersion` from `"persona-frame-v2-vibevoice-cfg2.1-ddpm10"` to `"persona-frame-v3-f5tts-cfg2.0-nfe32"` (or current F5 defaults — document what you pick).
   - Default `TTSRenderParameters` for F5: `cfg_scale` maps to F5's `cfg_strength` (default 2.0), add `nfe_steps` (default 32), drop `ddpm_steps`. Keep the struct backward-compatible — **do not break existing tests**.
   - Update `HTTPTTSBackendFactory.fromEnvironment()` only if the env contract changes (it shouldn't — keep the same 5 `JARVIS_TTS_*` vars).
4. Watchdog update:
   - `scripts/vibevoice-watchdog.sh` → rename `scripts/tts-watchdog.sh`.
   - Parameterize `INSTANCE`, `SECRET`, `IDENTIFIER`, `VOICE_LABEL` via top-of-file constants so future swaps don't require a rewrite.
   - LaunchAgent plist label stays `com.grizz.jarvis.tts.watchdog` (rename from `vibevoice.watchdog`; unload + reload).
5. Approval ritual:
   - Wipe `.jarvis/voice/approval.json` (it's tied to VibeVoice fingerprint; new model = new fingerprint = needs re-approval by design, per `VoiceApprovalGate`).
   - Do NOT touch `VoiceApprovalGate` logic. The whole point is that model swap invalidates approval. Operator must re-audition.
   - Document the re-audition command sequence in `services/f5-tts/README.md`.
6. Tests:
   - Unit test for the F5 parameter mapping (`TTSRenderParameters` → server JSON).
   - Integration test that verifies `HTTPTTSBackend` hits `/tts/synthesize` with the new payload shape (mocked URLSession).
   - Canon-gate floor stays at whatever it is today; bump it per your test count delta.

### Out

- **Do NOT** remove VibeVoice code/service files in this task. Leave `services/vibevoice-tts/` intact so we can fall back. A future ticket will delete it after F5 is proven.
- **Do NOT** modify `VoiceApprovalGate.swift` logic.
- **Do NOT** change `Principal`, `CompanionCapabilityPolicy`, `OSINTSourceRegistry`, canon-gate workflow.
- No LiveKit streaming. That's a separate future ticket.

## Wire contract (MUST preserve)

`POST /tts/synthesize` with bearer auth, JSON body:

```json
{
  "text": "string",
  "reference_audio_b64": "string (base64 WAV)",
  "reference_text": "string",
  "temperature": 0.8,
  "top_p": 0.9,
  "cfg_scale": 2.0,
  "ddpm_steps": 32,
  "max_new_tokens": null
}
```

Response: `audio/wav` bytes (16-bit PCM, server decides sample rate, advertised via `JARVIS_TTS_SAMPLE_RATE` env on the client).

**Server MUST accept and ignore fields it doesn't use** (backward-compat). If F5 ignores `ddpm_steps`, map it internally to `nfe_steps` or discard silently. Do NOT 400 on unknown fields.

Also preserve: `GET /healthz`, `GET /readyz`, `GET /stats`, idle-shutdown thread behavior (env `F5_IDLE_SECONDS`).

## Deliverables (response shape)

Write `DeepSeek/response/VOICE-001-response.md` with these sections, in order:

1. **Summary** — one paragraph of what landed and how to prove it works.
2. **File manifest** — every path you created or modified, with LOC and purpose.
3. **F5-TTS model choice** — which checkpoint (`F5-TTS_Base` / `F5-TTS_v1_Base` / other), why, and the HuggingFace URL. Include licence check.
4. **Parameter mapping table** — VibeVoice fields → F5-TTS fields → server-internal handling.
5. **Deploy runbook** — exact commands to:
   - First-time bring-up (create Artifact Registry repo, build image, push, create secret, create firewall rule, etc.)
   - Day-to-day `gcp-up.sh` flow
   - How the watchdog picks up the new instance
6. **Audition + approval flow** — commands the operator runs after deploy:
   - `Jarvis voice-audition "The quick brown fox..."`
   - Listen to the WAV
   - `Jarvis voice-approve grizzly "f5-tts matrix-01 2026-04-20"`
7. **Tests added** — count, names, what they prove. Include canon-gate floor delta.
8. **Open questions** — anything you had to assume. Flag canon risks.
9. **Rollback plan** — exact commands to revert to VibeVoice in <5 min if F5 is worse (keep `services/vibevoice-tts/deploy/gcp-up.sh` path alive).

## Canon guardrails (check before pushing)

- `VoiceApprovalGate` unchanged (diff should be zero lines).
- `SOUL_ANCHOR.md` unchanged (diff should be zero lines).
- `canon-gate.yml` test floor bumped if and only if your new tests increased the count; never decreased.
- `.gitignore` still ignores `.jarvis/voice/approval.json` (it's operator-local, NOT in repo).
- No secrets committed. Bearer stays in Secret Manager. `.jarvis/voice-bridge.env` stays gitignored.
- No hardcoded IPs. Watchdog reads them from `gcloud compute instances describe`.

## Reference material (read before coding)

- `services/vibevoice-tts/app.py` — current server contract to mirror.
- `services/vibevoice-tts/synthesizer.py` — pattern for singleton + idle-shutdown.
- `services/vibevoice-tts/deploy/gcp-up.sh` — GCP deploy pattern.
- `Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` — Swift client, do not break it.
- `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift:152` — where `personaFramingVersion` lives.
- `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift` — read, do not modify.
- `scripts/vibevoice-watchdog.sh` — watchdog to port over.
- `~/Library/LaunchAgents/com.grizz.jarvis.vibevoice.watchdog.plist` — template for the renamed LaunchAgent.
- `SOUL_ANCHOR.md` — why the voice gate exists, why you cannot circumvent it.

## Success criteria

1. `curl -H "Authorization: Bearer $F5_BEARER" -X POST http://<f5-ip>:8000/tts/synthesize -d '{...}' -o out.wav` returns a valid WAV in <5 s for a 1200-char input.
2. `Jarvis voice-audition "..."` produces a clip that sounds coherent, in-English, with operator's reference timbre preserved.
3. After `Jarvis voice-approve grizzly "..."`, `/speak` through the Obsidian bridge reads a full note end-to-end with no drift, no overlaps, no blurting.
4. Watchdog survives a spot-preemption cycle: kill the F5 VM, wait 60 s, confirm it comes back, `~/.jarvis/vibevoice.env` (or renamed equivalent) picks up the new IP, bridge respawns.
5. All pre-existing tests still pass. New tests added for F5 payload mapping.

---

**Operator state:** exhausted, autistic-rage post-incident. Do not ask clarifying questions mid-build — make reasonable defaults, document them in "Open Questions", deliver a complete runnable swap. If something is genuinely ambiguous, pick the choice that preserves canon and ship.
