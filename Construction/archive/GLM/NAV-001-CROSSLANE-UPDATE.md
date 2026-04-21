# NAV-001 — Cross-Lane Update (post-cook briefing)

**Hand this to GLM the moment his NAV-001 response doc is ready to post.**
Engine-core (§1–§10) was not touched. Two additive edits landed on the spec
while he was cooking: one factual correction to §9, and a new §11.

---

## 1. §9 — factual correction (one line)

The prior line claiming `Construction/Gemini/spec/VOICE-001-f5-tts-swap.md`
is "unrelated" to nav was corrected. Gemini's realtime speech-to-speech
work (VOICE-002) will consume nav output. GLM still does **NOT** touch
any Gemini files in this PR.

---

## 2. §11 — Forward-looking integration (new, additive, ~165 lines)

**Read, don't implement.** Engine-core this PR stays voice-free per §7.
§11 locks four contract shapes into the NAV-001 type surface so the
downstream voice-wiring ticket is a wiring job, not a redesign.

What §11 introduces:

- **`NavUtterance`** + **`NavUtterancePriority`** enum
  - Order: `advisory` < `turnByTurn` < `hazard` < `emergency`
  - Emit to a local queue this PR. No TTS call. No `AVSpeechSynthesizer`.
- **Barge-in preemption matrix**
  - `hazard` = uncancelable safety override
  - `emergency` = responder-tier only, preempts + suppresses conversation for TTL
- **Audio output path** goes through `AmbientAudioGateway.emit`
  - Do **NOT** build a parallel TTS-out path
  - Route: `RoutingEngine → NavUtterance queue → ConversationEngine → F5-TTS → AmbientAudioGateway.emit → speaker`
- **`NavContextSnapshot`** + **`NavContextProvider`** (read-only)
  - Lets conversation engine answer "how far to next turn" with grounded data
- **Off-wrist asymmetry ruling (canon)**
  - Off-wrist cancels conversation within 150ms
  - Off-wrist does **NOT** cancel nav — nav drains to phone/CarPlay if phone is in mesh
  - Intentional asymmetry; do not unify the behavior

---

## 3. What this means for GLM's in-flight response

Three possibilities:

1. **If Phase A–E response already defines these types with different shapes**
   → Align to §11 shapes before posting. Rename/refactor is cheap now,
     expensive after GLM ships.

2. **If Phase A–E response hasn't defined them yet**
   → Add §11 types to whichever phase owns the routing-engine output surface
     (Phase B or D). Stub implementation only: emit to local queue, no TTS call.
     Surface area: ~30 lines.

3. **If GLM prefers to ship Phase A–E untouched and bolt §11 on in a follow-up PR**
   → Acceptable, but call it out in the response doc so downstream knows.

**Test coverage for §11 in this PR:** one test per priority level covering
enqueue + TTL drop is sufficient. Full preemption coverage lives in VOICE-002
test matrix, not NAV-001.

---

## 4. Still do NOT touch (reinforced)

- `Construction/Qwen/**`
- `Construction/Gemini/**`
- `Jarvis/Sources/JarvisCore/Voice/**`
- Responder-surface UI
- Any `Intent*` or `Display*` symbol
- Any file listed in §7 Out of scope

---

## 5. Parallel-track context (informational only)

| Lane | Status | Relevance to NAV-001 |
|------|--------|----------------------|
| Qwen / AMBIENT-001 research | ✅ shipped (632 lines) | Confirms watch owns BT directly to headphones (Apple 2026 API). |
| Qwen / AMBIENT-002 Phase 1 impl spec | 📝 drafted | Owns canonical `AmbientAudioFrame` schema, `AmbientAudioGateway.emit`, `DuplexVADGate`. Referenced by §11.3. |
| Gemini / VOICE-001 F5-TTS swap | ✅ shipped | No nav impact (but operator re-audition required separately). |
| Gemini / VOICE-002 realtime S2S | 📝 drafted | Consumes NAV-001 §11 utterance stream + nav context snapshot. |
| Copilot / test coverage | ongoing | TelemetryChainWitnessTests 6→11. Full suite 433/433. |

Downstream specs (AMBIENT-002, VOICE-002) both reference NAV-001 §11 as
source-of-truth for nav contracts. If GLM's response changes any §11 type
shape, those downstream specs rebase automatically on the next commit.

---

## 6. Action on GLM's side

Post Phase A–E response verbatim per §6 when ready. If §11 types are
integrated into the response, note that in the response header so downstream
knows they don't have to ask. If §11 is deferred to a follow-up, call that
out too.

That's it. Ship it.
