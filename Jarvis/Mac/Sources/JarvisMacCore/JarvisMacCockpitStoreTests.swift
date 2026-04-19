import XCTest
@testable import JarvisMacCore

final class JarvisMacCockpitStoreTests: XCTestCase {
    func testInitializationWithMacDesktopRole() {
        let store = JarvisMacCockpitStore()
        XCTAssertEqual(store.role, .macDesktop)
    }

    func testVoiceGateExposesSnapshotData() {
        let store = JarvisMacCockpitStore()
        XCTAssertNil(store.voiceGate, "Voice gate should be nil before fetch")
    }

    func testSpatialHUDReturnsEmptyArrayBeforeFetch() {
        let store = JarvisMacCockpitStore()
        XCTAssertEqual(store.spatialHUD.count, 0, "Spatial HUD should be empty before fetch")
    }

    func testConnectionStateStartsDisconnected() {
        let store = JarvisMacCockpitStore()
        XCTAssertEqual(store.connectionState, .disconnected, "Initial state should be disconnected")
    }

    func testDiagnosticsInitializesEmpty() {
        let store = JarvisMacCockpitStore()
        XCTAssertTrue(store.diagnostics.isEmpty, "Diagnostics should be empty initially")
    }
}
