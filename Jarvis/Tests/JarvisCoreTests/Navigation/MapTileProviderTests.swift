import XCTest
@testable import JarvisCore

// MARK: - Mock Types

/// Simple coordinate representation used by the tile system.
struct TileCoordinate: Equatable {
    let x: Int
    let y: Int
    let zoom: Int
}

/// Dummy image placeholder returned by mock providers.
struct TileImage: Equatable {
    let identifier: String
}

/// Protocol that real tile providers conform to.
protocol TileProvider {
    var name: String { get }
    var tier: Int { get }
    var isHealthy: Bool { get }
    func fetchTile(at coordinate: TileCoordinate) -> TileImage?
    func probeHealth() -> Bool
}

/// Simple in‑memory audit log used by the orchestrator.
final class AuditLog {
    static let shared = AuditLog()
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }

    func clear() {
        entries.removeAll()
    }
}

// MARK: - Mock Provider

final class MockTileProvider: TileProvider {
    let name: String
    let tier: Int
    private(set) var healthProbeResult: Bool
    private(set) var fetchCalledWith: TileCoordinate?

    init(name: String, tier: Int, initialHealth: Bool) {
        self.name = name
        self.tier = tier
        self.healthProbeResult = initialHealth
    }

    var isHealthy: Bool {
        return healthProbeResult
    }

    func fetchTile(at coordinate: TileCoordinate) -> TileImage? {
        fetchCalledWith = coordinate
        return TileImage(identifier: "\(name)-\(coordinate.x)-\(coordinate.y)-\(coordinate.zoom)")
    }

    func probeHealth() -> Bool {
        return healthProbeResult
    }

    // Helper to toggle health during a test.
    func setHealth(_ healthy: Bool) {
        healthProbeResult = healthy
    }
}

// MARK: - Orchestrator Under Test

/// Simplified orchestrator that selects a provider based on health and tier,
/// performs a health probe before selection, and records audit entries.
final class TileProviderOrchestrator {
    private var providers: [TileProvider] = []

    func register(_ provider: TileProvider) {
        providers.append(provider)
    }

    func clearProviders() {
        providers.removeAll()
    }

    /// Returns a tile image for the given coordinate respecting the caller's tier.
    /// The highest‑tier healthy provider that does not exceed `maxTier` is chosen.
    func fetchTile(at coordinate: TileCoordinate, maxTier: Int) -> TileImage? {
        // Probe health for all providers (simulated as a simple call).
        let healthyProviders = providers.filter { $0.probeHealth() }

        // Filter by tier gating.
        let tieredProviders = healthyProviders.filter { $0.tier <= maxTier }

        // Choose the provider with the highest tier.
        guard let selected = tieredProviders.max(by: { $0.tier < $1.tier }) else {
            AuditLog.shared.record("Tile fetch failed: no suitable provider for tier \(maxTier)")
            return nil
        }

        // Perform the fetch.
        let image = selected.fetchTile(at: coordinate)

        // Record audit entry.
        AuditLog.shared.record("Tile fetched by \(selected.name) for coordinate \(coordinate)")

        return image
    }
}

// MARK: - Tests

final class MapTileProviderTests: XCTestCase {

    private var orchestrator: TileProviderOrchestrator!
    private var providerA: MockTileProvider!
    private var providerB: MockTileProvider!
    private var providerC: MockTileProvider!
    private let testCoordinate = TileCoordinate(x: 10, y: 20, zoom: 5)

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        orchestrator = TileProviderOrchestrator()
        AuditLog.shared.clear()

        // Provider A: tier 1, initially healthy
        providerA = MockTileProvider(name: "ProviderA", tier: 1, initialHealth: true)

        // Provider B: tier 2, initially healthy
        providerB = MockTileProvider(name: "ProviderB", tier: 2, initialHealth: true)

        // Provider C: tier 3, initially healthy (used for tier‑gating tests)
        providerC = MockTileProvider(name: "ProviderC", tier: 3, initialHealth: true)

