import XCTest
@testable import JarvisCore

final class DisplayCommandExecutorTests: XCTestCase {
    func testExecutorDispatchesToDisplayWithAuthorization() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let mockControlPlane = MockControlPlane()
        let mockTelemetry = MockTelemetryStore()
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: mockControlPlane, telemetry: mockTelemetry)

        let intent = ParsedIntent(
            intent: .displayAction(target: "left-monitor", action: "display-telemetry", parameters: [:]),
            confidence: 0.9,
            rawTranscript: "put telemetry on left monitor",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let auth = CommandAuthorization.voiceOperator(registry: registry)
        let result = try await executor.execute(intent: intent, authorization: auth)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.spokenText.contains("Switched"))
    }

    func testExecutorBlocksUnauthorizedDisplayAccess() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let mockControlPlane = MockControlPlane()
        let mockTelemetry = MockTelemetryStore()
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: mockControlPlane, telemetry: mockTelemetry)

        let intent = ParsedIntent(
            intent: .displayAction(target: "nonexistent-monitor", action: "display-telemetry", parameters: [:]),
            confidence: 0.9,
            rawTranscript: "put telemetry on nonexistent",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let auth = CommandAuthorization.voiceOperator(registry: registry)

        do {
            let _ = try await executor.execute(intent: intent, authorization: auth)
            XCTFail("Expected error for unauthorized display access")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Not authorized"))
        }
    }

    func testExecutorBlocksUnauthorizedHomeKitAccess() async throws {
        let paths = try makeTestWorkspace()
        let configURL = paths.root.appendingPathComponent(".jarvis/capabilities.json")
        let registry = try CapabilityRegistry(configURL: configURL)
        let mockControlPlane = MockControlPlane()
        let mockTelemetry = MockTelemetryStore()
        let executor = DisplayCommandExecutor(registry: registry, controlPlane: mockControlPlane, telemetry: mockTelemetry)

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
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Not authorized"))
        }
    }
}

class MockControlPlane {
}

class MockTelemetryStore: TelemetryStore {
    override init(paths: WorkspacePaths) throws {
        try super.init(paths: paths)
    }

    func dummy() {
        // Placeholder for test mocking
    }
}

func makeTestWorkspace() throws -> WorkspacePaths {
    let paths = try WorkspacePaths.rootDirectory()
    return paths
}
