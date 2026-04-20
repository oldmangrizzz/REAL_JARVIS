# NAV-001 — Universal Navigation Engine (Unified Execution Spec)

**Target model:** GLM (z.ai / glm-5.1 or sibling, one fresh session)
**Parallel specs:** `Construction/Qwen/spec/UX-001-navigation-surfaces.md` (surfaces consume this engine; see §9), `Construction/DeepSeek/spec/VOICE-001-f5-tts-swap.md` (unrelated)
**Response path:** `Construction/GLM/response/NAV-001-response.md` — **one file, full source inline, no abbreviations**

---

## 0. Why this spec supersedes the prior roster

The earlier NAV-001 session delivered a 507-line design doc (accepted) and then crashed mid-PR1 without shipping any Swift. This unified spec folds design + all five executable PRs into a single drop so we get engine-core in one pass. The prior design doc and EXECUTE-PR1 spec are archived at `Construction/GLM/archive/` for reference only — **this file is the only live spec**.

Do **not** treat this as a plan to sequence. Ship everything below in one response.

---

## 1. What already exists in-tree (do NOT redefine)

Verify each by grep before you write anything that touches it.

| Symbol | Location | What it is |
|---|---|---|
| `Principal` | `Jarvis/Shared/Sources/JarvisShared/Principal.swift` | enum with cases `.operatorTier`, `.companion(memberID:)`, `.guestTier`, `.responder(role:)` |
| `ResponderRole` | same file | EMR/EMT/AEMT/EMTP + `certLevel: Int` |
| `MapboxCredentials` | `Jarvis/Sources/JarvisCore/Credentials/MapboxCredentials.swift` | `publicToken: String?`; `secretToken(for: Principal) -> String?` returns nil for non-operator |
| `OSINTSourceRegistry.canonical` | `Jarvis/Sources/JarvisCore/OSINT/OSINTSourceRegistry.swift` | already contains `mapbox.tiles` (hosts: `api.mapbox.com`, `events.mapbox.com`), `osm.tiles` (host: `tile.openstreetmap.org`), `txdot.drivetexas`, and more. Do not re-add. |
| `OSINTFetchGuard` | same file | `.authorize(url:principal:)` fail-closed gate for all network URLs |
| `OSINTSourceRegistry.deniedSources` | same file | static `[String: String]` — **do not modify** |
| `WebContentFetchPolicy` | `Jarvis/Sources/JarvisCore/OSINT/WebContentFetchPolicy.swift` | **do not modify** |
| `CompanionCapabilityPolicy` | `Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` | **do not modify** |
| Test runner | `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test`. Test target: `JarvisCoreTests`. Project is `xcodegen`-driven — `project.yml` is authoritative. |
| Canon floor | `.github/workflows/canon-gate.yml` currently pinned at **250** (both the `# Floor: …` comment and the `[ "$EXECUTED" -lt 250 ]` guard). Current live suite: **272 tests** passing. Bump floor in this PR to the new executed count. |
| No `AuditLog` type exists yet | — | Define a minimal protocol in `TileProviderOrchestrator.swift` with a stub in-memory impl. |
| No `RoadGraph` type exists yet | — | Define in this spec (§3 Phase B). |

---

## 2. Hard rules (inviolable)

1. **Swift 6, strict concurrency.** `Sendable` wherever data crosses actor boundaries. `actor` for mutable orchestrator state. No warnings allowed.
2. **No UI code.** No SwiftUI, no MapKit UI, no CoreLocation mutation, no CarPlay. Engine-core only. Qwen consumes this via protocol, surfaces are their turf.
3. **No real network in tests.** Every transport is protocol-injected. Unit tests use deterministic stubs driven by JSON fixtures.
4. **No real tokens committed.** `MapboxCredentials` already supports env + dotenv loading; do not inline any token text.
5. **No new third-party SwiftPM deps.** Stay inside what `Package.swift` has today.
6. **Fail-closed on unlisted hosts.** Every outbound URL constructed by the engine MUST pass through `OSINTFetchGuard.authorize(url:principal:)` before it is used. Tests assert this explicitly.
7. **Tier-gating is explicit.** `RoutingProfile.principalScope: Set<PrincipalCategory>` is an exhaustive allow-list, no default fallthrough.
8. **No clinical decision support, ever.** Responder-tier data is situational awareness, never diagnosis or treatment guidance. EMS profile routes *around* incidents; it does not tell medics what to do.
9. **Anti-goals — still off-limits:** no scraping denied hosts, no dark OSINT, no scraping behind a login wall, no breaking `robots.txt`.
10. **Canon-gate floor bump** happens **once, at the end of Phase E**, in the same response. Bump both the `# Floor:` comment and the `[ "$EXECUTED" -lt N ]` numeric to match the new executed count (which will be 272 + new tests).

