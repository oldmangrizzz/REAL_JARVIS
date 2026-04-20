# Construction/ — parallel spec orders

Two sub-teams working in parallel on the Real Jarvis navigation arc while the core team (operator + primary agent) keeps driving logic, policy, and cognition work in-tree.

## Split

| Model | Scope | Spec | Response |
|---|---|---|---|
| **GLM** | Navigation engine (tiles, routing, OSINT adapters, pre-search) | Design: `GLM/spec/NAV-001-universal-navigation-engine.md`<br>Active PR: `GLM/spec/NAV-001-EXECUTE-PR1.md` | Plan: `GLM/response/NAV-001-response.md` ✅<br>PR1 code: `GLM/response/NAV-001-EXECUTE-PR1.md` ⏳ |
| **Qwen** | UI/UX surfaces (iOS map, CarPlay HUD, PWA, Unity, briefing) | `Qwen/spec/UX-001-navigation-surfaces.md` | `Qwen/response/UX-001-response.md` ⏳ |
| **Gemini** | Voice pipeline — realtime speech-to-speech (F5-TTS baseline, bidirectional conversational loop) | `Gemini/spec/VOICE-001-f5-tts-swap.md` (baseline, ✅ complete), `Gemini/spec/VOICE-002-realtime-speech-to-speech.md` (endgame, ⚠️ design accepted, compile broken) | `Gemini/response/VOICE-001-response.md` ✅, `Gemini/response/VOICE-002-response.md` ⚠️ |
| **Nemotron** | Surgical Swift patches — compile-break remediation, Sendable audits, cross-lane contract cleanup | `Nemotron/spec/VOICE-002-FIX-01-remediation.md` | `Nemotron/response/VOICE-002-FIX-01-response.md` ⏳ |

## Rules of engagement

1. **No overlap.** GLM owns engine, Qwen owns surface. Contract in the middle is:
   - `MapTileProvider` (GLM defines, Qwen consumes)
   - `HazardOverlayFeature` (GLM emits, Qwen renders)
   - `SceneBriefing` (GLM builds, Qwen presents)
   - `RoutingProfile` identifiers (GLM owns; Qwen surfaces selection UI)
2. **Canon is canon.** Neither team may silently edit:
   - `Principal` tier model
   - `OSINTSourceRegistry` denylist
   - `CompanionCapabilityPolicy` (esp. `clinicalExecutionFragments`)
   - `WebContentFetchPolicy` + `SearchProvenance`
   - Canon-gate floor in `.github/workflows/canon-gate.yml`
   Flag anything that looks wrong in your "Open Questions" section. Do not push through.
3. **Response shape is declared in each spec.** Follow it. Use the section headings verbatim so diffs are reviewable.
4. **Gray, not black.** Open sources only. If a capability requires a denied source or dark source, stop and flag it.
5. **No EMS-specificity in engine-core.** Responder tier is an access layer, not the product.

## Status

- Specs landed: 2026-04-20
- GLM NAV-001 plan: **accepted** (507-line design, 6-PR sequence)
- GLM NAV-001-EXECUTE-PR1: _pending execution_ (OQ rulings answered, ships `MapTileProvider` + `TileProviderOrchestrator` + 9 tests)
- Qwen UX-001 response: _pending_ — Phase A (tokens) unblocked, Phase B+ waits on GLM PR1 type freeze
- Gemini VOICE-001 response: ✅ complete (F5-TTS server deploy + re-audition gate reset). Endgame VOICE-002 (realtime speech-to-speech) spec pending.
- Third track (operator + primary agent): logic/policy/cognition, continues in `Jarvis/Sources/**`

## Dependency map

```
GLM PR1 (MapTileProvider) ──► Qwen Phase B (NavigationMapView)
GLM PR2 (RoutingProfile)  ──► Qwen Phase B routing UI
GLM PR4 (HazardOverlay)   ──► Qwen Phase B hazard layers
GLM PR5 (SceneBriefing)   ──► Qwen Phase E briefing card
Qwen Phase A (tokens)     ──► independent, ships anytime
Gemini VOICE-001        ──► ✅ F5-TTS baseline shipped; VOICE-002 realtime S2S next
```
