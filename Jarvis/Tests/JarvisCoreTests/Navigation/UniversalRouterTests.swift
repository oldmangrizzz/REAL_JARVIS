import XCTest
@testable import JarvisCore

// MARK: - Test Suite

final class UniversalRouterTests: XCTestCase {
    
    // System Under Test
    var router: UniversalRouter!
    
    // Shared Mocks
    var mockTileProvider: MockTileProvider!
    var mockHazardAdapter: MockHazardAdapter!
    var orchestrator: NavigationOrchestrator!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        
        mockTileProvider = MockTileProvider()
        mockHazardAdapter = MockHazardAdapter()
        orchestrator = NavigationOrchestrator(tileProvider: mockTileProvider,
                                              hazardAdapter: mockHazardAdapter)
        router = UniversalRouter(orchestrator: orchestrator)
    }
    
    // MARK: - Tests
    
    /// Verifies that a deterministic path is produced for a simple grid when using a profile that prefers the shortest route.
    func testDeterministicOrderingForShortestProfile() {
        // Arrange
        let profile = NavigationProfile(name: "Shortest",
                                        preferences: [.preferShortest])
        let start = Coordinate(x: 0, y: 0)
        let destination = Coordinate(x: 5, y: 5)
        
        // Act
        let routes = router.calculateRoutes(from: start,
                                             to: destination,
                                             using: profile)
        
        // Assert
        XCTAssertEqual(routes.count, 1, "Exactly one route should be returned.")
        let route = routes.first!
        
        let expectedPath: [Coordinate] = [
            Coordinate(x: 0, y: 0), Coordinate(x: 1, y: 0), Coordinate(x: 2, y: 0),
            Coordinate(x: 3, y: 0), Coordinate(x: 4, y: 0), Coordinate(x: 5, y: 0),
            Coordinate(x: 5, y: 1), Coordinate(x: 5, y: 2), Coordinate(x: 5, y: 3),
            Coordinate(x: 5, y: 4), Coordinate(x: 5, y: 5)
        ]
        XCTAssertEqual(route.path, expectedPath, "Path should follow the deterministic L‑shaped route.")
        XCTAssertEqual(route.totalCost, 11.0, accuracy: 0.001, "Each step costs 1.0, total should be 11.")
    }
    
    /// Ensures that hazard costs are incorporated correctly and that routes avoid high‑cost hazard tiles when the profile requests it.
    func testCostCalculationWithHazardAvoidance() {
        // Arrange
        let hazardousCoordinate = Coordinate(x: 2, y: 2)
        mockHazardAdapter.addHazard(at: hazardousCoordinate, cost: 10.0)
        
        let profile = NavigationProfile(name: "AvoidHazard",
                                        preferences: [.avoidHazards])
        let start = Coordinate(x: 0, y: 0)
        let destination = Coordinate(x: 4, y: 4)
        
        // Act
        let routes = router.calculateRoutes(from: start,
                                             to: destination,
                                             using: profile)
        
        // Assert
        XCTAssertEqual(routes.count, 1, "Exactly one route should be returned.")
        let route = routes.first!
        XCTAssertFalse(route.path.contains(hazardousCoordinate),
                       "Route must not traverse the hazardous tile.")
        XCTAssertEqual(route.totalCost, 8.0, accuracy: 0.001,
                       "Optimal path around the hazard should have a cost of 8 (8 steps × 1.0).")
    }
    
    /// Checks that multiple profiles are processed in a deterministic alphabetical order and that their cost rankings respect the profile preferences.
    func testMultipleProfilesDeterministicOrderingAndCostRanking() {
        // Arrange
        let profiles = [
            NavigationProfile(name: "Balanced", preferences: [.balanced]),
            NavigationProfile(name: "LowCost", preferences: [.avoidHighCost]),
            NavigationProfile(name: "Shortest", preferences: [.preferShortest])
        ]
        let start = Coordinate(x: 0, y: 0)
        let destination = Coordinate(x: 3, y: 3)
        
        // Act
        var results: [(profileName: String, route: Route)] = []
        for profile in profiles {
            let route = router.calculateRoutes(from: start,
                                                to: destination,
                                                using: profile).first!
            results.append((profile.name, route))
        }
        
        // Assert deterministic alphabetical ordering
        let orderedNames = results.map { $0.profileName }
        XCTAssertEqual(orderedNames, ["Balanced", "LowCost", "Shortest"],
                       "Profiles should be processed in alphabetical order.")
        
        // Verify cost ranking respects preferences (Balanced ≤ LowCost ≤ Shortest)
        let costs = results.map { $0.route.totalCost }
        XCTAssertTrue(costs[0] <= costs[1],
                      "Balanced profile should not be more expensive than LowCost.")
        XCTAssertTrue(costs[1] <= costs[2],
                      "LowCost profile should not be more expensive than Shortest.")
    }
}

// MARK: - Supporting Types & Mocks

// Simple coordinate representation used throughout the tests.
struct Coordinate: Hashable, Equatable {
    let x: Int
    let y: Int
}

// Minimal route representation returned by the router.
struct Route: Equatable {
    let path: [Coordinate]
    let totalCost: Double
}

// MARK: - Mock Tile Provider

/// Provides a static 10×10 grid where each tile has a base cost of 1.0.
final class MockTileProvider: TileProvider {
    func tiles(in region: Region) -> [Tile] {
        var tiles: [Tile] = []
        for x in 0..<10 {
            for y in 0..<10 {
                let coordinate = Coordinate(x: x, y: y)
                let tile = Tile(id: "\(x),\(y)",
                                coordinate: coordinate,
                                baseCost: 1.0)
                tiles.append(tile)
            }
        }
        return tiles
    }
}

// MARK: - Mock Hazard Adapter

/// Supplies additional cost for specific coordinates to simulate hazards.
final class MockHazardAdapter: HazardAdapter {
    private var hazardMap: [Coordinate: Double] = [:]
    
    func cost(at coordinate: Coordinate) -> Double {
        return hazardMap[coordinate] ?? 0.0
    }
    
    func addHazard(at coordinate: Coordinate, cost: Double) {
        hazardMap[coordinate] = cost
    }
}

// MARK: - Extensions for Core Types (if needed)

extension Tile {
    /// Convenience initializer used by the mock tile provider.
    init(id: String, coordinate: Coordinate, baseCost: Double) {
        self.init(id: id,
                  coordinate: coordinate,
                  baseCost: baseCost,
                  metadata: [:])
    }
}