---

## 3. Phase-by-phase file manifest

All Swift files live under `Jarvis/Sources/JarvisCore/Navigation/…`; all test files under `Jarvis/Tests/JarvisCoreTests/Navigation/…`; fixtures under `Jarvis/Tests/Fixtures/Navigation/…`. Create subdirectories as needed.

### Phase A — Tile providers + orchestrator

| Action | Path |
|---|---|
| Create | `Navigation/MapTileProvider.swift` |
| Create | `Navigation/MapboxTileProvider.swift` |
| Create | `Navigation/MapLibreOSMTileProvider.swift` |
| Create | `Navigation/TileProviderOrchestrator.swift` |
| Create | `Tests/Navigation/MapTileProviderTests.swift` (≥10 tests, see §5) |
| Create | `Fixtures/Navigation/tile_provider_health.json` |

### Phase B — Routing core

| Action | Path |
|---|---|
| Create | `Navigation/RoutingProfile.swift` |
| Create | `Navigation/RoadGraph.swift` (protocol + a tiny in-memory impl used only by tests; do **not** ship a production graph) |
| Create | `Navigation/UniversalRouter.swift` |
| Create | `Tests/Navigation/UniversalRouterTests.swift` (≥6 tests, goldens, see §5) |
| Create | `Fixtures/Navigation/route_graph_small.json` |
| Create | `Fixtures/Navigation/golden_routes_standard.json` |

### Phase C — Seed profiles

| Action | Path |
|---|---|
| Create | `Navigation/Profiles/StandardAutoProfile.swift` |
| Create | `Navigation/Profiles/AccessibilityProfile.swift` |
| Create | `Navigation/Profiles/EMSPreferredProfile.swift` |
| Create | `Navigation/Profiles/ScenicProfile.swift` |
| Create | `Tests/Navigation/RoutingProfilesTests.swift` (≥4 tests — tier-scope enforcement, golden per profile) |
| Create | `Fixtures/Navigation/golden_routes_ems.json` |
| Create | `Fixtures/Navigation/golden_routes_accessibility.json` |

### Phase D — OSINT hazard adapters

| Action | Path |
|---|---|
| Create | `Navigation/OSINT/HazardOverlayFeature.swift` (+ `HazardGeometry` enum: `.point(lat,lon)`, `.line([(lat,lon)])`, `.polygon([(lat,lon)])`) |
| Create | `Navigation/OSINT/HazardCache.swift` (actor, TTL-gated in-memory; **no disk**) |
| Create | `Navigation/OSINT/OSINTAdapterError.swift` |
| Create | `Navigation/OSINT/HazardAdapter.swift` (protocol; one `fetch(principal:) async throws -> [HazardOverlayFeature]`; URL built from `OSINTSourceRegistry.canonical`, passed through `OSINTFetchGuard`) |
| Create | `Navigation/OSINT/TxDOTDriveTexasAdapter.swift` |
| Create | `Navigation/OSINT/NASAFIRMSAdapter.swift` |
| Create | `Navigation/OSINT/NOAAWeatherAdapter.swift` |
| Create | `Navigation/OSINT/USGSEarthquakeAdapter.swift` |
| Create | `Tests/Navigation/HazardAdaptersTests.swift` (≥4 tests — one golden per adapter + one malformed-JSON fail-closed case) |
| Create | `Fixtures/Navigation/txdot_drivetexas.json` |
| Create | `Fixtures/Navigation/nasa_firms.json` |
| Create | `Fixtures/Navigation/noaa_weather.json` |
| Create | `Fixtures/Navigation/usgs_earthquake.json` |
| Create | `Fixtures/Navigation/malformed_osint.json` |

`NASAFIRMSAdapter`, `NOAAWeatherAdapter`, `USGSEarthquakeAdapter` require registry entries — if not already in `OSINTSourceRegistry.canonical`, add them with attribution/license/homepage/rate-limit hint and justify each addition in the response (2–3 sentences). Confirm via grep first; `txdot.drivetexas` is already present.

### Phase E — ScenePreSearch + wiring + canon-gate bump

