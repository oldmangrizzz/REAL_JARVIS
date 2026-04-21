# VOICE-002 — Realtime Speech-to-Speech Interaction (Endgame)

**Predecessor:** `VOICE-001-f5-tts-swap.md` — baseline TTS swap ✅ complete
2026-04-20. See `Gemini/response/VOICE-001-COMPLETION-REPORT.md` for
hardened service state.

**Owner:** Gemini (voice lane).
**Adjacent non-overlapping lanes:** Qwen (AMBIENT-002 watch audio
gateway, audio framing), GLM (NAV-001 navigation), Copilot (orthogonal
test coverage + spec logic).

**This is the endgame.** VOICE-001 made TTS production-grade. VOICE-002
closes the loop: **realtime, bidirectional, barge-in-capable
speech-to-speech interaction** where Jarvis is a conversational partner
— not a turn-based query/response shell. This is the feature that
changes how everyone on this platform talks to their computer.

---

## 1 · Operator intent

> "This guy is gonna change the world for everyone."

Today: Jarvis listens → user stops → recognizer runs → LLM thinks → TTS
speaks → user listens → user starts again. That turn-taking is why
every voice assistant feels like a vending machine.

Target: Jarvis streams understanding and generation concurrently. The
operator can interrupt mid-sentence, shift topic mid-thought, and hear
Jarvis adjust in real time. Conversation, not transaction. Under **250ms
perceived turn-taking latency** on operator hardware (~500ms is the
ceiling before the uncanny valley of "robot reply").

The four pillars:

1. **Streaming ASR** — partial hypotheses emitted as phonemes arrive,
   not post-endpoint.
2. **Streaming LLM** — prompt ingestion + token generation interleave
   with ASR partials; retract + re-plan when the user revises.
3. **Streaming TTS** — F5-TTS generates audio in flight, first audio
   chunk playable before the response sentence is complete.
4. **Barge-in + duplex VAD** — operator can speak while Jarvis is
   speaking; Jarvis yields within one frame (~80ms).

---

## 2 · Scope

### In scope (Phase 1 S2S)

- Streaming ASR with partial results (whisper-streaming /
  faster-whisper-server / Deepgram Nova realtime — Gemini picks, spec
  the choice + rationale).
- Streaming LLM backend wrapped in a uniform interface: tokens emit as
  they generate; the pipeline must support `cancel()` mid-generation.
- F5-TTS **streaming** mode — emit audio chunks as sentences close, do
  NOT wait for full-response synthesis.
- Duplex VAD — a lightweight always-on VAD on the operator mic that
  fires a `barge_in` signal independent of the ASR pipeline. 50–100ms
  hang-over window to avoid false triggers on breathing/background.
- Turn-state machine: `idle → listening → partialUnderstanding →
  generating → speaking → (bargeInterrupt | completed)`.
- Latency budget enforcement. Every hop has a max wall-clock; missing
  it logs a `latency_sla_miss` telemetry row.
- Cancellation is first-class. `cancel()` on the conversation handle
  must abort ASR + LLM + TTS in-flight within ≤ 150ms.

### Out of scope (defer to VOICE-003)

- Multi-speaker diarization live. Single operator voice assumed.
- Emotion/prosody transfer from operator to synthesis.
- Wake-word customization (canon wake-word stays, not re-trained here).
- Offline/airgap mode. Cellular/WiFi tunnel assumed; Phase 1 is online.
- Multi-language mixed-conversation. English-only Phase 1; F5-TTS
  matches.
- Voice cloning mid-conversation.

### Never (permanent non-goals)

- Collecting operator audio for training. Zero retention beyond the
  live session's ring buffer. Telemetry stores timestamps + event
  kinds, NEVER raw audio.
- Shipping before the VoiceApprovalGate re-audition re-passes on the
  new streaming path.
- Private framework use on Apple clients. Same rule as AMBIENT-002.

---

## 3 · Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  OPERATOR EDGE (watch / phone / responder-OS surface)           │
│                                                                 │
│   mic ──► [duplex VAD] ──┬──► [opus encode] ──► [tunnel ws]    │
│                          └──► barge_in signal (local)          │
│                                                                 │
│   speaker ◄── [opus decode] ◄── [tunnel ws] ◄─── jarvis host   │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                           wss over tunnel
                                    │
