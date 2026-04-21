import XCTest
@testable import JarvisCore

/// NAV-001 Phase E tests: ScenePreSearch tier-gating.
///
/// Verifies that fanned-out hazard adapters respect principal tier:
///   - Operator: full fusion (traffic + fire + weather + seismic)
///   - Companion: traffic + fire + weather (no seismic)
///   - Responder: traffic + fire + weather + seismic
///   - Guest: empty briefing
final class ScenePreSearchTests: XCTestCase {

    // MARK: - Stub adapter

    struct StubHazardAdapter: HazardAdapter, Sendable {
        let sourceKey: String
        let features: [HazardOverlayFeature]

        func fetch(principal: Principal) async throws -> [HazardOverlayFeature] {
            features
        }
    }

    static func makeFeature(id: String, sourceKey: String, category: HazardCategory) -> HazardOverlayFeature {
        HazardOverlayFeature(
            id: id, sourceKey: sourceKey, category: category,
            severity: .info, geometry: .point(lat: 30.0, lon: -97.0),
            observedAt: Date(), ttl: 300, summary: "Stub \(id)")
    }

    static func makePreSearch() -> DefaultScenePreSearch {
        DefaultScenePreSearch(adapters: [
            StubHazardAdapter(sourceKey: "txdot.drivetexas", features: [
                makeFeature(id: "tx1", sourceKey: "txdot.drivetexas", category: .traffic)
            ]),
            StubHazardAdapter(sourceKey: "firms.nasa", features: [
                makeFeature(id: "f1", sourceKey: "firms.nasa", category: .fire)
            ]),
            StubHazardAdapter(sourceKey: "noaa.nws", features: [
                makeFeature(id: "n1", sourceKey: "noaa.nws", category: .weather)
            ]),
            StubHazardAdapter(sourceKey: "usgs.quake", features: [
                makeFeature(id: "u1", sourceKey: "usgs.quake", category: .seismic)
            ]),
        ])
    }

    func testOperatorTierGetsFullFusion() async throws {
        let presearch = Self.makePreSearch()
        let briefing = try await presearch.gather(
            principal: .operatorTier, near: LatLon(lat: 30, lon: -97), radiusMeters: 5000)
        XCTAssertEqual(briefing.nearbyLayers.sorted(), ["firms.nasa", "noaa.nws", "txdot.drivetexas", "usgs.quake"].sorted(),
                       "Operator gets all four layers")
        // 1 feature per adapter * 4 adapters = 4
        XCTAssertEqual(briefing.hazards.count, 4)
    }

    func testCompanionTierExcludesSeismic() async throws {
        let presearch = Self.makePreSearch()
        let briefing = try await presearch.gather(
            principal: .companion(memberID: "melissa"), near: LatLon(lat: 30, lon: -97), radiusMeters: 5000)
        XCTAssertFalse(briefing.nearbyLayers.contains("usgs.quake"),
                       "Companion tier must not get seismic data")
        XCTAssertEqual(briefing.nearbyLayers.count, 3, "Companion gets traffic + fire + weather")
    }

    func testResponderTierGetsEMSRelevant() async throws {
        let presearch = Self.makePreSearch()
        let briefing = try await presearch.gather(
            principal: .responder(role: .emtp), near: LatLon(lat: 30, lon: -97), radiusMeters: 5000)
        XCTAssertTrue(briefing.nearbyLayers.contains("usgs.quake"),
                     "Responder tier gets seismic for EMS-relevant situational awareness")
        XCTAssertEqual(briefing.nearbyLayers.count, 4, "Responder gets all four layers")
    }

    func testGuestTierReturnsEmptyBriefing() async throws {
        let presearch = Self.makePreSearch()
        let briefing = try await presearch.gather(
            principal: .guestTier, near: LatLon(lat: 30, lon: -97), radiusMeters: 5000)
        XCTAssertTrue(briefing.hazards.isEmpty, "Guest tier must get no hazards")
        XCTAssertTrue(briefing.nearbyLayers.isEmpty, "Guest tier must get no layers")
    }
}