| Action | Path |
|---|---|
| Create | `Navigation/SceneBriefing.swift` |
| Create | `Navigation/ScenePreSearch.swift` (protocol + default impl fanning out to hazard adapters per tier) |
| Create | `Tests/Navigation/ScenePreSearchTests.swift` (≥3 tests — one per non-guest tier + one guest-denied case) |
| Create | `Fixtures/Navigation/scene_briefing_nps.json` |
| Modify | `.github/workflows/canon-gate.yml` — bump `# Floor:` comment AND `[ "$EXECUTED" -lt N ]` to new executed count |
| Modify | `obsidian/knowledge/codebase/CODEBASE_MAP.md` — add a Navigation row pointing at the new module tree |
| Create | `obsidian/knowledge/codebase/modules/Navigation.md` — module wiki page (what it is, public protocols, tier gating, OSINT sources used, parallel-track notes) |

Do **not** wire into `JarvisRuntime` in this PR. The engine stands alone; runtime wiring is a follow-up ticket after surfaces (Qwen) land.

---

## 4. Interface contracts (type shapes — Qwen consumes these)

```swift
// Phase A

public protocol MapTileProvider: Sendable {
    var identifier: String { get }          // registry key: "mapbox.tiles" | "osm.tiles"
    var attribution: String { get }
    func styleURL(for principal: Principal) throws -> URL
    func healthProbe() async -> TileProviderHealth
}

public enum TileProviderHealth: Sendable, Equatable {
    case healthy
    case degraded(reason: String)
    case unhealthy(reason: String)
}

public enum TileProviderError: Error, Sendable, Equatable {
    case hostNotRegistered(String)
    case unauthorizedTier(Principal)
    case allProvidersUnhealthy([String])     // provider identifiers
}

public actor TileProviderOrchestrator {
    public init(primary: any MapTileProvider,
                fallback: any MapTileProvider,
                registry: OSINTSourceRegistry = .canonical,
                failureThreshold: Int = 3,
                auditLog: any AuditLog = InMemoryAuditLog()) throws
    public func currentProvider() -> any MapTileProvider
    public func probe() async
    public func forcePrimaryRecovery() async -> Bool
}

public protocol AuditLog: Sendable {
    func record(_ entry: AuditEntry) async
}
public struct AuditEntry: Sendable, Equatable {
    public let at: Date
    public let kind: String     // "tile.switch.primary_to_fallback" etc.
    public let detail: String
}
public actor InMemoryAuditLog: AuditLog { public init(); public var entries: [AuditEntry] { get } ; public func record(_:) }

// Phase B

public enum PrincipalCategory: String, Sendable, Hashable {
    case grizz, companion, guest, responder
    public static func of(_ p: Principal) -> PrincipalCategory
}

public protocol RoutingProfile: Sendable {
    var identifier: String { get }
    var principalScope: Set<PrincipalCategory> { get }
    func edgeWeight(_ edge: RouteEdge, context: RoutingContext) -> Double
}

public struct RouteEdge: Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let fromNode: String
    public let toNode: String
    public let lengthMeters: Double
    public let maxSpeedKPH: Double?
    public let attributes: [String: String]   // "highway":"motorway", "accessibility":"ramp", etc.
}

public protocol RoadGraph: Sendable {
    func edge(id: String) -> RouteEdge?
    func neighbors(of node: String) -> [RouteEdge]
}

public struct RoutingContext: Sendable {
    public let principal: Principal
    public let activeHazards: [HazardOverlayFeature]
    public let requestedAt: Date
}

public struct Route: Sendable, Equatable, Codable {
    public let edgeIDs: [String]
    public let totalCostWeighted: Double
    public let totalLengthMeters: Double
    public let profileIdentifier: String
}

public struct UniversalRouter: Sendable {
    public init(graph: any RoadGraph)
    public func routes(from: String, to: String,
                       profiles: [any RoutingProfile],
                       context: RoutingContext,
                       limit: Int = 3) throws -> [Route]  // deterministic order
}

// Phase D

public struct HazardOverlayFeature: Sendable, Equatable, Codable, Hashable {
    public let id: String
    public let sourceKey: String          // OSINTSourceRegistry key
    public let category: HazardCategory
    public let severity: HazardSeverity   // .info | .elevated | .critical
    public let geometry: HazardGeometry
    public let observedAt: Date
    public let ttl: TimeInterval
    public let summary: String
}

public enum HazardCategory: String, Sendable, Codable { case traffic, fire, weather, seismic, other }
public enum HazardSeverity: String, Sendable, Codable { case info, elevated, critical }
public enum HazardGeometry: Sendable, Equatable, Hashable, Codable {
    case point(lat: Double, lon: Double)
    case line([LatLon])
    case polygon([LatLon])
}
public struct LatLon: Sendable, Equatable, Hashable, Codable { public let lat, lon: Double }

public protocol HazardAdapter: Sendable {
    var sourceKey: String { get }
    func fetch(principal: Principal) async throws -> [HazardOverlayFeature]
}

public actor HazardCache {
    public init(ttl: TimeInterval = 300)
    public func get(_ key: String) -> [HazardOverlayFeature]?
    public func put(_ key: String, _ value: [HazardOverlayFeature])
}

public enum OSINTAdapterError: Error, Sendable, Equatable {
    case hostNotAuthorized(String)
    case malformedPayload(String)
    case transportFailed(String)
}

// Phase E

public struct SceneBriefing: Sendable, Equatable, Codable {
    public let requestedAt: Date
    public let principal: Principal
    public let hazards: [HazardOverlayFeature]
    public let nearbyLayers: [String]          // registry keys present in briefing
    public let summary: String
}

public protocol ScenePreSearch: Sendable {
    func gather(principal: Principal, near: LatLon, radiusMeters: Double) async throws -> SceneBriefing
}
```

