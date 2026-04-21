# NAV-001 — Universal Navigation Engine (GLM Response)

**Responding to:** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md`
**Canon-floor status:** 35 existing test files, 0 Navigation/Map/Routing tests. Floor comment says 250; error message says 213 — flagged below.

---

## 1. Design Summary

The Universal Navigation Engine introduces five core abstractions organized into a tier-agnostic engine core and tier-gated policy surfaces:

**Engine-core (tier-agnostic):**
- `MapTileProvider` — protocol for tile source abstraction; concrete `MapboxTileProvider` and `MapLibreOSMTileProvider`.
- `TileProviderOrchestrator` — primary/fallback coordinator with auto-demotion on consecutive health-probe failures; audit-logs every switch; canon-gates tile hosts against `OSINTSourceRegistry.canonical`.
- `UniversalRouter` — deterministic routing engine consuming `[RoutingProfile]` and a road graph. Returns ranked routes via weighted multi-profile composition. Golden-file testable: identical inputs yield identical outputs.
- `HazardOverlayFeature` — normalized hazard representation (id, geometry, severity, source, observedAt, ttl) produced by OSINT adapters and consumed by profiles and ScenePreSearch.

**Tier-gated surfaces:**
- `RoutingProfile.principalScope: Set<PrincipalCategory>` gates which tiers see which profile. `EMSPreferredProfile` is responder-only; `AccessibilityProfile` is companion+responder; `StandardAutoProfile` and `ScenicProfile` are all-tiers.
- `ScenePreSearch.gather(tier:)` returns tier-appropriate `SceneBriefing` depth: operator gets full OSINT fusion, companion gets accessibility/parking, responder gets EMS-relevant hazards only, guest gets read-only base map context.
- `MapboxTileProvider` uses `MapboxCredentials.publicToken` for all tiers; secret token never leaves operator-tier code paths.

**Cognitive-architecture alignment:** Navigation is a consumer of salience. Route-quality feedback deposits to the `PheromindEngine` (e.g., `TernarySignal.repel` for hazard-blocked edges, `.reinforce` for confirmed clear corridors). Navigation components subscribe to `MasterOscillator` via `PhaseLockedSubscriber` for periodic health probes and cache TTL refresh — event+edge+threshold, not request+response+return.

**Anti-goals enforced:** No UI, no CarPlay, no AR, no SwiftUI views. No denied-host scraping. No dark OSINT. No clinical decision support. Fail-closed on unlisted hosts.

---

## 2. File Manifest

### Phase A — MapTileProvider + Orchestrator

| Action | Path |
|--------|------|
| Create | `Jarvis/Sources/JarvisCore/Navigation/MapTileProvider.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/MapboxTileProvider.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/MapLibreOSMTileProvider.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/TileProviderOrchestrator.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/MapTileProviderTests.swift` |
| Create | `Jarvis/Tests/Fixtures/Navigation/tile_provider_health.json` |
| Modify | `.github/workflows/canon-gate.yml` — bump floor |

### Phase B — Routing Engine

| Action | Path |
|--------|------|
| Create | `Jarvis/Sources/JarvisCore/Navigation/RoutingProfile.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/UniversalRouter.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/Profiles/StandardAutoProfile.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/Profiles/AccessibilityProfile.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/Profiles/EMSPreferredProfile.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/Profiles/ScenicProfile.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/UniversalRouterTests.swift` |
| Create | `Jarvis/Tests/Fixtures/Navigation/route_graph_small.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/golden_routes_standard.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/golden_routes_ems.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/golden_routes_accessibility.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/golden_routes_multi_composite.json` |
| Modify | `.github/workflows/canon-gate.yml` — bump floor |

### Phase C — OSINT Adapters

| Action | Path |
|--------|------|
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/HazardOverlayFeature.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/OSINTAdapterError.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/HazardCache.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/TxDOTDriveTexasAdapter.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/NASAFIRMSAdapter.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/NOAAWeatherAdapter.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/OSINT/USGSEarthquakeAdapter.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/TxDOTDriveTexasAdapterTests.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/NASAFIRMSAdapterTests.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/NOAAWeatherAdapterTests.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/USGSEarthquakeAdapterTests.swift` |
| Create | `Jarvis/Tests/Fixtures/Navigation/txdot_drivetexas.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/nasa_firms.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/noaa_weather.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/usgs_earthquake.json` |
| Create | `Jarvis/Tests/Fixtures/Navigation/malformed_osint.json` |
| Modify | `.github/workflows/canon-gate.yml` — bump floor |

