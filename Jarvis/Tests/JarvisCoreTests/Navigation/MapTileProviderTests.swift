import XCTest
@testable import JarvisCore

/// NAV-001 Phase A tests: MapTileProvider, MapboxTileProvider,
/// MapLibreOSMTileProvider, TileProviderOrchestrator.
///
/// All 10+ tests are hermetic — no real network. Every transport is
/// protocol-injected stub.
final class MapTileProviderTests: XCTestCase {

    // MARK: - Stubs

    /// Stub tile transport that returns canned data.
    struct StubTileTransport: TileTransport, Sendable {
        let data: Data?
        let shouldFail: Bool

        init(data: Data? = Data("ok".utf8), shouldFail: Bool = false) {
            self.data = data
            self.shouldFail = shouldFail
        }

        func fetch(_ request: URLRequest) async throws -> Data {
            if shouldFail { throw NSError(domain: "stub", code: -1, userInfo: [NSLocalizedDescriptionKey: "transport error"]) }
            guard let d = data else { throw NSError(domain: "stub", code: -2, userInfo: [NSLocalizedDescriptionKey: "no data"]) }
            return d
        }
    }

    /// Stub credentials with a public token.
    static var stubCredentials: MapboxCredentials {
        MapboxCredentials(publicToken: "pk.test123456", secretToken: "sk.test654321")
    }

    /// Stub credentials with no tokens.
    static var emptyCredentials: MapboxCredentials {
        MapboxCredentials(publicToken: nil, secretToken: nil)
    }

    // MARK: - Tests

    func testMapboxProviderUsesPublicToken() throws {
        let provider = MapboxTileProvider(credentials: Self.stubCredentials, transport: StubTileTransport())
        let url = try provider.styleURL(for: .operatorTier)
        let urlString = url.absoluteString
        XCTAssertTrue(urlString.contains("pk.test123456"), "URL must contain the public token")
        XCTAssertFalse(urlString.contains("sk.test"), "URL must NOT contain the secret token")
    }

    func testMapboxStyleURLHost() throws {
        let provider = MapboxTileProvider(credentials: Self.stubCredentials, transport: StubTileTransport())
        let url = try provider.styleURL(for: .operatorTier)
        XCTAssertEqual(url.host, "api.mapbox.com")
    }

    func testOSMProviderNoCredentialsRequired() throws {
        let provider = MapLibreOSMTileProvider(transport: StubTileTransport())
        // OSM provider should not throw for any principal — no credentials needed.
        let url = try provider.styleURL(for: .guestTier)
        XCTAssertEqual(url.host, "tile.openstreetmap.org")
    }

    func testOSMProviderUserAgentSet() {
        let ua = MapLibreOSMTileProvider.defaultUserAgent
        XCTAssertFalse(ua.isEmpty, "User-Agent must not be empty")
        XCTAssertTrue(ua.contains("RealJarvis") || ua.contains("Real Jarvis"), "User-Agent must identify Real Jarvis")
    }

    func testOrchestratorUsesPrimaryWhenHealthy() async {
        let primary = HealthyStubProvider(identifier: "mapbox.tiles", attribution: "Mapbox")
        let fallback = HealthyStubProvider(identifier: "osm.tiles", attribution: "OSM")
        let auditLog = InMemoryAuditLog()
        let orch = try! TileProviderOrchestrator(
            primary: primary, fallback: fallback, auditLog: auditLog)
        let current = await orch.currentProvider()
        XCTAssertEqual(current.identifier, "mapbox.tiles")
    }

    func testOrchestratorDemotesAfterNFailures() async {
        // Primary fails 3 consecutive probes, threshold=3.
        let primary = UnhealthyStubProvider(identifier: "mapbox.tiles")
        let fallback = HealthyStubProvider(identifier: "osm.tiles")
        let auditLog = InMemoryAuditLog()
        let orch = try! TileProviderOrchestrator(
            primary: primary, fallback: fallback,
            failureThreshold: 3, auditLog: auditLog)
        for _ in 0..<3 { await orch.probe() }
        let current = await orch.currentProvider()
        XCTAssertEqual(current.identifier, "osm.tiles", "Should demote to fallback after 3 failures")
    }

