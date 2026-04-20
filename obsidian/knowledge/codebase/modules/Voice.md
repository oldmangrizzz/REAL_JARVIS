# Voice

**Path:** `Jarvis/Sources/JarvisCore/Voice/`
**Files:** 6 (1656 lines)
- `VoiceApprovalGate.swift` — **HARD GATE** (see [[concepts/Voice-Approval-Gate]])
- `VoiceSynthesis.swift` — public synthesis API
- `TTSBackend.swift` — backend protocol + render params
- `HTTPTTSBackend.swift` — production path (VibeVoice on GCP)
- `FishAudioMLXBackend.swift` — local fallback
- `VoiceGateTelemetryRecording.swift` — telemetry decoupling protocol

## Purpose
Speak aloud to the operator — but ONLY after passing the [[concepts/Voice-Approval-Gate|Voice-Approval-Gate]].
Motivated by a documented autism-threat-response pattern (prior consequence:
destroyed $3,000 television). Gate is green only after the operator has
manually auditioned a rendered sample and signed the voice-identity
fingerprint. `speak()` refuses until then.

## Key types
- `VoiceApprovalGate` — the hard gate. Checks fingerprint before any audio exits.
- `VoiceReferenceProfile` — operator-approved reference audio + transcript.
- `VoiceSynthesisResult` — rendered WAV + telemetry.
- `TTSBackend` (protocol) — implemented by HTTP + Fish.
- `TTSRenderParameters` — temp, cfgScale, ddpmSteps, etc.
- `VoiceGateTelemetryRecording` (protocol) — keeps gate free of direct
  [[codebase/modules/Telemetry]] coupling; all telemetry is best-effort.

## Production path
1. Runtime calls `VoiceSynthesis.render(text, profile, params)`.
2. `HTTPTTSBackend` POSTs to VibeVoice FastAPI
   ([[codebase/services/vibevoice-tts]]) with base64 reference + transcript.
3. Returned WAV hits `VoiceApprovalGate` — blocked unless fingerprint matches.
4. Telemetry recorded via `VoiceGateTelemetryRecording` conformer.

## Fallback
`FishAudioMLXBackend` shells out to bundled `mlx-audio-swift-tts`. Heavy on
8 GB Macs; only used when HTTP path is unreachable.

## Related
- [[concepts/Voice-Approval-Gate]] — the doctrine.
- [[codebase/services/vibevoice-tts]] — the service.
- [[architecture/TRUST_BOUNDARIES]] — the gate class this enforces.
- `voice-approve-canonical.zsh` — operator-side approval tool.