### Phase D — ScenePreSearch

| Action | Path |
|--------|------|
| Create | `Jarvis/Sources/JarvisCore/Navigation/ScenePreSearch.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/SceneBriefing.swift` |
| Create | `Jarvis/Sources/JarvisCore/Navigation/RegisteredAPIScenePreSearch.swift` |
| Create | `Jarvis/Tests/JarvisCoreTests/Navigation/ScenePreSearchTests.swift` |
| Create | `Jarvis/Tests/Fixtures/Navigation/scene_briefing_nps.json` |
| Modify | `.github/workflows/canon-gate.yml` — final bump |

---

## 3. Interface Sketches

```swift
// MARK: - Phase A

/// Tier-agnostic tile source. Concrete providers determine style URL
/// and credential requirements per principal tier.
public protocol MapTileProvider: Sendable {
    var identifier: String { get }
    var attribution: String { get }
    func styleURL(for principal: Principal) -> URL?
    func healthProbe() async -> TileProviderHealth
}

public struct TileProviderHealth: Equatable, Sendable {
    public let providerID: String
    public let isHealthy: Bool
    public let latencyMs: Double
    public let checkedAt: Date
    public let consecutiveFailures: Int
}

/// Consumed by: all tiers. Orchestrates primary/fallback tile providers
/// with auto-demotion and audit logging. Canon-gates hosts against
/// OSINTSourceRegistry.canonical.
public final class TileProviderOrchestrator: Sendable {
    public init(
        primary: MapTileProvider,
        fallback: MapTileProvider,
        registry: OSINTSourceRegistry,
        demotionThreshold: Int,
        auditLog: AuditLogSink
    )
    public var activeProvider: MapTileProvider { get }
    public func styleURL(for principal: Principal) -> URL?
    public func healthProbe() async -> TileProviderHealth
    public func forcePrimaryRecovery() async -> Bool
}

/// Consumed by: all tiers. Uses MapboxCredentials.publicToken only.
/// Secret token never accessed.
public struct MapboxTileProvider: MapTileProvider, Sendable {
    public init(credentials: MapboxCredentials)
}

/// Consumed by: all tiers. No token required. Fallback for when
/// Mapbox is degraded or unavailable.
public struct MapLibreOSMTileProvider: MapTileProvider, Sendable {
    public init()
}

// MARK: - Phase B

/// Categorization for profile scoping without coupling to Principal enum internals.
public enum PrincipalCategory: String, Sendable {
    case operatorTier
    case companion
    case guest
    case responder
}

public extension Principal {
    var category: PrincipalCategory { get }
}

/// A single cost/allowance model for route edges. Engine-core: tier-agnostic
/// logic; principalScope gates tier visibility.
public protocol RoutingProfile: Sendable {
    var identifier: String { get }
    var principalScope: Set<PrincipalCategory> { get }
    func cost(edge: RouteEdge, context: RouteContext) -> Double
    func allow(edge: RouteEdge) -> Bool
}

public struct RouteEdge: Equatable, Sendable, Codable {
    public let id: String
    public let source: String
    public let target: String
    public let baseCost: Double
    public let metadata: [String: Double]
}

public struct RouteContext: Sendable {
    public let principal: Principal
    public let hazards: [HazardOverlayFeature]
    public let pheromoneHint: Double?
}

public struct RankedRoute: Equatable, Sendable {
    public let edges: [RouteEdge]
    public let totalCost: Double
    public let profileWeights: [String: Double]
}

/// Tier-agnostic deterministic routing engine. Multi-profile weighted
/// composition with per-profile cost caps. Identical inputs yield
/// identical outputs (golden-file testable).
public struct UniversalRouter: Sendable {
    public init(
        profiles: [RoutingProfile],
        profileWeights: [String: Double]? // nil = equal weight
    )
    public func route(
        from source: String,
        to target: String,
        graph: [RouteEdge],
        context: RouteContext
    ) -> [RankedRoute]
}

/// Consumed by: all tiers. Baseline driving cost model.
public struct StandardAutoProfile: RoutingProfile, Sendable {
    public init()
}

/// Consumed by: companion + responder tiers. Adjusts cost for
/// curb-cut, elevator, handicap-parking proximity.
/// Data source: OSM Overpass (osm.overpass) waypoint metadata.
public struct AccessibilityProfile: RoutingProfile, Sendable {
    public init()
}

/// Consumed by: responder tier only. Operator-teachable parameters
/// via .taught hook — no hardcoded agency-specific rules.
/// Data sources: txdot.drivetexas, firms.nasa, noaa.nws, usgs.quake.
public struct EMSPreferredProfile: RoutingProfile, Sendable {
    public var taughtParameters: [String: Double]
    public init(taughtParameters: [String: Double] = [:])
}

/// Consumed by: all tiers. Lowest priority profile. Ties into
/// recreation feeds for scenic corridor preference.
/// Data source: nps.api, osm.overpass tourism=* tags.
public struct ScenicProfile: RoutingProfile, Sendable {
    public init()
}

// MARK: - Phase C

/// Normalized hazard representation crossing OSINT adapter → router/profile boundary.
/// Consumed by: all tiers via profile cost adjustments and ScenePreSearch.
public struct HazardOverlayFeature: Equatable, Sendable, Codable {
    public let id: String
    public let geometry: HazardGeometry
    public let severity: HazardSeverity
    public let source: String // OSINTSource.key
    public let observedAt: Date
    public let ttl: TimeInterval
}

public enum HazardGeometry: Equatable, Sendable, Codable {
    case point(latitude: Double, longitude: Double)
    case polygon(coordinates: [(lat: Double, lon: Double)])
    case line(coordinates: [(lat: Double, lon: Double)])
}

public enum HazardSeverity: String, Equatable, Sendable, Codable {
    case informational
    case advisory
    case warning
    case critical
}

/// Structured error from OSINT adapters. Never exposes raw URLError to callers.
public enum OSINTAdapterError: Error, Equatable, CustomStringConvertible {
    case fetchDenied(host: String, reason: String)
    case sourceNotFound(key: String)
    case malformedPayload(source: String, detail: String)
    case rateLimitExceeded(source: String, retryAfter: TimeInterval?)
    case cacheExpired(source: String)
    case networkUnavailable(source: String)
}

/// Pluggable TTL cache for hazard features. Subscribes to MasterOscillator
/// for periodic eviction.
public final class HazardCache: PhaseLockedSubscriber, Sendable {
    public var subscriberID: String { get }
    public init(ttlDefault: TimeInterval, maxEntries: Int)
    public func insert(_ feature: HazardOverlayFeature)
    public func features(inRegion: HazardGeometry, minSeverity: HazardSeverity?) -> [HazardOverlayFeature]
    public func onTick(_ tick: OscillatorTick)
}

/// Consumed by: all tiers. Respects OSINTFetchGuard — fail-closed on unlisted host.
public protocol OSINTHazardAdapter: Sendable {
    var sourceKey: String { get }
    func fetch(
        region: HazardGeometry,
        principal: Principal,
        guard: OSINTFetchGuard
    ) async -> Result<[HazardOverlayFeature], OSINTAdapterError>
}

public struct TxDOTDriveTexasAdapter: OSINTHazardAdapter, Sendable {
    public init(cache: HazardCache, fetchGuard: OSINTFetchGuard)
}

public struct NASAFIRMSAdapter: OSINTHazardAdapter, Sendable {
    public init(cache: HazardCache, fetchGuard: OSINTFetchGuard)
}

public struct NOAAWeatherAdapter: OSINTHazardAdapter, Sendable {
    public init(cache: HazardCache, fetchGuard: OSINTFetchGuard)
}

public struct USGSEarthquakeAdapter: OSINTHazardAdapter, Sendable {
    public init(cache: HazardCache, fetchGuard: OSINTFetchGuard)
}

// MARK: - Phase D

/// Consumed by: all tiers (depth varies by tier). Pre-search gathers
/// scene context for a destination. Wires WebContentFetchPolicy with
/// SearchProvenance.
public protocol ScenePreSearch: Sendable {
    func gather(
        destination: Coordinate,
        radius: CLLocationDistance,
        tier: Principal
    ) async -> SceneBriefing
}

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

/// Tier-shaped briefing. Operator gets full depth; companion gets
/// accessibility/parking; responder gets EMS hazards; guest gets base map.
public struct SceneBriefing: Equatable, Sendable {
    public let destination: Coordinate
    public let hazards: [HazardOverlayFeature]
    public let poiSummary: [POISummary]
    public let accessibilityNotes: [String]?
    public let sourceProvenances: [SearchProvenance]
}

public struct POISummary: Equatable, Sendable, Codable {
    public let name: String
    public let category: String
    public let source: String
    public let coordinate: Coordinate
}

/// First implementation: registered-API-only data from NPS/BLM/Recreation.gov/
/// Wikipedia REST. Web-search fetch path left as TODO.
public struct RegisteredAPIScenePreSearch: ScenePreSearch, Sendable {
    public init(
        adapters: [OSINTHazardAdapter],
        webPolicy: WebContentFetchPolicy,
        registry: OSINTSourceRegistry
    )
}

// MARK: - Pheromind Integration

/// Navigation deposits route-quality feedback to the pheromind field.
/// Consumed by: engine-core (not tier-gated).
public struct NavigationPheromoneDeposit {
    public static func routeQualityDeposit(
        edge: EdgeKey,
        routeSuccess: Bool,
        hazardCount: Int
    ) -> PheromoneDeposit
}

/// Audit log sink for TileProviderOrchestrator switches.
public protocol AuditLogSink: Sendable {
    func log(event: String, details: [String: String])
}
```