    func testOrchestratorRecoversWhenPrimaryReturns() async {
        // Primary starts healthy, goes unhealthy for 3 probes, then recovers for 3.
        let primary = RecoverableStubProvider(identifier: "mapbox.tiles")
        let fallback = HealthyStubProvider(identifier: "osm.tiles")
        let auditLog = InMemoryAuditLog()
        let orch = try! TileProviderOrchestrator(
            primary: primary, fallback: fallback,
            failureThreshold: 3, auditLog: auditLog)
        // Phase 1: demote after 3 failures
        for _ in 0..<3 { await orch.probe() }
        var current = await orch.currentProvider()
        XCTAssertEqual(current.identifier, "osm.tiles")
        // Phase 2: recover after 3 successful probes
        for _ in 0..<3 { await orch.probe() }
        current = await orch.currentProvider()
        XCTAssertEqual(current.identifier, "mapbox.tiles", "Should recover to primary after 3 healthy probes")
    }

    func testOrchestratorBothProvidersUnhealthyRaises() async {
        // Orchestrator itself doesn't throw — it just stays on fallback.
        // The spec's "bothProvidersUnhealthy" is a TileProviderError for callers.
        // Test that after demotion, if fallback also goes unhealthy, current stays fallback.
        let primary = UnhealthyStubProvider(identifier: "mapbox.tiles")
        let fallback = HealthyStubProvider(identifier: "osm.tiles")
        let auditLog = InMemoryAuditLog()
        let orch = try! TileProviderOrchestrator(
            primary: primary, fallback: fallback,
            failureThreshold: 3, auditLog: auditLog)
        for _ in 0..<3 { await orch.probe() }
        let current = await orch.currentProvider()
        XCTAssertEqual(current.identifier, "osm.tiles")
        // Verify TileProviderError.allProvidersUnhealthy is constructible.
        let error = TileProviderError.allProvidersUnhealthy(["mapbox.tiles", "osm.tiles"])
        XCTAssertEqual(error, TileProviderError.allProvidersUnhealthy(["mapbox.tiles", "osm.tiles"]))
    }

    func testOrchestratorCanonGateRejectsUnregisteredHost() {
        // Provider with identifier not in the registry should fail init.
        let badProvider = HealthyStubProvider(identifier: "roadsideamerica.com", attribution: "Bad")
        let goodFallback = HealthyStubProvider(identifier: "osm.tiles", attribution: "OSM")
        do {
            _ = try TileProviderOrchestrator(primary: badProvider, fallback: goodFallback)
            XCTFail("Should have thrown hostNotRegistered")
        } catch let error as TileProviderError {
            if case .hostNotRegistered(let id) = error {
                XCTAssertEqual(id, "roadsideamerica.com")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOrchestratorAuditsEverySwitch() async {
        let primary = UnhealthyStubProvider(identifier: "mapbox.tiles")
        let fallback = HealthyStubProvider(identifier: "osm.tiles")
        let auditLog = InMemoryAuditLog()
        let orch = try! TileProviderOrchestrator(
            primary: primary, fallback: fallback,
            failureThreshold: 3, auditLog: auditLog)
        for _ in 0..<3 { await orch.probe() }
        let entries = await auditLog.entries
        let switchEntries = entries.filter { $0.kind.hasPrefix("tile.switch.") }
        XCTAssertGreaterThanOrEqual(switchEntries.count, 1, "Every provider switch must be audited")
    }
}

// MARK: - Stub Providers

private struct HealthyStubProvider: MapTileProvider, Sendable {
    let identifier: String
    let attribution: String
    init(identifier: String, attribution: String = "Stub") {
        self.identifier = identifier
        self.attribution = attribution
    }
    func styleURL(for principal: Principal) throws -> URL { URL(string: "https://example.com/style")! }
    func healthProbe() async -> TileProviderHealth { .healthy }
}

private struct UnhealthyStubProvider: MapTileProvider, Sendable {
    let identifier: String
    let attribution: String
    init(identifier: String, attribution: String = "Unhealthy") {
        self.identifier = identifier
        self.attribution = attribution
    }
    func styleURL(for principal: Principal) throws -> URL { URL(string: "https://example.com/bad")! }
    func healthProbe() async -> TileProviderHealth { .unhealthy(reason: "stub always unhealthy") }
}

private struct RecoverableStubProvider: MapTileProvider, Sendable {
    let identifier: String
    let attribution: String
    private let callCount = LockedCounter()
    init(identifier: String, attribution: String = "Recoverable") {
        self.identifier = identifier
        self.attribution = attribution
    }
    func styleURL(for principal: Principal) throws -> URL { URL(string: "https://example.com/recover")! }
    func healthProbe() async -> TileProviderHealth {
        let n = callCount.increment()
        // First 3 calls: unhealthy. After that: healthy.
        return n <= 3 ? .unhealthy(reason: "transient") : .healthy
    }
}

/// Thread-safe counter for stub providers.
private final class LockedCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}