Transports must be protocol-injected throughout; define `TileTransport` and `HazardTransport` (shape: `func fetch(URLRequest) async throws -> Data`) so tests drop in stubs. Production transports are thin `URLSession` wrappers.

---

## 5. Test matrix (hermetic, no network)

Bare minimum counts, all must be executed in `JarvisCoreTests`:

**Phase A — `MapTileProviderTests` (≥10):**
1. `testMapboxProviderUsesPublicToken` — stubbed credentials; secret token closure is never called.
2. `testMapboxStyleURLHost` — URL host is `api.mapbox.com`.
3. `testOSMProviderNoCredentialsRequired`.
4. `testOSMProviderUserAgentSet` — default UA is non-empty and identifies Real Jarvis.
5. `testOrchestratorUsesPrimaryWhenHealthy`.
6. `testOrchestratorDemotesAfterNFailures` — threshold=3, stubbed transport returns unhealthy.
7. `testOrchestratorRecoversWhenPrimaryReturns` — after demotion, primary goes healthy for 3 consecutive probes → switch back.
8. `testOrchestratorBothProvidersUnhealthyRaises` — `TileProviderError.allProvidersUnhealthy`.
9. `testOrchestratorCanonGateRejectsUnregisteredHost` — construct a provider reporting `identifier="roadsideamerica.com"` → init throws `.hostNotRegistered`.
10. `testOrchestratorAuditsEverySwitch` — in-memory audit log receives one `tile.switch.*` entry per transition.

**Phase B — `UniversalRouterTests` (≥6):**
1. `testRouterDeterministicOrdering` — same inputs → byte-equal `Route` array across two calls.
2. `testRouterShortestStandardProfile` — golden from `golden_routes_standard.json`.
3. `testRouterProfileScopeRejectsWrongTier` — passing `EMSPreferredProfile` with `.companion` principal throws or is silently dropped per exhaustive switch.
4. `testRouterRespectsActiveHazards` — edge with a `.critical` hazard in `activeHazards` gets repelled (weight ≫ baseline).
5. `testRouterReturnsEmptyWhenNoPath`.
6. `testRouterLimitBounds` — `limit: 1` returns ≤ 1 route.

**Phase C — `RoutingProfilesTests` (≥4):**
1. `testStandardAutoAllTiers` — scope contains all four categories.
2. `testEMSPreferredResponderOnly` — scope is exactly `[.responder]`.
3. `testAccessibilityCompanionAndResponder`.
4. `testScenicExcludesHighways` — edges with `highway=motorway` carry heavy penalty vs secondary.

**Phase D — `HazardAdaptersTests` (≥5):**
1. `testTxDOTAdapterParsesGolden`.
2. `testFIRMSAdapterParsesGolden`.
3. `testNOAAAdapterParsesGolden`.
4. `testUSGSAdapterParsesGolden`.
5. `testAdapterFailsClosedOnMalformedPayload` — `malformed_osint.json` → `OSINTAdapterError.malformedPayload`.
6. (bonus) `testAdapterRejectsUnauthorizedHost` — override transport to return a URL whose host isn't in the registry → `OSINTFetchGuard` throws, adapter surfaces `.hostNotAuthorized`.

**Phase E — `ScenePreSearchTests` (≥3):**
1. `testOperatorTierGetsFullFusion` — briefing includes traffic + fire + weather + seismic layers.
2. `testCompanionTierExcludesSeismic` (or equivalent tier-depth rule — document your chosen policy in the module wiki).
3. `testResponderTierGetsEMSRelevant`.
4. (bonus) `testGuestTierReturnsEmptyBriefing`.

