import XCTest
@testable import JarvisCore

/// Phase 5: verify the HomeKit → Home Assistant call-service mapping and
/// the N8NBridge wire-through in `DisplayCommandExecutor`.
final class DisplayCommandExecutorHAMappingTests: XCTestCase {

    // MARK: - Pure mapping

    func testMapHomeKitToHA_onCharacteristic_mapsToLightTurnOn() {
        let m = DisplayCommandExecutor.mapHomeKitToHA(
            accessory: "downstairs-lights",
            characteristic: "on",
            value: "true"
        )
        XCTAssertEqual(m.domain, "light")
        XCTAssertEqual(m.service, "turn_on")
        XCTAssertEqual(m.entityId, "group.downstairs_lights")
    }

    func testMapHomeKitToHA_offCharacteristic_mapsToLightTurnOff() {
        let m = DisplayCommandExecutor.mapHomeKitToHA(
            accessory: "upstairs lights",
            characteristic: "on",
            value: "false"
        )
        XCTAssertEqual(m.service, "turn_off")
        XCTAssertEqual(m.entityId, "group.upstairs_lights")
    }

    func testMapHomeKitToHA_brightness_includesPercent() {
        let m = DisplayCommandExecutor.mapHomeKitToHA(
            accessory: "downstairs",
            characteristic: "brightness",
            value: "75"
        )
        XCTAssertEqual(m.service, "turn_on")
        XCTAssertEqual(m.data["brightness_pct"] as? Int, 75)
    }

    func testMapHomeKitToHA_brightnessClamped() {
        let hi = DisplayCommandExecutor.mapHomeKitToHA(accessory: "x", characteristic: "brightness", value: "999")
        XCTAssertEqual(hi.data["brightness_pct"] as? Int, 100)
        let lo = DisplayCommandExecutor.mapHomeKitToHA(accessory: "x", characteristic: "brightness", value: "-5")
        XCTAssertEqual(lo.data["brightness_pct"] as? Int, 0)
    }

    func testHAEntityID_passesThroughExplicitEntityID() {
        XCTAssertEqual(
            DisplayCommandExecutor.haEntityID(for: "light.kitchen_strip"),
            "light.kitchen_strip"
        )
    }

    func testHAEntityID_returnsNilForUnknown() {
        XCTAssertNil(DisplayCommandExecutor.haEntityID(for: "unknown"))
        XCTAssertNil(DisplayCommandExecutor.haEntityID(for: ""))
    }

    func testHAEntityID_slugifiesFreeformName() {
        XCTAssertEqual(
            DisplayCommandExecutor.haEntityID(for: "Kitchen Counter"),
            "light.kitchen_counter"
        )
    }

    // MARK: - Wire-through via N8NBridge mock

    func testRouteToHomeKit_callsN8NWebhookWithMappedPayload() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let telemetry = try TelemetryStore(paths: paths)
        let controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)

        let transport = N8NBridgeTests.MockTransport()
        let body = try JSONSerialization.data(withJSONObject: ["ok": true])
        transport.response = (body, HTTPURLResponse(
            url: URL(string: "http://192.168.4.119:5678/webhook/jarvis/ha/call-service")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!)
        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )

        let executor = DisplayCommandExecutor(
            registry: registry,
            controlPlane: controlPlane,
            telemetry: telemetry,
            n8nBridge: bridge
        )

        // Use an accessory name that's actually in the allowed set to avoid
        // authorization failure. Borrow whatever the registry provides.
        guard let accessoryID = registry.allAccessoryIDs.first else {
            throw XCTSkip("No accessories registered in test fixture")
        }
        let intent = ParsedIntent(
            intent: .homeKitControl(accessoryName: accessoryID, characteristic: "on", value: "true"),
            confidence: 0.9,
            rawTranscript: "turn on \(accessoryID)",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        let auth = CommandAuthorization.voiceOperator(registry: registry)

        let result = try await executor.execute(intent: intent, authorization: auth)

        XCTAssertTrue(result.success)
        XCTAssertEqual(
            transport.capturedRequest?.url?.absoluteString,
            "http://192.168.4.119:5678/webhook/jarvis/ha/call-service"
        )
        guard let body = transport.capturedBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("Expected JSON body")
        }
        XCTAssertEqual(json["domain"] as? String, "light")
        XCTAssertEqual(json["service"] as? String, "turn_on")
    }

    func testRouteToHomeKit_withoutBridge_fallsBackToQueuedStub() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let telemetry = try TelemetryStore(paths: paths)
        let controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)

        let executor = DisplayCommandExecutor(
            registry: registry,
            controlPlane: controlPlane,
            telemetry: telemetry
        )
        guard let accessoryID = registry.allAccessoryIDs.first else {
            throw XCTSkip("No accessories registered in test fixture")
        }
        let intent = ParsedIntent(
            intent: .homeKitControl(accessoryName: accessoryID, characteristic: "on", value: "true"),
            confidence: 0.9,
            rawTranscript: "turn on \(accessoryID)",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        let auth = CommandAuthorization.voiceOperator(registry: registry)

        let result = try await executor.execute(intent: intent, authorization: auth)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.spokenText.contains("queued"))
    }
}
