# MK2-EPIC-05 — Voice Pipeline Unification

**Lane:** Gemini (voice)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** `VOICE-001-f5-tts-swap` (in flight), `VOICE-002-realtime-speech-to-speech` (in flight), `AMBIENT-001-watch-as-audio-gateway` (pending)
**Priority:** P0
**Canon sensitivity:** HIGH — touches `VoiceApprovalGate`, voice identity, Soul Anchor

---

## Why

Three voice epics are in flight as separate Forge tasks:
1. **VOICE-001** — VibeVoice → F5-TTS swap (output).
2. **VOICE-002** — realtime speech-to-speech loop (bidirectional).
3. **AMBIENT-001** — Watch as audio gateway (input).

They will ship independently but nothing **unifies** them. Operator needs one pipeline: Watch/Phone/Mac mic → VAD → STT (local `SFSpeechRecognizer` or Whisper.cpp) → `VoiceApprovalGate` approval → `IntentParser` → `DisplayCommandExecutor` OR `VoicePipeline.render(response)` → F5-TTS → speaker output. With a single **failover matrix** if any stage is down.

## Scope

### In

1. **`VoicePipelineOrchestrator`** at `Jarvis/Sources/JarvisCore/Voice/VoicePipelineOrchestrator.swift`:
   - Single actor that owns the voice loop.
   - Inputs: raw PCM buffer or tunnel-relayed audio (from Watch gateway).
   - Stages: VAD → STT → gate → intent → action → response synth → playback.
   - Emits telemetry at each stage: `voice.stage.<name>.{start,ok,failed}`.

2. **Failover matrix:**
   - STT: Local SFSpeechRecognizer → Whisper.cpp local → Whisper on GCP (only if voice gate re-approval for external model) → `voice.stt.unavailable` fail.
   - TTS: F5-TTS primary → FishAudio MLX local fallback → degrade to text-only response in cockpit.
   - Fallbacks documented in `Construction/Gemini/response/MK2-EPIC-05-failover.md`.

3. **Wire the AMBIENT watch gateway:**
   - When `AMBIENT-001` lands, Watch streams audio frames through the tunnel via a new `JarvisRemoteRequest.audioFrame(Data, timestamp)` (add to `TunnelModels.swift`).
   - Host orchestrator accepts frames, performs STT locally (not on the Watch — respecting NLB: the Watch is a microphone, not a persona).
   - Operator approval persists per-device: Watch gateway requires its own voice-gate approval token.

4. **Smoke**: `scripts/smoke/voice-loop.sh`:
   - Plays a pre-recorded WAV file into a virtual audio device (or uses a CLI `--simulate-input` flag).
   - Asserts telemetry shows all 7 stages in order ending with `.ok`.
   - Asserts the rendered TTS output file is ≥ 1 s of audio.

### Out

- Do NOT re-implement VAD; use existing `Voice/VAD.swift` (or add a minimal `WebRTC VAD` wrapper if absent).
- Do NOT change `VoiceApprovalGate` logic; only add a new approval-token category for ambient gateway.
- Do NOT break VibeVoice fallback — it must remain runnable until F5 proven in production.

## Acceptance Criteria

- [ ] `scripts/smoke/voice-loop.sh` green.
- [ ] New tests ≥ 8: orchestrator stage ordering, STT failover, TTS failover, gate-denied rejection, ambient frame authorization (post-EPIC-02), ambient-frame rejection when unauthorized, telemetry event sequence, re-approval on model fingerprint change.
- [ ] P95 end-to-end latency (spoken → action executed) ≤ 1.5 s on local network (measure + log in response doc).
- [ ] `VoiceApprovalGate` remains model-fingerprint-bound; swapping TTS model triggers re-audition requirement (invariant test).

## Invariants

- SOUL_ANCHOR §3: voice gate primacy — no synth without approval.
- PRINCIPLES §2: STT runs locally by default; cloud STT requires explicit gate re-approval.
- NLB §1.1: no shared voice model weights between JARVIS and any other persona.

## Artifacts

- New: `Voice/VoicePipelineOrchestrator.swift`, `Voice/VoiceFailoverMatrix.swift`, `Tests/VoicePipelineOrchestratorTests.swift`, `scripts/smoke/voice-loop.sh`.
- Modified: `Shared/TunnelModels.swift`, `Host/JarvisHostTunnelServer.swift`, `Watch/Sources/JarvisWatchCore/*AudioGateway.swift` (when AMBIENT-001 lands; coordinate via Ralph state lessons).
- Response: `Construction/Gemini/response/MK2-EPIC-05.md` + `Construction/Gemini/response/MK2-EPIC-05-failover.md`.
