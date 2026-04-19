import XCTest
@testable import JarvisCore

final class CapabilityRegistryTests: XCTestCase {
    func testRegistryLoadsFromConfigFile() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let registry = try CapabilityRegistry(configURL: configURL)

        XCTAssertEqual(registry.allDisplayIDs.count, 3)
        XCTAssertEqual(registry.allAccessoryIDs.count, 3)
    }

    func testDisplayMatchingByAlias() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)

        XCTAssertEqual(registry.matchDisplay(from: "put telemetry on the left monitor"), "left-monitor")
        XCTAssertEqual(registry.matchDisplay(from: "show feed on primary tv"), "lab-tv")
    }

    func testAccessoryMatchingByAlias() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)

        XCTAssertEqual(registry.matchAccessoryName(from: "turn off the kitchen lights"), "kitchen-lights")
        XCTAssertEqual(registry.matchAccessoryName(from: "lock the front door"), "front-door-lock")
    }

    func testActionAndParametersExtraction() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)

        XCTAssertEqual(registry.matchAction(from: "put telemetry on the left monitor"), "display-telemetry")
        XCTAssertEqual(registry.matchParameters(from: "show cockpit on the left monitor"), ["content": "hud"])
    }
}
