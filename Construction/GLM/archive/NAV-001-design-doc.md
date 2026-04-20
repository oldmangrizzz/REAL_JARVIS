# NAV-001 — Universal Navigation Engine (GLM Spec Order)

**Target model:** GLM (z.ai / glm-5.1)
**Scope owner:** Real Jarvis / JarvisCore
**Response path:** `Construction/GLM/response/NAV-001-response.md`
**Parallel spec:** `Construction/Qwen/spec/UX-001-navigation-surfaces.md` (UI/UX — do not overlap)
**Canon floor:** 250 tests, Swift 5.9+, SwiftPM + Xcode workspace

---

## 0. Read-First (non-negotiable context)

Before writing a single line, read and internalize:

1. `docs/COGNITIVE_ARCHITECTURE.md` — three-layer doctrine (substrate / topology / gain). Navigation is a consumer of salience, not a replacement for it.
2. `Jarvis/Shared/Sources/JarvisShared/Principal.swift` — tier model (`.operatorTier / .companion / .guestTier / .responder(role:)`). Every capability you expose must honor tier.
3. `Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` — especially `clinicalExecutionFragments`. Responder tier is **advocacy + situational awareness**, never clinical execution.
4. `Jarvis/Sources/JarvisCore/OSINT/OSINTSourceRegistry.swift` — canonical open-source feeds. **You do not fetch from a host that isn't in this registry. Period.**
5. `Jarvis/Sources/JarvisCore/OSINT/WebContentFetchPolicy.swift` — any web read requires `SearchProvenance`. No direct scraping of denied hosts.
6. `Jarvis/Sources/JarvisCore/Credentials/MapboxCredentials.swift` — Mapbox secret token is operator-tier only. Tiles use public token.
7. `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift`, `Oscillator/MasterOscillator.swift` — substrate you will feed and listen to, not replace.

**Mission framing:** "Same engine, different access layers." This is **not** an EMS app. It is a universal navigation engine whose access surface changes per tier. Responder role (EMR/EMT/AEMT/EMTP) gets EMS-preferred routing; Companion tier gets accessibility/parking/traffic; Operator tier gets full open-source fusion. The engine is tier-agnostic; policies gate output.

**Doctrine keywords:** open sources not dark sources. Gray not black. Empowerment not replacement.

---

## 1. Deliverables (in order)

### Phase A — `MapTileProvider` abstraction
- Protocol `MapTileProvider` with: `identifier`, `styleURL(for:Principal)`, `healthProbe() async -> TileProviderHealth`, `attribution`.
- Concrete: `MapboxTileProvider` (uses `MapboxCredentials.publicToken`), `MapLibreOSMTileProvider` (community OSM raster/vector fallback, no token required).
- `TileProviderOrchestrator` — primary + fallback; auto-demotes to fallback on N consecutive health-probe failures; audit-logs every switch; never fails-open into a non-registered host.
- **Canon gate:** every tile host must resolve to an entry in `OSINTSourceRegistry.canonical` (`osm.tiles`, `mapbox.tiles`). Add a compile-time or test-time assertion.

### Phase B — Routing engine core
- Protocol `RoutingProfile` with: `identifier`, `principalScope: Set<PrincipalCategory>`, `cost(edge:RouteEdge, context:RouteContext) -> Double`, `allow(edge:RouteEdge) -> Bool`.
- Engine `UniversalRouter` — takes `[RoutingProfile]` plus a road graph, returns ranked routes. Multi-profile composition (weighted sum with per-profile caps). Deterministic output for identical inputs (golden-file testable).
- Seed profiles:
  - `StandardAutoProfile` (baseline)
  - `AccessibilityProfile` (curb cuts, elevator entrances, handicap parking proximity) — Companion tier
  - `EMSPreferredProfile` — Responder tier only. Operator-teachable parameters (placeholders; do not hardcode agency-specific rules — leave `.taught` hook).
  - `ScenicProfile` (ties into recreation feeds; lowest priority)
- Every profile must read from registered sources only. Document data source per cost term.

