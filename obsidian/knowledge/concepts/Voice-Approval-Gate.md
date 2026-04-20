# Voice-Approval-Gate

**Source of truth:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift`
**Adjacent spec:** `PRINCIPLES.md` (operator register), `VERIFICATION_PROTOCOL.md §2` (Voice rendering gates)
**Classification:** **HARD BOUNDARY** (not formally "HARD INVARIANT" like [[concepts/NLB|NLB]], but enforced on every voice synthesis).

---

## Why it exists

The operator (Grizz) has an autism threat-response pattern in which unsanctioned audible speech — especially synthesized speech pretending familiarity — can spike the threat system. Voice is also the highest-trust channel JARVIS has: once something is spoken aloud through the workshop PA, [[codebase/frontend/pwa|PWA]], or an Apple-Watch wrist-tap, it is emotionally real in the room. Every TTS rendering is therefore gated *before* the bytes leave the synthesizer.

## What it enforces

1. **Explicit approval** for each voice identity / sample set. Voice reference WAVs are in `.jarvis/voice/` and must be registered in the approval ledger before any TTS backend is permitted to use them.
2. **Register discipline.** JARVIS speaks silly-99%-of-the-time baseline and can switch to "1900-mode" (clinical register) — but only matching the operator's own switching behavior, never unilaterally.
3. **Addressing discipline.** Operator is addressed as **Grizz** (baseline), **Grizzly** (warm), **Mr. Hanson** (1900-mode). Never "user," "human," or "operator" in spoken output (those appear only in logs).
4. **No pre-scripted first utterance.** The first words JARVIS ever speaks on a new session are composed from Soul Anchor state, after all deterministic gates pass green. See `PRINCIPLES.md §8`.
5. **Backend policy.** The approval gate sits in front of every backend registered in [[codebase/modules/Voice]] ([[codebase/services/vibevoice-tts|VibeVoice/GCP]], MLX-local Fish-Audio, raw HTTP TTS) so a new backend cannot silently slip past it.

## Signature and telemetry

- Every voice rendering is signed with **P256-OP** (`VERIFICATION_PROTOCOL.md §2`).
- Every rendering is recorded in the telemetry table via `VoiceGateTelemetryRecording.swift`.
- Any attempt to render without approval → `A&Ox3` degradation per [[concepts/AOx4|A&Ox4]] discipline.

## Relationship to other boundaries

- [[concepts/NLB]] — the NLB is about *who JARVIS talks to over what channel*; the Voice-Approval-Gate is about *what JARVIS is permitted to speak aloud*. They stack.
- [[architecture/TRUST_BOUNDARIES]] — the gate is drawn inside the outermost voice trust boundary.
- [[concepts/AOx4]] — failures collapse A&Ox to 3.
- [[codebase/modules/Voice]] — implementation module.
- [[codebase/modules/Telemetry]] — recording path.
