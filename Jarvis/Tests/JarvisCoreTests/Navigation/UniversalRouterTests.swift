import XCTest
@testable import JarvisCore

/// NAV-001 Phase B tests: UniversalRouter + RoadGraph + RoutingProfile.
///
/// All tests use `InMemoryRoadGraph` loaded from fixtures. No network.
final class UniversalRouterTests: XCTestCase {

    // MARK: - Test graph

    /// Build a small test graph:
    ///    A --e1--> B --e2--> C
    ///    A --e3--> C (direct)
    ///    B --e4--> D
    ///    C --e5--> D
    static func makeGraph() -> InMemoryRoadGraph {
        InMemoryRoadGraph(edges: [
            RouteEdge(id: "e1", fromNode: "A", toNode: "B", lengthMeters: 100, attributes: ["highway": "secondary"]),
            RouteEdge(id: "e2", fromNode: "B", toNode: "C", lengthMeters: 100, attributes: ["highway": "secondary"]),
            RouteEdge(id: "e3", fromNode: "A", toNode: "C", lengthMeters: 250, attributes: ["highway": "motorway"]),
            RouteEdge(id: "e4", fromNode: "B", toNode: "D", lengthMeters: 300, attributes: ["highway": "residential"]),
            // e5 is affected by hazard h1 (critical incident on C->D corridor).
            RouteEdge(id: "e5", fromNode: "C", toNode: "D", lengthMeters: 50, attributes: ["highway": "secondary", "affectedByHazard": "h1"]),
        ])
    }

    // MARK: - Tests

    func testRouterDeterministicOrdering() throws {
        let graph = Self.makeGraph()
        let router = UniversalRouter(graph: graph)
        let profile = StandardAutoProfile()
        let context = RoutingContext(principal: .operatorTier, activeHazards: [])
        let r1 = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 3)
        let r2 = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 3)
        XCTAssertEqual(r1, r2, "Same inputs must produce byte-equal Route arrays")
    }

    func testRouterShortestStandardProfile() throws {
        let graph = Self.makeGraph()
        let router = UniversalRouter(graph: graph)
        let profile = StandardAutoProfile()
        let context = RoutingContext(principal: .operatorTier, activeHazards: [])
        let routes = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 3)
        XCTAssertGreaterThanOrEqual(routes.count, 1)
        // Shortest path: A->B->C->D (e1+e2+e5 = 100+100+50 = 250)
        let best = routes[0]
        XCTAssertEqual(best.profileIdentifier, "standard_auto")
        // e1(100) * 1.0 + e2(100) * 1.0 + e5(50) * 1.0 = 250
        XCTAssertEqual(best.totalCostWeighted, 250.0, accuracy: 0.01)
        XCTAssertEqual(best.totalLengthMeters, 250.0, accuracy: 0.01)
        XCTAssertEqual(best.edgeIDs, ["e1", "e2", "e5"])
    }

    func testRouterProfileScopeRejectsWrongTier() throws {
        let graph = Self.makeGraph()
        let router = UniversalRouter(graph: graph)
        // EMS profile is responder-only; companion principal should get no routes.
        let profile = EMSPreferredProfile()
        let context = RoutingContext(principal: .companion(memberID: "melissa"), activeHazards: [])
        let routes = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 3)
        XCTAssertTrue(routes.isEmpty, "EMS profile must be rejected for companion tier")
    }

    func testRouterRespectsActiveHazards() throws {
        let graph = Self.makeGraph()
        let router = UniversalRouter(graph: graph)
        // Place a critical hazard on edge e5 (C->D). StandardAuto doesn't
        // use hazard context, but EMS does.
        let hazard = HazardOverlayFeature(
            id: "h1", sourceKey: "txdot.drivetexas",
            category: .traffic, severity: .critical,
            geometry: .point(lat: 30, lon: -97), observedAt: Date(), ttl: 300,
            summary: "Critical incident on C->D"
        )
        let profile = EMSPreferredProfile()
        let context = RoutingContext(principal: .responder(role: .emtp), activeHazards: [hazard])
        let routes = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 3)
        // With e5 penalized 10x, the path A->B->D (e1+e4=100+300=400) should be chosen
        // over A->B->C->D where e5 cost is 50*10=500 just for that edge.
        if let best = routes.first {
            // The hazard-avoiding route should not use edge e5.
            // A->B->D: 130 + 390 = 520 (e1 100*1.3 + e4 300*1.3)
            // vs A->B->C->D: 130 + 500 = 630 (e5 penalized)
            XCTAssertFalse(best.edgeIDs.contains("e5"), "Critical hazard should repel from e5")
        }
    }

    func testRouterReturnsEmptyWhenNoPath() throws {
        // Disconnected graph.
        let graph = InMemoryRoadGraph(edges: [
            RouteEdge(id: "x1", fromNode: "X", toNode: "Y", lengthMeters: 100)
        ])
        let router = UniversalRouter(graph: graph)
        let profile = StandardAutoProfile()
        let context = RoutingContext(principal: .operatorTier, activeHazards: [])
        let routes = try router.routes(from: "X", to: "Z", profiles: [profile], context: context, limit: 3)
        XCTAssertTrue(routes.isEmpty, "No path must return empty routes")
    }

    func testRouterLimitBounds() throws {
        let graph = Self.makeGraph()
        let router = UniversalRouter(graph: graph)
        let profile = StandardAutoProfile()
        let context = RoutingContext(principal: .operatorTier, activeHazards: [])
        let routes = try router.routes(from: "A", to: "D", profiles: [profile], context: context, limit: 1)
        XCTAssertLessThanOrEqual(routes.count, 1, "limit=1 must return at most 1 route")
    }
}