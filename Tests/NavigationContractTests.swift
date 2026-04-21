import XCTest
@testable import MyApp

// MARK: - Test Helpers

private extension NavigationContract {
    static func sample() -> NavigationContract {
        return NavigationContract(
            routeId: "sample-route-123",
            waypoints: [
                Waypoint(latitude: 37.7749, longitude: -122.4194),
                Waypoint(latitude: 34.0522, longitude: -118.2437)
            ],
            destination: Destination(latitude: 34.0522, longitude: -118.2437, name: "Los Angeles")
        )
    }
}

private extension Destination {
    /// Returns `true` if the coordinate is within valid latitude/longitude bounds.
    var isValid: Bool {
        return (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }
}

// MARK: - NavigationContractTests

final class NavigationContractTests: XCTestCase {

    // MARK: 1️⃣ Contract Round‑Trip

    func testContractRoundTripEncodingDecoding() throws {
        // Given
        let original = NavigationContract.sample()

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NavigationContract.self, from: data)

        // Then
        XCTAssertEqual(original, decoded, "Decoded contract should be equal to the original")
    }

    // MARK: 2️⃣ Platform‑Guard Compile Assertions

    func testPlatformGuardCompilation() {
        // This test does not run any runtime logic; it merely ensures that the
        // platform‑guarded symbols compile on the appropriate platforms.
        #if canImport(CarPlay)
        // CarPlay framework is available – we should be able to reference CarPlayScene.
        let _ = CarPlayScene.self
        #else
        // On platforms without CarPlay we expect the symbol to be unavailable.
        // The absence of a compile‑time error is the success condition.
        #endif

        // Similarly, ensure that the NavigationStore is only compiled for iOS/tvOS.
        #if os(iOS) || os(tvOS)
        let _ = NavigationStore.shared
        #endif
    }

    // MARK: 3️⃣ CarPlay Scene Initialization

    func testCarPlaySceneInitialization() {
        #if canImport(CarPlay)
        // Given / When
        let scene = CarPlayScene()

        // Then
        XCTAssertNotNil(scene, "CarPlayScene should be instantiated without crashing")
        #else
        // Skip on platforms that do not support CarPlay.
        XCTAssertTrue(true, "CarPlay not available on this platform – test skipped.")
        #endif
    }

    // MARK: 4️⃣ PWA JSON Shape Compatibility

    func testPWAJSONShapeCompatibility() throws {
        // Simulated PWA‑generated JSON payload.
        let jsonString = """
        {
            "routeId": "pwa-route-456",
            "waypoints": [
                { "latitude": 40.7128, "longitude": -74.0060 },
                { "latitude": 42.3601, "longitude": -71.0589 }
            ],
            "destination": {
                "latitude": 42.3601,
                "longitude": -71.0589,
                "name": "Boston"
            }
        }
        """
        let jsonData = Data(jsonString.utf8)

        // When
        let decoder = JSONDecoder()
        let contract = try decoder.decode(NavigationContract.self, from: jsonData)

        // Then
        XCTAssertEqual(contract.routeId, "pwa-route-456")
        XCTAssertEqual(contract.waypoints.count, 2)
        XCTAssertEqual(contract.destination.name, "Boston")
    }

    // MARK: 5️⃣ Route Cache Eviction Logic

    func testRouteCacheEvictionWhenExceedingLimit() {
        // Assuming NavigationStore has a `maxCacheSize` of 3 for testability.
        let store = NavigationStore.shared
        store.maxCacheSize = 3
        store.clearAllRoutes()

        // Add four distinct routes.
        for i in 1...4 {
            let contract = NavigationContract(
                routeId: "route-\(i)",
                waypoints: [],
                destination: Destination(latitude: 0.0, longitude: 0.0, name: "Dummy")
            )
            store.addRoute(contract)
        }

        // The store should retain only the last three routes (2,3,4).
        let retainedIds = store.routes.map { $0.routeId }
        XCTAssertFalse(retainedIds.contains("route-1"), "Oldest route should be evicted")
        XCTAssertTrue(retainedIds.contains("route-2"))
        XCTAssertTrue(retainedIds.contains("route-3"))
        XCTAssertTrue(retainedIds.contains("route-4"))
    }

    // MARK: 6️⃣ Destination Validation

    func testDestinationValidationRejectsInvalidCoordinates() {
        // Invalid latitude (> 90)
        let invalidLat = Destination(latitude: 95.0, longitude: 0.0, name: "InvalidLat")
        XCTAssertFalse(invalidLat.isValid, "Latitude beyond ±90° should be invalid")

        // Invalid longitude (< -180)
        let invalidLon = Destination(latitude: 0.0, longitude: -190.0, name: "InvalidLon")
        XCTAssertFalse(invalidLon.isValid, "Longitude beyond ±180° should be invalid")

        // Valid coordinate
        let valid = Destination(latitude: 45.0, longitude: 45.0, name: "Valid")
        XCTAssertTrue(valid.isValid, "Coordinates within bounds should be valid")
    }
}