import XCTest
@testable import JarvisCore

/// NAV-001 Phase C tests: Routing profiles tier-scope enforcement.
///
/// Verifies that each profile's `principalScope` is an exhaustive
/// allow-list with no default fallthrough.
final class RoutingProfilesTests: XCTestCase {

    func testStandardAutoAllTiers() {
        let profile = StandardAutoProfile()
        XCTAssertTrue(profile.principalScope.contains(.grizz))
        XCTAssertTrue(profile.principalScope.contains(.companion))
        XCTAssertTrue(profile.principalScope.contains(.guest))
        XCTAssertTrue(profile.principalScope.contains(.responder))
        XCTAssertEqual(profile.principalScope.count, 4, "Standard auto must allow all four categories")
    }

    func testEMSPreferredResponderOnly() {
        let profile = EMSPreferredProfile()
        XCTAssertEqual(profile.principalScope.count, 1)
        XCTAssertTrue(profile.principalScope.contains(.responder), "EMS profile is responder-only")
    }

    func testAccessibilityCompanionAndResponder() {
        let profile = AccessibilityProfile()
        XCTAssertTrue(profile.principalScope.contains(.companion))
        XCTAssertTrue(profile.principalScope.contains(.responder))
        XCTAssertFalse(profile.principalScope.contains(.grizz), "Accessibility is not for operator (they get full access via standard)")
        XCTAssertFalse(profile.principalScope.contains(.guest), "Guest tier does not get accessibility routing")
        XCTAssertEqual(profile.principalScope.count, 2)
    }

    func testScenicExcludesHighways() {
        let profile = ScenicProfile()
        let context = RoutingContext(principal: .operatorTier, activeHazards: [])

        // Highway edge should be heavily penalized.
        let highwayEdge = RouteEdge(id: "hwy1", fromNode: "A", toNode: "B", lengthMeters: 1000, attributes: ["highway": "motorway"])
        let highwayWeight = profile.edgeWeight(highwayEdge, context: context)

        // Secondary edge should be preferred.
        let secondaryEdge = RouteEdge(id: "sec1", fromNode: "C", toNode: "D", lengthMeters: 1000, attributes: ["highway": "secondary"])
        let secondaryWeight = profile.edgeWeight(secondaryEdge, context: context)

        XCTAssertGreaterThan(highwayWeight, secondaryWeight, "Highway must carry heavier penalty than secondary in scenic profile")
        // Motorway penalty is 5x, secondary bonus is 0.8x → 5000 vs 800.
        XCTAssertEqual(highwayWeight, 5000.0, accuracy: 0.01)
        XCTAssertEqual(secondaryWeight, 800.0, accuracy: 0.01)
    }
}