New executed count ≈ 272 (current) + ~28 new = **~300**. Bump canon-gate floor to the **actual** executed number your local run reports — do not round, do not pad.

---

## 6. Response shape (verbatim section order)

Write `Construction/GLM/response/NAV-001-response.md` with exactly these sections, in order:

1. **Summary** — one paragraph: what landed, test count delta, why operator can merge.
2. **File manifest** — path / purpose / LOC for every file (Phase A–E).
3. **Registry additions** — if you added NOAA / FIRMS / USGS to `OSINTSourceRegistry.canonical`, show the exact diff and justify each in 1–2 sentences.
4. **Full file contents** — every `.swift` and `.json` inline, fenced ```` ```swift ```` / ```` ```json ````. **No abbreviations, no `// ...`, no "same as above" references.** Operator copy-pastes top to bottom.
5. **Canon-gate diff** — the `.github/workflows/canon-gate.yml` change (before/after) with the new floor number.
6. **Wiki diffs** — `CODEBASE_MAP.md` row addition + new `modules/Navigation.md` page, inline.
7. **Test matrix table** — test name → phase → what it proves → runs hermetic (yes/no). All must say yes.
8. **Local verification commands**:
   ```
   xcodegen generate
   xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
     -destination 'platform=macOS,arch=arm64' test 2>&1 | tail -10
   ```
9. **Canon-clean checklist** (every box ticked):
   - [ ] No UI code anywhere
   - [ ] No real tokens committed
   - [ ] No real network calls in tests
   - [ ] Swift 6 strict-concurrency clean (zero warnings)
   - [ ] `Principal` / `CompanionCapabilityPolicy` / `WebContentFetchPolicy` / `OSINTSourceRegistry.deniedSources` untouched
   - [ ] All outbound URLs go through `OSINTFetchGuard.authorize`
   - [ ] Canon-gate `# Floor:` comment and `[ "$EXECUTED" -lt N ]` numeric both updated to the same new value
   - [ ] Wiki page `modules/Navigation.md` + `CODEBASE_MAP.md` row added
10. **Test-count delta** — integer: new executed tests added.
11. **Handoff notes for Qwen** — anything in the protocol contracts they should pin against.
12. **Open questions** — anything that blocks full ship. Do not silently work around canon; surface it and we rule.

---

## 7. Out of scope (do NOT ship)

- No `JarvisRuntime` wiring — engine is standalone this PR.
- No Pheromind / oscillator integration — separate cross-cutting PR later.
- No CarPlay, no AR, no SwiftUI surfaces — Qwen's track.
- No voice I/O — DeepSeek's track.
- No persistence of taught parameters — in-memory `[String: Double]` only for EMS profile, `// CANON: operator-teachable; persistence ticket pending`.
- No production road graph — ship `RoadGraph` protocol + tiny in-memory test impl only. Real graph is a downstream ticket.

---

## 8. Doctrine refresher (tattoo this before coding)

- **Engine-core is tier-agnostic.** Tiers enter through `RoutingProfile.principalScope` and `ScenePreSearch.gather(principal:)`. Nowhere else.
- **Every network URL is registry-pinned.** No exceptions. `OSINTFetchGuard` is the chokepoint.
- **Fail closed.** Unknown host → throw. Malformed payload → throw. Unknown tier → no data.
- **Deterministic routing.** Identical inputs produce byte-equal `Route` outputs. Golden files are real contracts.
- **Audit every tile switch.** Silent demotion is an incident, not a feature.
- **No clinical surfaces.** Responder tier is situational awareness, period.
- **Open sources only — gray, not black.** If the source isn't in the registry, it doesn't exist to us.

---

## 9. Parallel tracks (do not touch their files)

- **Qwen — `UX-001`** owns all navigation surfaces (`NavigationCockpitView`, `CarPlayNavigationScene`, PWA, Unity). Qwen consumes `MapTileProvider`, `HazardOverlayFeature`, `SceneBriefing`, `RoutingProfile` as opaque protocol/struct types. Keep those shapes **frozen** once this ships. Qwen UX-001-A1 (design tokens) already merged.
- **DeepSeek — `VOICE-001`** owns F5-TTS swap (`services/f5-tts/`). Unrelated; ignore.

If you need to change a contract that Qwen consumes, surface it in **§12 Open questions**, do not silently alter it.

---

## 10. Greenlight

Ship Phases A–E inline in one response. One merge. Engine-core complete. Qwen surfaces unblock on merge.

*Spec authored 2026-04-20. Archived predecessors at `Construction/GLM/archive/`.*
