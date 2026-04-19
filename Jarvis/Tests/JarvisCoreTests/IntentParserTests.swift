import XCTest
@testable import JarvisCore

final class IntentParserTests: XCTestCase {
    func testDisplayIntentParsing() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let parser = IntentParser(capabilityRegistry: registry)

        let intent1 = parser.parse(transcript: "Jarvis, put the telemetry feed on the left monitor")
        XCTAssertTrue(intent1.confidence >= 0.8)
        if case .displayAction(let target, let action, let params) = intent1.intent {
            XCTAssertEqual(target, "left-monitor")
            XCTAssertEqual(action, "display-telemetry")
        } else {
            XCTFail("Expected displayAction intent")
        }
    }

    func testHomeKitIntentParsing() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let parser = IntentParser(capabilityRegistry: registry)

        let intent1 = parser.parse(transcript: "Jarvis, turn off the kitchen lights")
        XCTAssertTrue(intent1.confidence >= 0.5)
        if case .homeKitControl(let name, let char, let val) = intent1.intent {
            XCTAssertEqual(name, "kitchen-lights")
            XCTAssertEqual(char, "on")
            XCTAssertEqual(val, "false")
        } else {
            XCTFail("Expected homeKitControl intent")
        }

        let intent2 = parser.parse(transcript: "Jarvis, dim the kitchen to 30%")
        if case .homeKitControl(_, "brightness", let val) = intent2.intent {
            XCTAssertEqual(val, "30")
        } else {
            XCTFail("Expected brightness control")
        }
    }

    func testUnknownIntentWithLowConfidence() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let parser = IntentParser(capabilityRegistry: registry)

        let intent = parser.parse(transcript: "Jarvis, burn the house down")
        XCTAssertEqual(intent.confidence, 0.0)
        if case .unknown = intent.intent {
        } else {
            XCTFail("Expected unknown intent")
        }
    }

    func testSystemQueryIntent() throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let parser = IntentParser(capabilityRegistry: registry)

        let intent = parser.parse(transcript: "Jarvis, status")
        XCTAssertTrue(intent.confidence >= 0.5)
        if case .systemQuery = intent.intent {
        } else {
            XCTFail("Expected systemQuery intent")
        }
    }
}
