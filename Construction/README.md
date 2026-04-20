# Construction/ — parallel spec orders

Two sub-teams working in parallel on the Real Jarvis navigation arc while the core team (operator + primary agent) keeps driving logic, policy, and cognition work in-tree.

## Split

| Model | Scope | Spec | Response |
|---|---|---|---|
| **GLM** | Navigation engine (tiles, routing, OSINT adapters, pre-search) | `GLM/spec/NAV-001-universal-navigation-engine.md` | `GLM/response/NAV-001-response.md` |
| **Qwen** | UI/UX surfaces (iOS map, CarPlay HUD, PWA, Unity, briefing) | `Qwen/spec/UX-001-navigation-surfaces.md` | `Qwen/response/UX-001-response.md` |

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
- GLM response: _pending_
- Qwen response: _pending_
- Third track (operator + primary agent): logic/policy/cognition, continues in `Jarvis/Sources/**`