---

## 4. Test Matrix

| Phase | Test Name | What It Proves |
|-------|-----------|----------------|
| A | `testMapboxTileProviderReturnsStyleURLForAllTiers` | MapboxTileProvider vends style URL using publicToken for every Principal tier |
| A | `testMapboxTileProviderNeverExposesSecretToken` | Secret token is never referenced; only publicToken flows through style URLs |
| A | `testMapLibreOSMTileProviderNeedsNoToken` | OSM provider returns valid style URL without any credentials |
| A | `testOrchestratorStartsOnPrimary` | TileProviderOrchestrator defaults to primary provider |
| A | `testOrchestratorDemotesAfterConsecutiveFailures` | N consecutive health-probe failures auto-demotes to fallback |
| A | `testOrchestratorRecoversToPrimary` | forcePrimaryRecovery succeeds when primary health probe is healthy again |
| A | `testOrchestratorAuditLogsSwitch` | Every provider switch emits an audit log entry |
| A | `testOrchestratorCanonGateRejectsUnregisteredHost` | Tile host not in OSINTSourceRegistry.canonical is rejected at init |
| A | `testOrchestratorCanonGateAllowsRegisteredHosts` | osm.tiles and mapbox.tiles hosts pass the canon gate |
| B | `testStandardAutoProfileCostIsBaseline` | StandardAutoProfile cost equals baseCost on simple edges |
| B | `testAccessibilityProfileReducesCurbCutEdgeCost` | Curb-cut metadata lowers cost; non-accessible edges stay base |
| B | `testEMSPreferredProfileExcludesResponderOnly` | EMSPreferredProfile.principalScope is responder-only |
| B | `testEMSPreferredProfileTaughtParametersOverrideCost` | .taught hook parameters override default cost weights |
| B | `testScenicProfileLowestPriority` | ScenicProfile cost delta is smallest among all profiles |
| B | `testUniversalRouterDeterministicGoldenFile` | Same graph + profiles + context = same ranked routes (golden-file) |
| B | `testUniversalRouterMultiProfileWeightedComposition` | Weighted sum with per-profile caps produces correct composite cost |
| B | `testUniversalRouterRejectsDeniedEdges` | Edges where `allow()` returns false are excluded from all routes |
| B | `testUniversalRouterEmptyGraphReturnsEmpty` | No edges → no routes (deterministic empty result) |
| B | `testProfilePrincipalScopeExcludesUnauthorizedTiers` | Profiles not in principal's scope don't contribute to route cost |
| C | `testTxDOTAdapterHappyPath` | Fixture JSON decodes to correct HazardOverlayFeature array |
| C | `testNASAFIRMSAdapterHappyPath` | FIRMS GeoJSON normalizes to features with .hazards category |
| C | `testNOAAWeatherAdapterHappyPath` | NWS alerts decode with correct severity mapping |
| C | `testUSGSEarthquakeAdapterHappyPath` | USGS quake feed decodes with .seismic category |
| C | `testTxDOTAdapterMalformedPayload` | Malformed JSON returns .malformedPayload, not a crash |
| C | `testNASAFIRMSAdapterMalformedPayload` | Malformed FIRMS data returns .malformedPayload |
| C | `testNOAAAdapterMalformedPayload` | Bad NWS response returns .malformedPayload |
| C | `testUSGSAdapterMalformedPayload` | Bad USGS response returns .malformedPayload |
| C | `testAdapterUnlistedHostFailClosed` | URL to unregistered host returns .fetchDenied (fail-closed) |
| C | `testAdapterRateLimitHintHonored` | Rate-limit guidance from OSINTSource is respected in cache TTL |
| C | `testHazardCacheInsertAndEvict` | Cache stores and TTL-evicts features correctly |
| C | `testHazardCacheOnTickEviction` | MasterOscillator tick triggers TTL expiration sweep |
| C | `testAdapterNoRawURLErrorExposed` | Error type is always OSINTAdapterError, never URLError |
| D | `testScenePreSearchReturnsRegisteredAPIDataOnly` | RegisteredAPIScenePreSearch returns only data from registered APIs |
| D | `testScenePreSearchNoProvenanceFailsClosed` | Missing SearchProvenance → WebContentFetchPolicy denies the read |
| D | `testScenePreSearchOperatorDepthFull` | Operator tier gets full hazard + POI briefing |
| D | `testScenePreSearchCompanionDepthAccessibility` | Companion tier gets accessibility notes + parking, no EMS specifics |
| D | `testScenePreSearchResponderDepthEMS` | Responder tier gets EMS hazards, no scenic/recreation data |
| D | `testScenePreSearchGuestDepthReadOnly` | Guest tier gets minimal base-map POI only |
| D | `testScenePreSearchDeniedSourceNeverFetched` | Denied hosts (roadsideamerica, etc.) never appear in results |