        orchestrator.register(providerA)
        orchestrator.register(providerB)
        orchestrator.register(providerC)
    }

    override func tearDown() {
        orchestrator.clearProviders()
        orchestrator = nil
        providerA = nil
        providerB = nil
        providerC = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    /// Verify that the orchestrator selects the highest‑tier healthy provider.
    func testProviderSelectionPrefersHighestHealthyTier() {
        // All providers are healthy; maxTier set high enough to include all.
        let image = orchestrator.fetchTile(at: testCoordinate, maxTier: 5)

        XCTAssertNotNil(image, "Expected a tile image to be returned")
        XCTAssertEqual(image?.identifier, "ProviderC-10-20-5", "Expected ProviderC (tier 3) to be selected")
        XCTAssertEqual(providerC.fetchCalledWith, testCoordinate, "ProviderC should have been called")
        XCTAssertNil(providerB.fetchCalledWith, "ProviderB should not be called")
        XCTAssertNil(providerA.fetchCalledWith, "ProviderA should not be called")
    }

    /// Simulate a health probe failure and ensure the unhealthy provider is ignored.
    func testHealthProbingExcludesUnhealthyProvider() {
        // Mark ProviderC as unhealthy.
        providerC.setHealth(false)

        // Max tier still high enough to include ProviderC if it were healthy.
        let image = orchestrator.fetchTile(at: testCoordinate, maxTier: 5)

        XCTAssertNotNil(image, "Expected a tile image despite one provider being unhealthy")
        XCTAssertEqual(image?.identifier, "ProviderB-10-20-5", "Expected ProviderB (tier 2) to be selected")
        XCTAssertEqual(providerB.fetchCalledWith, testCoordinate, "ProviderB should have been called")
        XCTAssertNil(providerC.fetchCalledWith, "ProviderC should not be called because it is unhealthy")
        XCTAssertNil(providerA.fetchCalledWith, "ProviderA should not be called")
    }

    /// Verify that tier gating respects the caller's maximum allowed tier.
    func testTierGatingRespectsUserTierLimit() {
        // User tier limit is 1; only ProviderA should be eligible.
        let image = orchestrator.fetchTile(at: testCoordinate, maxTier: 1)

        XCTAssertNotNil(image, "Expected a tile image for tier limit 1")
        XCTAssertEqual(image?.identifier, "ProviderA-10-20-5", "Expected ProviderA (tier 1) to be selected")
        XCTAssertEqual(providerA.fetchCalledWith, testCoordinate, "ProviderA should have been called")
        XCTAssertNil(providerB.fetchCalledWith, "ProviderB should be excluded by tier gating")
        XCTAssertNil(providerC.fetchCalledWith, "ProviderC should be excluded by tier gating")
    }

    /// Ensure that each successful fetch records an appropriate audit log entry.
    func testAuditLogRecordsProviderSelection() {
        // Perform a fetch that should select ProviderB.
        providerC.setHealth(false) // make tier 3 unavailable
        _ = orchestrator.fetchTile(at: testCoordinate, maxTier: 5)

        // Verify audit log.
        XCTAssertEqual(AuditLog.shared.entries.count, 1, "Exactly one audit entry should be recorded")
        let entry = AuditLog.shared.entries.first!
        XCTAssertTrue(entry.contains("ProviderB"), "Audit entry should reference ProviderB")
        XCTAssertTrue(entry.contains("10, 20, 5"), "Audit entry should contain the coordinate")
    }

    /// When no providers satisfy the tier or health constraints, the orchestrator returns nil and logs the failure.
    func testFetchReturnsNilWhenNoSuitableProvider() {
        // Make all providers unhealthy.
        providerA.setHealth(false)
        providerB.setHealth(false)
        providerC.setHealth(false)

        let image = orchestrator.fetchTile(at: testCoordinate, maxTier: 5)

        XCTAssertNil(image, "Expected nil when no providers are healthy")
        XCTAssertEqual(AuditLog.shared.entries.count, 1, "A failure audit entry should be recorded")
        XCTAssertTrue(AuditLog.shared.entries.first!.contains("no suitable provider"), "Failure entry should mention lack of suitable provider")
    }
}