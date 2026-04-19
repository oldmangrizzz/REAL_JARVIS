import XCTest
@testable import JarvisCore

final class ARCHarnessBridgeWebSocketTests: XCTestCase {

    // MARK: - WebSocket broadcaster wiring

    func testSendJSONCreatesWebSocketTaskViaTelemetry() async throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        let engine = StubPhysicsEngine()

        let bridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:18765")!,
            telemetry: telemetry,
            engine: engine
        )

        // Emit a state — this should attempt a WebSocket connection
        await bridge.emitState(["status": "test"])

        // Check telemetry for either "WebSocket connected" or "WebSocket send failed"
        // (the broadcaster likely isn't running, so expect a send failure after connect)
        let eventsURL = telemetry.tableURL("arc_agi_events")
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2s for async WebSocket attempt

        guard FileManager.default.fileExists(atPath: eventsURL.path) else {
            XCTFail("Telemetry file should exist after emitState")
            return
        }

        let content = try String(contentsOf: eventsURL, encoding: .utf8)
        // We should see either a connect log or a send-failure log
        let hasConnectLog = content.contains("WebSocket connected")
        let hasSendFailLog = content.contains("WebSocket send failed")
        XCTAssertTrue(hasConnectLog || hasSendFailLog,
                      "Expected WebSocket telemetry log but found: \(content.suffix(500))")

        await bridge.stop()
    }

    func testStopCancelsWebSocketViaTelemetry() async throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        let engine = StubPhysicsEngine()

        let bridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:18766")!,
            telemetry: telemetry,
            engine: engine
        )

        // Emit something to create the WebSocket task
        await bridge.emitState(["status": "pre-stop"])
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

        // Stop should cancel the WebSocket task
        await bridge.stop()

        // Emit after stop — should reconnect fresh
        await bridge.emitState(["status": "post-stop"])
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let eventsURL = telemetry.tableURL("arc_agi_events")
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let content = try String(contentsOf: eventsURL, encoding: .utf8)
            // Should see at least one "WebSocket connected" entry after reconnection
            let connectCount = content.components(separatedBy: "WebSocket connected").count - 1
            XCTAssertTrue(connectCount >= 1,
                          "Expected at least one WebSocket connected log, found \(connectCount)")
        }
    }

    func testEmitMethodsForwardCorrectTypes() async throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        let engine = StubPhysicsEngine()

        let bridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:18767")!,
            telemetry: telemetry,
            engine: engine
        )

        // All emit methods should complete without crashing
        await bridge.emitHypothesis(["h": "value"])
        await bridge.emitGrid(["g": "value"])
        await bridge.emitScore(["s": "value"])
        await bridge.emitAction(["a": "value"])

        await bridge.stop()
    }

    func testBridgeStopsCleanlyWithNoWebSocket() async throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)

        let bridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:18768")!,
            telemetry: telemetry
        )

        // Stop without ever calling emit — should not crash
        await bridge.stop()
    }
}