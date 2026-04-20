# NAV-001-EXECUTE — Ship PR1 (Phase A: MapTileProvider + Orchestrator)

**Target model:** GLM (z.ai / glm-5.1)
**Reads from:** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md` (design spec — already accepted)
**Responds with:** `Construction/GLM/response/NAV-001-EXECUTE-PR1.md` (contains full Swift/JSON file contents, operator applies in one pass)
**Parallel spec (sync'd):** `Construction/Qwen/spec/UX-001-navigation-surfaces.md`
**Canon floor:** 250 tests — **do NOT bump in PR1** (deferred to PR5 per GLM-authored R7 mitigation)

---

## 0. What's already done (do NOT redo)

- Design spec NAV-001 accepted. Your 507-line plan in `GLM/response/NAV-001-response.md` is the source of truth for the 6-PR sequence.
- `.github/workflows/canon-gate.yml` — floor-comment vs error-message mismatch already fixed in commit `85b7aae` (comment was 250, error said 213; both now say 250).
- Prior in-flight response `GLM/response/NAV-001-response.md` crashed mid-PR1. Start fresh; do not assume any file in `Jarvis/Sources/JarvisCore/Navigation/` exists.

## 1. Open-question rulings (apply as hard law, do not re-litigate)

- **OQ-1 (canon-floor mismatch):** Fixed in-tree. When PR5 bumps the floor, bump BOTH the `# Floor: at least N tests` comment AND the `[ "$EXECUTED" -lt N ]` check together.
- **OQ-2 (road-graph source):** PR2 defines `RoadGraph` protocol (`edges(near:)`, `edge(id:)`, `neighbors(of:)`); caller-supplied. PR1 is tile-only, no graph work.
- **OQ-3 (taught-parameters persistence):** In-memory `[String: Double]` for PR3. Mark `// CANON: operator-teachable; persistence ticket pending`. Obsidian vault persistence is a future ticket.
- **OQ-4 (compile-time host check):** Test-time assertion in `TileProviderOrchestratorTests` — iterate `OSINTSourceRegistry.canonical` and assert every declared tile host is present. No build-phase script.
- **OQ-5 (URL construction in adapters):** Adapters build URLs from `OSINTSourceRegistry.canonical` hosts, pass to `OSINTFetchGuard.authorize(url:principal:)`. Lockstep-update doc in `docs/` deferred. PR1 not affected.
- **OQ-6 (geometry enum):** `HazardGeometry` enum `.point | .line | .polygon` is fine for PR4. Extension for MultiPolygon is future work. PR1 not affected.

## 2. PR1 scope — ship these files end-to-end (Swift 6, strict concurrency)

Create exactly these paths, with full file contents in your response:

1. `Jarvis/Sources/JarvisCore/Navigation/MapTileProvider.swift`
   - `protocol MapTileProvider: Sendable` with: `identifier: String`, `attribution: String`, `func styleURL(for: Principal) throws -> URL`, `func healthProbe() async -> TileProviderHealth`.
   - `enum TileProviderHealth: Sendable { case healthy, degraded(reason: String), unhealthy(reason: String) }`
   - `enum TileProviderError: Error, Sendable { case hostNotRegistered(String), unauthorizedTier(Principal), allProvidersUnhealthy([String]) }`

2. `Jarvis/Sources/JarvisCore/Navigation/MapboxCredentials.swift`  *(create if missing)*
   - `struct MapboxCredentials: Sendable { public let publicToken: String; public let secretToken: String? }` with a `// PLACEHOLDER: operator injects via keychain` comment. Do NOT inline any real token. If it already exists elsewhere, use that type — verify via grep before creating.

3. `Jarvis/Sources/JarvisCore/Navigation/MapboxTileProvider.swift`
   - Conforms `MapTileProvider`. Uses `MapboxCredentials.publicToken` only. Style URL builds against `api.mapbox.com`. `healthProbe()` hits a low-cost tile metadata endpoint through an injectable `TileTransport` protocol (no direct `URLSession` call in unit tests).

4. `Jarvis/Sources/JarvisCore/Navigation/MapLibreOSMTileProvider.swift`
   - Conforms `MapTileProvider`. No credentials. Uses `tile.openstreetmap.org` (or `tile.openstreetmap.de` as mirror). Respect OSM tile usage policy: document the user-agent requirement in a comment; leave the injectable user-agent as an init param with a sensible default (`"RealJarvis/1.0 (+https://grizzlymedicine.org)"`).

5. `Jarvis/Sources/JarvisCore/Navigation/TileProviderOrchestrator.swift`
   - `actor TileProviderOrchestrator`.
   - Init takes: `primary: any MapTileProvider`, `fallback: any MapTileProvider`, `failureThreshold: Int = 3`, `auditLog: AuditLog`.
   - Public: `func currentProvider() -> any MapTileProvider`, `func recordHealth(_:)`, `func probe() async`.
   - State: consecutive-failure counters per provider; auto-demote primary → fallback after N consecutive unhealthy probes; recovery path when primary returns healthy.
   - **Every switch logs via `AuditLog`** (use the existing `AuditLog` type if present; otherwise define a minimal protocol in this file with a stub in-memory impl and flag it in Open Questions).
   - At init, calls a canon-gate check: every provider's `identifier` must resolve to an entry in `OSINTSourceRegistry.canonical`. Throw `TileProviderError.hostNotRegistered` otherwise.