### Phase C — OSINT adapters (actual HTTP, first wave)
Wire **these four** against `OSINTFetchGuard` — fail closed on any unlisted host, respect rate-limit hints, no user-agent spoofing:
1. `TxDOTDriveTexasAdapter` (`txdot.drivetexas`) — traffic events / closures / camera metadata.
2. `NASAFIRMSAdapter` (`firms.nasa`) — active fire detections (GeoJSON window).
3. `NOAAWeatherAdapter` (`noaa.nws`) — alerts by area/point.
4. `USGSEarthquakeAdapter` (`usgs.quake`) — recent seismic events.
Each adapter:
- Normalized output → `HazardOverlayFeature` (id, geometry, severity, source, observedAt, ttl).
- Pluggable cache with TTL honoring source guidance.
- Structured error type; never throws raw `URLError` to callers.
- Unit tests with fixture JSON (do not hit network in tests).

### Phase D — Scene pre-search pipeline (stub, not full)
- Protocol `ScenePreSearch` with `gather(destination: Coordinate, radius:CLLocationDistance, tier:Principal) async -> SceneBriefing`.
- Implementation wires `WebContentFetchPolicy` — takes a `SearchProvenance` injected by caller, honors robots/rate-limit envelope on the type.
- First implementation: returns only registered-API data (NPS/BLM/Recreation.gov/Wikipedia REST). Web-search fetch path left as `TODO` with clear integration point.

### Phase E — Anti-goals (do NOT build)
- No UI. No SwiftUI views. No CarPlay `CPMapTemplate`. No AR overlays. No Unity bridge. (Qwen owns all of that under UX-001.)
- No direct scrape of `roadsideamerica.com`, `ioverlander`, `campendium`, `thedyrt`, `alltrails`, `freecampsites`, or `strava` heatmap. See `OSINTSourceRegistry.deniedSources`.
- No "dark" OSINT (breach dumps, dox aggregators, social-scrape). Gray only.
- No clinical decision support surface. Even on Responder tier. Route and situational awareness only.

---

## 2. Interfaces you must NOT break

- `Principal` enum cases and `tierToken` encode/decode (existing round-trip tests must stay green).
- `CompanionCapabilityPolicy` voice + tunnel evaluation signatures.
- `OSINTSourceRegistry.canonical` membership checks (adding entries is fine; removing is not).
- `WebContentFetchPolicy` signature — you may add overloads, not replace.
- Canon-gate floor in `.github/workflows/canon-gate.yml` — you **will** bump both the comment (`# Floor: at least N tests`) and the `[ "$EXECUTED" -lt N ]` check with every green test-count increase. Do not land otherwise.

## 3. Tests — required shape

- Pure unit tests with fixtures. Do not touch the network in CI.
- For each adapter: happy-path + malformed-payload + rate-limit-hint + unlisted-host-attempt (must fail closed).
- For `UniversalRouter`: golden-route tests (small canned graphs) per profile; multi-profile composition sanity.
- For `TileProviderOrchestrator`: fallback triggers after N failures, returns to primary on recovery, every switch audit-logged.
- Add all new tests under `Jarvis/Tests/JarvisCoreTests/` and bump canon-gate floor once green.

## 4. Output format (your response goes here)

Write your response to `Construction/GLM/response/NAV-001-response.md` with sections:
1. **Design summary** (≤ 400 words). Name the abstractions. State what's tier-gated vs engine-core.
2. **File manifest** — every file you will create or modify, grouped by phase.
3. **Interface sketches** — Swift protocol/struct signatures only (no full bodies).
4. **Test matrix** — table: phase → test name → what it proves.
5. **Open questions** — anything in this spec you believe is wrong, ambiguous, or conflicts with existing canon. Cite file + line. Do not silently "fix" canon; flag it.
6. **Risk log** — at least five risks with mitigation. Include at least one data-source-policy risk and one performance/scale risk.
7. **Sequencing** — concrete PR plan (PR1 … PRn) small enough to land independently. Each PR ≤ ~500 net LOC, tests included.

## 5. Tone and standards

- Swift 5.9, `swift-format` defaults tolerated, no force-unwraps in new code.
- No third-party dependencies beyond what's already in `Package.swift` without explicit justification in your response.
- Every `struct`/`class` you introduce that crosses a tier boundary must carry a doc comment citing which tier consumes it and why.
- Comments only where they clarify — follow the house style (no narration).

---

**Final reminder:** we work in the gray, not the black. Open sources, search-surfaced reads, never scraping a denied host via a back door. If a data capability requires going dark, say so in Open Questions and stop.
