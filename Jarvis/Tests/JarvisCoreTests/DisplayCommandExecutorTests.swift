import XCTest
@testable import JarvisCore

final class DisplayCommandExecutorTests: XCTestCase {
    func testExecutorDispatchesToDisplayWithAuthorization() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let telemetry = try TelemetryStore(paths: paths)
        let controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: controlPlane, telemetry: telemetry)

        let intent = ParsedIntent(
            intent: .displayAction(target: "left-monitor", action: "display-telemetry", parameters: [:]),
            confidence: 0.9,
            rawTranscript: "put telemetry on left monitor",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let auth = CommandAuthorization.voiceOperator(registry: registry)
        let result = try await executor.execute(intent: intent, authorization: auth)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.spokenText.contains("HomeKit") || result.spokenText.contains("Switched") || result.spokenText.contains("Launched"),
                      "Expected success message, got: \(result.spokenText)")
    }

    func testExecutorBlocksUnauthorizedDisplayAccess() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let telemetry = try TelemetryStore(paths: paths)
        let controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: controlPlane, telemetry: telemetry)

        let intent = ParsedIntent(
            intent: .displayAction(target: "left-monitor", action: "display-telemetry", parameters: [:]),
            confidence: 0.9,
            rawTranscript: "put telemetry on nonexistent",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        // tunnelClient only has its own deviceID in allowedDisplays — left-monitor is not authorized
        let auth = CommandAuthorization.tunnelClient(deviceID: "own-device", registry: registry)

        do {
            let _ = try await executor.execute(intent: intent, authorization: auth)
            XCTFail("Expected error for unauthorized display access")
        } catch let error as JarvisError {
            XCTAssertTrue(error.description.contains("Not authorized"),
                          "Expected 'Not authorized' in error, got: \(error.description)")
        } catch {
            XCTFail("Expected JarvisError, got: \(error)")
        }
    }

    func testExecutorBlocksUnauthorizedHomeKitAccess() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let telemetry = try TelemetryStore(paths: paths)
        let controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: controlPlane, telemetry: telemetry)

        let intent = ParsedIntent(
            intent: .homeKitControl(accessoryName: "unregistered-lights", characteristic: "on", value: "true"),
            confidence: 0.8,
            rawTranscript: "turn on unregistered",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let auth = CommandAuthorization.tunnelClient(deviceID: "own-device", registry: registry)

        do {
            let _ = try await executor.execute(intent: intent, authorization: auth)
            XCTFail("Expected error for unauthorized HomeKit access")
        } catch let error as JarvisError {
            XCTAssertTrue(error.description.contains("Not authorized"),
                          "Expected 'Not authorized' in error, got: \(error.description)")
        } catch {
            XCTFail("Expected JarvisError, got: \(error)")
        }
    }
}