---

## 5. Open Questions

### OQ-1: canon-gate.yml floor comment vs error message mismatch
**File:** `.github/workflows/canon-gate.yml`, lines 45 vs 53.
**Issue:** The comment on line 45 says `# Floor: at least 250 tests`. The error message on line 53 says `Expected >= 213 tests`. These disagree. Spec NAV-001 line 7 and canon context both say 250. Which number is canonical? We will bump whichever is the actual floor, but this must be resolved before merge to avoid a false-negative gate failure or a too-permissive gate.

### OQ-2: RouteEdge road graph source not specified
**File:** `NAV-001-universal-navigation-engine.md`, Phase B.
**Issue:** The spec says UniversalRouter "takes `[RoutingProfile]` plus a road graph" but does not specify how the road graph is populated. Is this an OSM Overpass snapshot? A Mapbox Directions API response? A static bundled graph? The `RouteEdge` struct we define must come from somewhere. We assume the graph is provided externally (caller-supplied) for now — the router is graph-agnostic — but a production graph source needs a spec decision.

### OQ-3: EMSPreferredProfile .taught hook storage and lifecycle
**File:** `NAV-001-universal-navigation-engine.md`, line 43.
**Issue:** "Operator-teachable parameters (placeholders; do not hardcode agency-specific rules — leave `.taught` hook)" is clear on what NOT to do but ambiguous on persistence. Should `taughtParameters` survive process restarts? If so, where? Obsidian vault? A separate JSON? We implement as an in-memory `[String: Double]` dict for now with a clear TODO for persistence, but this needs canonical clarification.

