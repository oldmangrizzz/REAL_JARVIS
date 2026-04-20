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

    func testUnknownDisplayAndAccessoryReturnSentinel() throws {
        let paths = try makeTestWorkspace()
        let registry = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        XCTAssertEqual(registry.matchDisplay(from: "show it on the ceiling"), "unknown")
        XCTAssertEqual(registry.matchAccessoryName(from: "turn on the garage door"), "unknown")
    }

    func testMatchActionBranches() throws {
        let paths = try makeTestWorkspace()
        let r = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        XCTAssertEqual(r.matchAction(from: "show camera feed"), "display-camera")
        XCTAssertEqual(r.matchAction(from: "pull up the map"), "display-map")
        XCTAssertEqual(r.matchAction(from: "show dashboard"), "display-dashboard")
        XCTAssertEqual(r.matchAction(from: "put cockpit hud on left"), "display-dashboard")
        XCTAssertEqual(r.matchAction(from: "display status board"), "display-telemetry")
        XCTAssertEqual(r.matchAction(from: "throw something up"), "display-generic")
    }

    func testMatchParametersBranches() throws {
        let paths = try makeTestWorkspace()
        let r = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        XCTAssertEqual(r.matchParameters(from: "show camera on the left")["content"], "camera")
        XCTAssertEqual(r.matchParameters(from: "dashboard on the tv")["content"], "dashboard")
        // Later branches (hud/cockpit/dashboard) overwrite earlier in insertion order.
        let mixed = r.matchParameters(from: "show telemetry and dashboard")
        XCTAssertEqual(mixed["content"], "dashboard")
        XCTAssertTrue(r.matchParameters(from: "do the thing").isEmpty)
    }

    func testDisplayAndAccessoryLookupByID() throws {
        let paths = try makeTestWorkspace()
        let r = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        XCTAssertEqual(r.display(for: "left-monitor")?.displayName, "Left Monitor")
        XCTAssertNil(r.display(for: "no-such-display"))
        XCTAssertEqual(r.accessory(for: "kitchen-lights")?.homeKitAccessoryID, "kitchen-lights-HK")
        XCTAssertNil(r.accessory(for: "no-such-accessory"))
    }

    func testDisplayIndexIsOneBased() throws {
        let paths = try makeTestWorkspace()
        let r = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        XCTAssertEqual(r.displayIndex(for: "left-monitor"), 1)
        XCTAssertEqual(r.displayIndex(for: "lab-tv"), 2)
        XCTAssertEqual(r.displayIndex(for: "workshop-projector"), 3)
        XCTAssertNil(r.displayIndex(for: "no-such"))
    }

    func testAuthorityDefaultsToStandardWhenMissing() throws {
        let paths = try makeTestWorkspace()
        let r = try CapabilityRegistry(configURL: paths.root.appendingPathComponent(".jarvis/capabilities.json"))
        // Fixture has no `authority` field on any display → all decode to .standard.
        for id in r.allDisplayIDs {
            XCTAssertEqual(r.display(for: id)?.authority, .standard, "expected \(id) to default to .standard")
        }
    }

    func testAuthorityDecodesExplicitValues() throws {
        let json = """
        {
          "displays": [
            {"id":"echo","displayName":"Echo","aliases":["echo"],"type":"host","transport":"local","address":null,"capabilities":[],"room":null,"authority":"full-control"},
            {"id":"charlie","displayName":"Charlie","aliases":["charlie"],"type":"mesh-node","transport":"jarvis-tunnel","address":null,"capabilities":[],"room":null,"authority":"full-access-and-control"}
          ],
          "accessories": []
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(CapabilityConfig.self, from: json)
        XCTAssertEqual(config.displays[0].authority, .fullControl)
        XCTAssertEqual(config.displays[1].authority, .fullAccessAndControl)
    }

    func testReloadReplacesState() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let r = try CapabilityRegistry(configURL: configURL)
        XCTAssertEqual(r.allDisplayIDs.count, 3)

        let slim = """
        {"displays":[{"id":"only","displayName":"Only","aliases":["only"],"type":"monitor","transport":"local","address":null,"capabilities":[],"room":null}],"accessories":[]}
        """
        try slim.write(to: configURL, atomically: true, encoding: .utf8)
        try r.reload(from: configURL)
        XCTAssertEqual(r.allDisplayIDs, ["only"])
        XCTAssertEqual(r.allAccessoryIDs, [])
        XCTAssertNil(r.display(for: "left-monitor"))
    }
}