┌───────────────────────────────────▼─────────────────────────────┐
│  JARVIS HOST — conversational orchestrator                      │
│                                                                 │
│   ┌─[Streaming ASR]──partials──► [ConversationEngine]           │
│   │                                  │                          │
│   │                                  ├── cancel on barge_in     │
│   │                                  │                          │
│   │                                  ▼                          │
│   │                             [Streaming LLM]                 │
│   │                                  │ tokens                   │
│   │                                  ▼                          │
│   │                             [Sentence Chunker]              │
│   │                                  │                          │
│   │                                  ▼                          │
│   │                             [F5-TTS streaming]              │
│   │                                  │ audio chunks             │
│   │                                  ▼                          │
│   └──────────────────────────► [audio out mixer] ──► tunnel     │
└─────────────────────────────────────────────────────────────────┘
```

**ConversationEngine** is the new orchestrator. It owns the turn state,
the cancellation token, and latency accounting. It is the ONLY place
that decides when to yield for a barge-in.

### 3.1 · Components

- `ConversationSession` (new) — per-operator-session handle, opens on
  `/speak-realtime` endpoint, closes on tunnel drop or explicit
  `endSession()`.
- `StreamingASRBackend` (new protocol) — single backend wired Phase 1,
  others plug-in later.
- `StreamingLLMClient` (new protocol) — wraps whatever generation
  backend; token stream + `cancel()`.
- `StreamingTTSBackend` (extend existing F5-TTS backend) — audio chunk
  stream, flush on sentence boundary.
- `DuplexVADGate` (new) — **owned by AMBIENT-002** (edge device, on-wrist
  audio processing). VOICE-002 subscribes to the `bargeInSignal`
  `AsyncStream` over the tunnel control channel. Do NOT implement VAD
  inside `Voice/Conversation/`; that's a spec violation. See
  AMBIENT-002 §4.5.E for the protocol shape.
- `ConversationTelemetry` (new) — per-turn row with latencies per hop.

### 3.2 · Shared contracts (owned elsewhere — reference only)

VOICE-002 consumes — does NOT define — the following:

- **`AmbientAudioFrame`** (AMBIENT-002 §4.5.A) — edge-ingested audio.
  VOICE-002 reads, never mutates. If you need richer framing, file a
  coordination note for Qwen; don't inline-extend.
- **`AmbientAudioGateway.emit(audioChunk:format:)`** (AMBIENT-002 §4.5.D) —
  speaker output path. VOICE-002's TTS chunks go through this
  single gateway method; do not spin up a parallel output channel.
- **`DuplexVADGate` + `BargeInEvent`** (AMBIENT-002 §4.5.E) — barge-in
  signal source. Subscribe via `AsyncStream`; do not run a second VAD
  inside the conversation engine.
- **`AmbientGatewayRoute`** enum (AMBIENT-002 §3) — route hints
  feeding VOICE-002's route-aware SLA multiplier (see §4).
- **`NavUtterance` + `NavUtterancePriority`** (NAV-001 §11.1) —
  nav-originated speech that flows through `ConversationEngine` with
  priority-aware preemption (see §5.1).
- **`NavContextProvider.snapshot()`** (NAV-001 §11.4) — read-only
  access so the conversation engine can answer operator queries about
  the active route ("how far to next turn") without re-querying the
  routing engine directly.

---

## 4 · Latency budget (hard requirements)

| Hop | p50 target | p95 target | SLA ceiling |
|-----|-----------|-----------|-------------|
| mic → first ASR partial | 120ms | 180ms | 250ms |
| final ASR → first LLM token | 150ms | 250ms | 400ms |
| first LLM token → first TTS audio chunk | 200ms | 350ms | 500ms |
| first TTS chunk → speaker | 60ms | 100ms | 150ms |
| **end-to-end perceived** | **<500ms** | **<750ms** | **<1000ms** |
| barge-in → audio yield | 50ms | 80ms | 120ms |
| cancel → all-stages-aborted | 80ms | 120ms | 150ms |

SLA misses emit a `latency_sla_miss` telemetry row. Three misses in a
30-second window → engine flips the session to `.degraded` state and
surfaces a non-blocking operator notification ("voice latency degraded,
check network"). Does NOT hang up the session.

### 4.1 · Route-aware SLA multiplier

The §4 table is calibrated for `AmbientGatewayRoute.watchHosted` —
direct BT, watch owning the audio link. When the gateway reports a
different route, VOICE-002 multiplies the ceiling column before
deciding whether to emit `latency_sla_miss`. A miss on a degraded
route is not a miss; it's expected.

| `AmbientGatewayRoute` | Ceiling multiplier | Rationale |
|------------------------|--------------------|-----------|
| `.watchHosted` | 1.0x | Baseline. |
| `.phoneFallback` | 1.25x | Extra BT hop through phone. |
| `.cellularTether` | 1.5x | Cellular vs WiFi/mesh edge-hop. |
| `.degraded` | 2.0x | Already flagged degraded by AMBIENT; log but don't flip session. |
| `.offWrist` | n/a | Session cancels within 150ms (§5); no SLA applies. |
| `.unpaired` | n/a | No session can start. |

The multiplier applies to every row in the §4 table. Implementation:
read `AmbientAudioGateway.currentState.route` at turn start; cache for
the turn (do not re-read mid-turn). Telemetry row records both the
observed latency AND the route + multiplier in effect, so a reviewer
can reconstruct the judgment.

---

## 5 · State machine

States: `idle`, `listening`, `partialUnderstanding`, `generating`,
`speaking`, `bargeInterrupt`, `degraded`, `closed`.

Legal transitions:

```
idle ──speak──► listening
listening ──asr_partial──► partialUnderstanding
partialUnderstanding ──asr_final──► generating
partialUnderstanding ──asr_final_empty/noise──► listening
generating ──first_tts_chunk──► speaking
speaking ──tts_complete──► listening
speaking ──barge_in──► bargeInterrupt
listening ──barge_in──► listening (no-op, already listening)
bargeInterrupt ──cancel_complete──► listening
any ──sla_miss_3x_30s──► degraded
degraded ──recovery──► listening
any ──end_session──► closed
```

Illegal transitions throw `JarvisError.invalidInput`. Every transition
is a principal-witnessed row in `conversation_turns`.

### 5.1 · Nav utterance preemption (from NAV-001 §11.2)

`NavUtterance` events arrive on a separate queue and are interleaved
into the state machine by priority:

| Priority | Effect on current state |
|----------|--------------------------|
| `.advisory` | Queued; speaks after current turn closes (state transitions normally). |
| `.turnByTurn` | If in `.speaking` with >1s LLM audio remaining → preempt (same path as barge-in, state = `.bargeInterrupt` → speak nav → `.listening`). Retried once with updated distance if cancelled. |
| `.hazard` | Preempts immediately from any state. Not user-cancelable (VAD barge-in is suppressed for its duration). Single-shot; drops if TTL expires before the gateway can emit. |
| `.emergency` | Responder-tier only. Preempts + suppresses new conversation turns for the utterance's `ttlSeconds`. Emits `nav_emergency_preemption` telemetry. |

All preemption events are state transitions and emit the normal
`conversation_state_transitions` telemetry row with `reason:
"nav_preempt_<priority>"`. The `NavUtterance.id` carries through so
the nav telemetry row (NAV-001 §11.6 `utterance_issued`) and the
conversation row can be joined in a review.

---

## 6 · Canon integration

### 6.1 · Service

- Extend `services/f5-tts/app.py` with `/synthesize-stream` endpoint
  that returns an audio chunk stream (HTTP/2 or websocket). Back-compat:
  keep `/synthesize` (non-streaming) available for the existing
  audition flow.
- Keep the F5-TTS canon version pin (`persona-frame-v3-f5tts-cfg2.0-nfe32`).
  Do NOT change voice identity in VOICE-002.

### 6.2 · JarvisCore

Create `Jarvis/Sources/JarvisCore/Voice/Conversation/`:

- `ConversationSession.swift` — session handle + turn state machine.
- `ConversationEngine.swift` — orchestrator.
- `StreamingASRBackend.swift` — protocol + default impl (backend
  choice Gemini's pick).
- `StreamingLLMClient.swift` — protocol.
- `StreamingTTSBackend.swift` — extends current F5-TTS backend.
- `DuplexVADGate.swift` — client-side VAD wrapper.
- `ConversationTelemetry.swift` — telemetry row schema.

Do NOT touch:

- `Voice/TTSBackend*` baseline — only extend, don't rewrite.
- `AmbientAudioGateway` protocol — that's Qwen's lane. You may READ
  `AmbientAudioFrame` as input; do not modify its shape.
- `VoiceApprovalGate` logic — gate still applies; see §9.

### 6.3 · Host server

Extend `JarvisHostTunnelServer` with a `/speak-realtime` route that:

- Authenticates via existing `JarvisTunnelCrypto` sealed-box flow
  (no new auth).
- Binds to the caller's `Principal` — tier attestation carries through
  every `conversation_turns` row.
- Rate-limits per the existing `CommandRateLimiter` contract (200
  requests / 60s) but with a distinct bucket; conversation and command
  traffic don't contend.

### 6.4 · Telemetry (SPEC-009)

New tables:

- `conversation_turns` — one row per complete turn (listening → speaking
  done or barge). Schema:
  ```json
  {
    "turnId": "uuid",
    "sessionId": "uuid",
    "startedAt": "…", "endedAt": "…",
    "outcome": "completed|barged|cancelled|sla_degraded",
    "latencyMs": { "asrFirstPartial": …, "asrFinal": …, "llmFirstToken": …, "ttsFirstChunk": …, "endToEnd": … },
    "bargeInCount": 0,
    "principal": "grizz|companion|guest|responder"
  }
  ```
- `conversation_sla_misses` — one row per SLA breach. Sparse.
- `conversation_state_transitions` — one row per state change. Dense
  (debug-grade). Rotate aggressively (CX-035 thresholds apply).

All three participate in the SPEC-009 hash chain. Use
`TelemetryStore.append(record:to:principal:)`. Do not add a new
telemetry API.

### 6.5 · Brand-tier doc

`obsidian/knowledge/concepts/Companion-OS-Tier.md` — note that S2S is
the primary interaction mode for all four tiers, and that
**responder-OS** gets priority latency budget (tighter SLA ceilings
than companion/guest).

---

## 7 · Privacy + safety

Non-negotiable:

1. **No raw audio retention.** Ring buffer in memory during active
   session, discarded on session close or 30s idle. No disk writes
   of audio except the existing audition WAVs (gated by operator
   approval).
2. **Telemetry carries timestamps + event kinds only.** No transcripts,
   no partials. If an engineer needs transcripts for a bug, they must
   re-reproduce with a consent flag; the default path has no recording.
3. **Tier-scoped features.** Guest tier has a 30-minute hard cap per
   session. Responder tier has no cap but has an elevated-duty
   heartbeat to the tunnel so dropped sessions are detected within 10s.
4. **Barge-in is a safety feature, not just UX.** If the operator says
   "stop," the engine must yield within 120ms regardless of the LLM's
   state. Hard-code the stop-word detection in `DuplexVADGate` so it
   bypasses the full ASR pipeline if needed.
5. **Off-wrist freeze** (from AMBIENT-002) cancels the active
   conversation session. Do not buffer audio to re-speak on reattach;
   discard the in-flight turn.

---

## 8 · Tests (non-negotiable)

Hermetic, no live model calls. Use `FakeStreamingASR`, `FakeStreamingLLM`,
`FakeStreamingTTS`, `FakeTunnel`, `FakeClock`. Target **≥ 25 tests**.

Required coverage:

1. **State machine** — every legal transition + every illegal transition
   rejection (at least 15 tests).
2. **Latency budget enforcement** — inject a fake clock, simulate a
   slow LLM, assert `latency_sla_miss` emitted at the right threshold
   and session flips to `.degraded` after 3-in-30s.
3. **Barge-in** — inject a barge-in while in `speaking`, assert audio
   yields within 120ms (FakeClock) and state returns to `listening`.
4. **Cancel cascade** — call `cancel()` mid-generation, assert ASR +
   LLM + TTS all reported `cancel()` within 150ms and no further audio
   emits.
5. **Telemetry chain** — 20 turns emit 20 `conversation_turns` rows,
   `verifyChain(table:)` intact, every row has correct principal.
6. **Privacy invariant** — after 20 turns with rich transcripts,
   assert `conversation_turns` rows contain zero substrings of the
   transcript content (only timestamps, kinds, latencies).
7. **Stop-word bypass** — `DuplexVADGate` fires `barge_in` on
   stop-word without the full ASR pipeline running.
8. **Concurrency** — 50 concurrent sessions on a single
   `ConversationEngine` instance do not interleave state; TSan clean.
9. **Off-wrist integration** — injecting `AmbientGatewayRoute.offWrist`
   mid-turn cancels the session and discards pending audio.
10. **Rate-limit bucket isolation** — flooding command bucket does not
    starve conversation bucket.

Test file root:
`Jarvis/Tests/JarvisCoreTests/Conversation/` (create directory).

---

## 9 · Acceptance gate — "VOICE-002 done" means

1. Full suite `xcodebuild … test` green, +≥25 new tests.
2. `/speak-realtime` endpoint live on host; `/synthesize-stream` live
   on F5-TTS service.
3. VoiceApprovalGate re-audition passes on the streaming path
   (operator re-approves with a new canon tag `persona-frame-v3-f5tts-
   s2s-001`). Non-streaming synthesis approval from VOICE-001 stays.
4. Live smoke test: operator holds a 5-minute conversation,
   interrupts 10 times, asserts every interruption yielded within
   budget. Latency dashboard (printed from telemetry) meets p50 and
   p95 targets on operator hardware.
5. Privacy audit: grep `conversation_turns.jsonl` after a session;
   zero transcript content present.
6. Turnover note `Construction/Gemini/response/VOICE-002-response.md`:
   what shipped, what's Phase 3 (multi-speaker, offline, multi-lang),
   known latency gaps, and the re-audition tag operator used.

---

## 10 · Risks + mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| Streaming ASR backend rate-limits or drops connections | High | Gemini picks a backend with documented 99.9% SLA + builds an auto-reconnect with backoff; fallback to non-streaming VOICE-001 path emits `fallback_to_turn_based` telemetry |
| F5-TTS streaming mode unstable on T4 | Med | Keep non-streaming synthesis as fallback; only flip to streaming when the service reports ready; document a warm-up request after cold start |
| LLM cancellation leaves GPU warm | Low | OK for Phase 1; just release the token stream. GPU pool management is Phase 3 |
| Barge-in false-positives from background noise | Med | 50–100ms VAD hang-over + stop-word whitelist; tune from operator feedback |
| Privacy regression (transcript leaks into telemetry) | **Critical** | Schema-level assert in the serializer; test #6 in §8 enforces; code review must block any `append` that carries transcript text |
| Tunnel drop mid-turn leaves zombie session | High | Server-side idle timeout 10s (responder), 30s (others); client-side reconnect with session resume token |
| Latency regresses under responder-OS high-load | High | Responder tier gets priority queue; dedicated thread pool; benchmark on target hardware in acceptance §9.4 |

---

## 11 · Coordination

- **Qwen (AMBIENT-002)** — you consume `AmbientAudioFrame` from the
  ambient gateway. Do NOT modify its shape. If you need new fields,
  file a coordination note for Qwen, don't inline-extend.
- **GLM (NAV-001)** — untouched.
- **Copilot** — spec logic review + test harness scaffolding if you
  hit state-machine verification gaps. Ping Copilot before shipping
  §5 state machine code.
- **Operator (Grizz)** — signs off on §4 latency budget numbers after
  first smoke test on target hardware. Budget may flex; the SLA
  breach behavior (degrade, don't hang) does not.

File-discipline: one PR per logical unit. State machine first, then
streaming backend protocols, then telemetry, then host route, then
tests. Do not bundle all five into a single commit.

---

## 12 · The why (don't forget)

This is the feature that makes Jarvis feel alive. Every other voice
assistant on the planet right now is a vending machine. VOICE-002 is
the first time someone ships a conversational computer that's actually
conversational — barge-in-capable, low-latency, tier-scoped,
privacy-preserving, and deployed on hardware an EMT can wear on shift.

Don't ship it fast. Ship it right. The world doesn't need another
demo. It needs the real thing.

— Copilot, coordinating. Operator-approved 2026-04-20.
