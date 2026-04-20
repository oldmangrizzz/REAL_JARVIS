# NAV-001-A — Execute PR1 (Phase A: MapTileProvider + Orchestrator)

**Responds to:** `Construction/GLM/response/NAV-001-response.md`
**Status:** Design accepted. Ship PR1 now.

---

## Open-question rulings (apply these to the code you ship)

- **OQ-1** (canon-floor mismatch): **Fixed in-tree.** The actual floor is 250; error message corrected in this same commit. When you bump the floor in a later PR, bump both the `# Floor: at least N tests` comment and the `[ "$EXECUTED" -lt N ]` check together. Do NOT touch the floor in PR1 — defer to PR5 per your own sequencing.
- **OQ-2** (road-graph source): Caller-supplied `RoadGraph` protocol is correct for PR2. For PR1, no graph work needed. In PR2, define the protocol with `edges(near:)` + `edge(id:)` + `neighbors(of:)`. Bundled static graph for tests, Mapbox Directions adapter is a follow-up ticket (not in-scope for NAV-001).
- **OQ-3** (taught-parameters persistence): In-memory `[String: Double]` for now is correct. Add a `// CANON: operator-teachable; persistence ticket pending` marker. Persistence surface is `obsidian/knowledge/operator-taught/` JSON files, but that's a separate ticket — don't block on it.
- **OQ-4** (compile-time host check): **Test-time assertion is acceptable.** In `TileProviderOrchestratorTests`, add a test that iterates `OSINTSourceRegistry.canonical` and asserts every declared tile host is present. No build-phase script for now.
- **OQ-5** (URL construction): Adapters construct URLs from `OSINTSourceRegistry.canonical` hosts, then pass to `OSINTFetchGuard.authorize(url:principal:)`. If the registry host changes, adapter updates in lockstep — ship a registry-change checklist in `docs/` later. Not in PR1.
- **OQ-6** (geometry enum): `HazardGeometry` enum `.point | .line | .polygon` is fine for PR4. MultiPolygon/GeometryCollection → future extension, flag in a code comment.

## Ship PR1 end-to-end

Write actual Swift (not pseudocode) at these paths per your File Manifest §2 Phase A:

1. `Jarvis/Sources/JarvisCore/Navigation/MapTileProvider.swift`
2. `Jarvis/Sources/JarvisCore/Navigation/MapboxTileProvider.swift`
3. `Jarvis/Sources/JarvisCore/Navigation/MapLibreOSMTileProvider.swift`
4. `Jarvis/Sources/JarvisCore/Navigation/TileProviderOrchestrator.swift`
5. `Jarvis/Tests/JarvisCoreTests/Navigation/MapTileProviderTests.swift`
6. `Jarvis/Tests/Fixtures/Navigation/tile_provider_health.json`

### Rules

- **Swift 6, strict concurrency.** Mark provider types `Sendable` where appropriate. Use `actor` for `TileProviderOrchestrator` state.
- **No network in unit tests.** Health probes in tests must accept a protocol-typed transport that tests stub.
- **Canon-gate:** Do NOT bump `.github/workflows/canon-gate.yml` in PR1 per your own R7 mitigation. Defer to PR5.
- **No UI code.** No SwiftUI, no MapKit UI. This is engine-core only.
- **Mapbox credentials:** `MapboxCredentials.publicToken` is the only tier-visible secret for PR1. If a type/struct doesn't exist yet, create it in `Jarvis/Sources/JarvisCore/Navigation/MapboxCredentials.swift` with a clear "PLACEHOLDER: operator must inject" comment. Do NOT inline any real token.
- **OSINTSourceRegistry coupling:** Reference the existing registry; add tile-host entries if missing (`api.mapbox.com`, `tile.openstreetmap.org`, `tile.openstreetmap.de`). Host additions require a short justification in your response.
- **Tests:** At least 9 tests per your own estimate. Cover: primary healthy → use primary; primary fails 3x → auto-demote to fallback; fallback also fails → return a structured `TileProviderError.allProvidersUnhealthy`; canon-gate registry check; audit-log on switch.
- **Golden determinism:** Same input → identical output. Tests must be hermetic.

### Response format

Write your PR1 delivery as a diff-style response at `Construction/GLM/response/NAV-001-A-PR1-response.md`, including:

1. **Files landed** — path + LOC per file.
2. **Full file contents** — every new `.swift` and `.json` file, fenced in triple-backticks with language tags. This lets the operator apply in one pass.
3. **Test count delta** — number of new tests executed (for PR5 floor math).
4. **How to run locally:**
   ```
   xcodebuild -scheme Jarvis -configuration Debug -destination 'platform=macOS' test -only-testing:JarvisTests/MapTileProviderTests
   ```
5. **Canon-clean checklist:**
   - [ ] No changes to `.github/workflows/canon-gate.yml`
   - [ ] No changes to `OSINTSourceRegistry.canonical` denylist (additions to allowlist only, justified)
   - [ ] No changes to `Principal`, `CompanionCapabilityPolicy`, `WebContentFetchPolicy`
   - [ ] No UI code
   - [ ] No secrets committed
6. **Open questions for PR2** — anything you hit in PR1 that informs PR2 design.

### Out of scope for PR1

- RoutingProfile / UniversalRouter (PR2)
- OSINT adapters (PR4)
- ScenePreSearch (PR5)
- Pheromind/oscillator wiring (PR6)
- LiveKit, CarPlay, AR (never in this track)

---

**Greenlight. Ship it.**
