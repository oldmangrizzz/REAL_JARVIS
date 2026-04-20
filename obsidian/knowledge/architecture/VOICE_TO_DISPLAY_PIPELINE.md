# Voice → Display Pipeline

The path a single voice utterance takes from mic to screen/speaker,
with every gate it has to cross. This is the hot path of the system.

## Sequence

```
[1] Mac mic / mobile mic
     │
     ▼  raw PCM
[2] Voice.ContinuousListener  ─────────────┐
     │                                     │   ← reads local keyword /
     │                                     │     VAD; never forwards
     │                                     │     audio remotely.
     ▼  transcript                         │
[3] Interface.CommandParser                │
     │                                     │
     ▼  InterfaceCommand                   │
[4] Core.JarvisRuntime                     │   ← routes to skills
     │                                     │
     ▼  InterfaceResponse + ttsText        │
[5] Voice.ApprovalGate  ←──────────────────┘
     │  (must pass [[concepts/Voice-Approval-Gate]])
     ▼  approved render
[6] Voice.VibeVoiceClient
     │
     ▼  HTTPS POST /tts/synthesize
     │  (bearer, reference audio b64)
     │
     ▼  WAV bytes
[7] Voice.Playback (local)                ── also ──▶ [8] Interface.Cockpit UI
     │                                                    │  (Mac / Mobile / Watch / PWA)
     ▼                                                    ▼
[9] Telemetry.TelemetryStore (JSONL, append-only)    display
     │
     ▼  best-effort
    Convex (stigmergic_signals / execution_traces)
```

## Hard invariants

1. **[[concepts/NLB]]** — between [4] and [5], raw physics/PII is never
   stringified into the LLM prompt. Only derived state crosses.
2. **[[concepts/Voice-Approval-Gate]]** at [5] — no output audio is
   ever played or pushed to any client without a ratified approval
   token. The gate fails closed.
3. **[[codebase/modules/SoulAnchor]]** — [2] recording and [7]
   playback both require a currently-ratified Soul Anchor. If the
   Anchor trips, both halt.
4. Mobile/Watch/PWA are **consumers** of [8] — they never short-circuit
   [5]. Remote clients send transcripts up, never renders down, unless
   approved on the Mac.
5. Telemetry at [9] is append-only, hash-chained, and **records the
   gate outcome** (success, rejection reason). Redaction of content is
   enforced.

## Failure modes

- Gate rejection → Telemetry logs reason; UI surfaces the rejection; no
  audio plays.
- Anchor tripped → system enters Lockdown
  (`scripts/jarvis-lockdown.zsh`), pipeline halts at [2].
- VibeVoice unreachable → client falls back to local voice if any is
  permitted; otherwise fails closed.
- Telemetry disk full → best-effort; pipeline still completes, upload
  queue backs up.

## See also
- [[codebase/modules/Voice]]
- [[codebase/modules/Interface]]
- [[codebase/modules/Core]]
- [[codebase/modules/Telemetry]]
- [[codebase/services/vibevoice-tts]]
- [[architecture/TRUST_BOUNDARIES]]