### OQ-4: TileProviderOrchestrator canon-gate enforcement timing
**File:** `NAV-001-universal-navigation-engine.md`, line 35.
**Issue:** "Add a compile-time or test-time assertion" — Swift cannot do true compile-time host checking without a macro or build-phase script. We implement this as a test-time assertion (XCTestAssert in `TileProviderOrchestrator` init that both primary and fallback `identifier` values resolve to `OSINTSourceRegistry.canonical` sources). If compile-time enforcement is desired, a separate build-phase script (e.g., a `swift-syntax` linter) would need to be added. Flagging for spec clarification.

### OQ-5: OSINTAdapter fetch method needs URL construction protocol
**File:** `NAV-001-universal-navigation-engine.md`, Phase C.
**Issue:** `OSINTFetchGuard.authorize(url:principal:)` requires a URL, but adapters need to construct request URLs from the `OSINTSourceRegistry.canonical` endpoint hosts + query parameters. The spec doesn't specify whether adapters should construct URLs first and then pass them to the guard, or if the guard should provide URL construction assistance. We have adapters construct URLs from registry endpoint hosts, then pass to the guard — but if `OSINTSourceRegistry.canonical` changes an endpoint host, the adapter must be updated in lockstep. This coupling is worth noting.

### OQ-6: HazardOverlayFeature.geometry definition precision
**File:** `NAV-001-universal-navigation-engine.md`, line 54.
**Issue:** The spec says "geometry" for `HazardOverlayFeature` but doesn't constrain the type. GeoJSON supports Point, LineString, Polygon, MultiPolygon, etc. We define a `HazardGeometry` enum with `.point`, `.line`, `.polygon` — sufficient for all four adapters' output shapes. If future adapters produce MultiPolygon or GeometryCollection, this enum will need extension.