6. `Jarvis/Tests/JarvisCoreTests/Navigation/MapTileProviderTests.swift`
   - **9 tests minimum:**
     1. `testMapboxProviderUsesPublicToken` — asserts secret token never read.
     2. `testMapboxStyleURLHost` — URL host is `api.mapbox.com`.
     3. `testOSMProviderNoCredentialsRequired`.
     4. `testOSMProviderUserAgentSet` — asserts default UA compliant with OSM policy.
     5. `testOrchestratorUsesPrimaryWhenHealthy`.
     6. `testOrchestratorDemotesAfterNFailures` — N=3, stubbed transport returns unhealthy.
     7. `testOrchestratorRecoversWhenPrimaryReturns` — after demotion, primary goes healthy for consecutive probes → switch back.
     8. `testOrchestratorBothProvidersUnhealthyRaises` — `TileProviderError.allProvidersUnhealthy`.
     9. `testOrchestratorCanonGateRejectsUnregisteredHost` — construct a provider with `identifier="roadsideamerica.com"` (denied source) → init throws `.hostNotRegistered`.
     10. (optional bonus) `testOrchestratorAuditsEverySwitch` — in-memory audit log receives one entry per transition.

7. `Jarvis/Tests/Fixtures/Navigation/tile_provider_health.json`
   - Small JSON fixture used by the stub `TileTransport` to sequence health responses: an array of `{ "provider": "mapbox", "status": "healthy|degraded|unhealthy", "reason": "..." }` steps. Keep it ≤ 2 KB.

## 3. Hard rules

- **Swift 6, strict concurrency.** `Sendable` where data types cross actor boundaries. `actor` for orchestrator state. No warnings allowed.
- **No real network calls in tests.** All transports must be protocol-injected. Unit tests use deterministic stub transports driven by the fixture.
- **No UI code.** No SwiftUI, no MapKit UI, no CoreLocation mutation. Engine-core only.
- **No secrets committed.** `MapboxCredentials` has placeholder text only.
- **OSINTSourceRegistry additions allowed.** If `mapbox.tiles` / `osm.tiles` entries aren't already present, add them with:
  - Short justification in your response
  - Host + attribution + robots posture recorded
  - Must NOT be added to `OSINTSourceRegistry.deniedSources`.
- **Canon-gate.yml:** do NOT touch in PR1.
- **`Principal`, `CompanionCapabilityPolicy`, `WebContentFetchPolicy`:** do NOT modify.
- **Forbidden deps:** no new third-party SwiftPM deps. Stay inside what's in `Package.swift` today.

## 4. Response shape (verbatim section order)

Write `Construction/GLM/response/NAV-001-EXECUTE-PR1.md` with:

1. **Summary** — one paragraph. What landed, why the operator can merge it.
2. **File manifest** — path / LOC / purpose for each of the 7 files.
3. **Full file contents** — every `.swift` and `.json` inline, fenced ` ```swift ` / ` ```json `. This is the source of truth; operator applies by copying blocks. Do not abbreviate, do not `// ...` middle sections.
4. **Registry additions** — if you added `mapbox.tiles` / `osm.tiles` entries to `OSINTSourceRegistry.canonical`, show the exact diff and justify each addition in 1–2 sentences.
5. **Test matrix** — table: test name → what it proves → how long it takes. Confirm all 9 run hermetic (no network).
6. **How to verify locally**:
   ```
   xcodebuild -scheme Jarvis -configuration Debug -destination 'platform=macOS' \
     test -only-testing:JarvisTests/MapTileProviderTests 2>&1 | tail -30
   ```
7. **Canon-clean checklist** (all must be checked):
   - [ ] `.github/workflows/canon-gate.yml` not modified
   - [ ] `Principal` / `CompanionCapabilityPolicy` / `WebContentFetchPolicy` not modified
   - [ ] `OSINTSourceRegistry.deniedSources` not modified
   - [ ] No UI code
   - [ ] No real tokens committed
   - [ ] No network calls in tests
   - [ ] Swift 6 strict-concurrency clean
8. **Test-count delta** — integer count of new executed tests added.
9. **Handoff notes for PR2** — anything PR1 surfaced that PR2 (`RoutingProfile` + `UniversalRouter` core) needs to know.
10. **Open questions** — anything you hit that needs operator ruling. Do NOT silently work around canon.

## 5. Out of scope (future PRs, do not ship in PR1)

- PR2: `RoutingProfile`, `UniversalRouter`, `RoadGraph` protocol, golden-file fixtures
- PR3: Seed profiles (Standard/Accessibility/EMS/Scenic)
- PR4: OSINT adapters (TxDOT, FIRMS, NOAA, USGS) + `HazardOverlayFeature` + `HazardCache`
- PR5: `ScenePreSearch` + `SceneBriefing` + **canon-gate floor bump**
- PR6: Pheromind/oscillator wiring

These land in later spec orders (`NAV-001-EXECUTE-PR2.md`, etc.) after PR1 merges green.

## 6. Parallel track (Qwen)

Qwen is working `UX-001` (surfaces). Contract types you must keep stable for Qwen:

- `MapTileProvider` protocol shape (Qwen consumes, never defines)
- `HazardOverlayFeature` — PR4 only, not in PR1
- `SceneBriefing` — PR5 only, not in PR1
- `RoutingProfile.principalScope` — PR2

In PR1 you only expose `MapTileProvider` and `TileProviderOrchestrator`. Qwen's Phase B (NavigationMapView) will inject a `MapTileProvider` instance when that lands — keep the protocol shape rock-solid.

---

**Greenlight. Ship PR1. Inline the code. One clean response, one clean merge.**