---

## 6. Risk Log

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | **Data-source-policy: OSINT host changes break adapter URLs.** OSINTSourceRegistry pins endpoint hosts (e.g., `earthquake.usgs.gov`). If USGS changes their API domain, the guard will fail-closed and the adapter returns no data. | Medium | High — silent loss of hazard overlays during active incidents. | Add host-resolution test in CI that pings each registered endpoint on a weekly cron (not in unit-test CI). Add telemetry alerting when `OSINTAdapterError.fetchDenied` spikes for a previously-healthy source. Keep fallback: router operates without live hazard data using pheromind stale state. |
| R2 | **Performance/scale: TileProviderOrchestrator health probe amplification.** Health probes to both primary and fallback on every tick could exceed Mapbox/OSM rate limits, especially at 60 bpm oscillator rate. | High | Medium — rate-limit ban on tile endpoints. | Use jittered exponential backoff on probe frequency (minimum 30s between probes per provider, not per tick). `PhaseLockedSubscriber.onTick` only triggers a probe if `timeSinceLastProbe > probeInterval`. Oscillator tick handles cache eviction, not network I/O on every beat. |
| R3 | **Determinism failure: floating-point weighted composition instability.** Multi-profile cost composition with weighted sums may produce non-deterministic route ordering due to floating-point associativity differences across platforms. | Low | High — golden-file tests break; router non-determinism violates spec. | Round all intermediate cost computations to 10^-9 precision before comparison. Use stable sort with secondary key (edge ID lexicographic) to break ties. Include a determinism round-trip test: route 1000 times on same graph, assert identical output. |
| R4 | **EMSPreferredProfile scope leak.** If profile composition logic fails to filter by `principalScope`, a responder-only profile could influence companion/guest routes, leaking EMS-specific cost adjustments (e.g., fire-hazard avoidance) to unauthorized tiers. | Low | High — tier isolation violation per Principal doctrine. | Add adversarial test: compose all four profiles, call `route()` with `.guestTier`, assert EMSPreferredProfile cost terms contribute exactly 0.0. Add runtime assert in `UniversalRouter.route()` that only profiles within scope contribute. |
| R5 | **HazardCache memory growth without bound.** If multiple OSINT adapters produce high-volume features (e.g., FIRMS during wildfire season), the cache could grow unbounded across oscillator eviction cycles. | Medium | Medium — memory pressure on constrained devices (Watch/TV). | Cap `maxEntries` (default 500). LRU eviction on insert when at capacity. Telemetry log when eviction fires. Tune cap per platform at integration time. |
| R6 | **ScenePreSearch web-search TODO becomes a security surface.** The spec says "web-search fetch path left as TODO with clear integration point." If a future implementor wires a general-purpose HTTP client without provenance, it bypasses WebContentFetchPolicy. | Medium | High — unsanctioned scraping, potential TOS violation. | Mark the TODO with a `// SECURITY:` comment block requiring WebContentFetchPolicy authorization. Add a compile-time check in the test suite that `RegisteredAPIScenePreSearch` only references URLs that pass through the policy. The todo file gets an explicit security review checklist item. |
| R7 | **Canon-gate floor bump race condition.** NAV-001 adds ~45 tests across phases. If another spec (e.g., UX-001) merges concurrently with conflicting floor bumps, one CI run will fail. | Medium | Low — CI failure, not data loss. | Bump floor in the final PR of each phase only (not every intermediate PR). Coordinate floor values in PR description. Final floor should be current_actual + NAV-001_new_tests. |

---

## 7. Sequencing

### PR1: MapTileProvider + TileProviderOrchestrator (Phase A)
- **New files:** `MapTileProvider.swift`, `MapboxTileProvider.swift`, `MapLibreOSMTileProvider.swift`, `TileProviderOrchestrator.swift`, `MapTileProviderTests.swift`, fixture JSON
- **Modified:** none (canon-gate floor bump deferred to PR5)
- **Net LOC:** ~420 (250 implementation + 170 tests)
- **Test count added:** ~9
- **Can land:** independently — no deps on later PRs

### PR2: RoutingProfile + UniversalRouter core (Phase B engine)
- **New files:** `RoutingProfile.swift`, `UniversalRouter.swift`, `RouteEdge`/`RouteContext`/`RankedRoute` in `RoutingProfile.swift`, `UniversalRouterTests.swift`, route graph + golden fixtures
- **Modified:** none
- **Net LOC:** ~450 (280 implementation + 170 tests)
- **Test count added:** ~6 (engine determinism + composition)
- **Can land:** independently — profiles in PR3 add concrete RoutingProfile implementations

### PR3: Seed routing profiles (Phase B profiles)
- **New files:** `StandardAutoProfile.swift`, `AccessibilityProfile.swift`, `EMSPreferredProfile.swift`, `ScenicProfile.swift`, profile-specific tests added to `UniversalRouterTests.swift`
- **Modified:** none
- **Net LOC:** ~380 (200 implementation + 180 tests)
- **Test count added:** ~5
- **Depends on:** PR2 (RoutingProfile protocol)

### PR4: OSINT adapters (Phase C)
- **New files:** `HazardOverlayFeature.swift`, `OSINTAdapterError.swift`, `HazardCache.swift`, four adapter files, four test files, five fixtures
- **Modified:** none
- **Net LOC:** ~480 (260 implementation + 220 tests)
- **Test count added:** ~14 (4 adapters x 4 tests each + cache + denied-host)
- **Can land:** independently — adapters are standalone, HazardOverlayFeature is self-contained

### PR5: ScenePreSearch + integration wiring + canon-gate floor bump (Phase D + all-phase wiring)
- **New files:** `ScenePreSearch.swift`, `SceneBriefing.swift`, `RegisteredAPIScenePreSearch.swift`, `ScenePreSearchTests.swift`, `NavigationPheromoneDeposit.swift`, fixture JSON
- **Modified:** `.github/workflows/canon-gate.yml` — bump floor from current to current + ~45
- **Net LOC:** ~400 (220 implementation + 180 tests)
- **Test count added:** ~7
- **Depends on:** PR4 (HazardOverlayFeature, OSINTHazardAdapter), PR2 (Coordinate)
- **Final floor:** will be set to `actual_count_at_merge_time`

### PR6: Pheromind integration + oscillator subscriber wiring (cross-cutting)
- **New files:** `NavigationPheromoneDeposit.swift` (may be in PR5; if too large, split here), integration tests for deposits and tick-driven eviction
- **Modified:** potentially `HazardCache` to verify `PhaseLockedSubscriber` integration
- **Net LOC:** ~300 (150 implementation + 150 tests)
- **Test count added:** ~4
- **Depends on:** PR1 (TileProviderOrchestrator health probe on tick), PR4 (HazardCache onTick)

---

**Total estimated new tests:** ~45
**Total estimated net LOC:** ~2,430
**Canon-gate floor target:** current + 45 (actual value determined at merge time)
**All PRs:** <= 500 net LOC including tests. Each independently landable except where dependency noted.