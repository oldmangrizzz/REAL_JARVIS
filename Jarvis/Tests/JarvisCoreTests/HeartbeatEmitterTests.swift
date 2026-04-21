import XCTest
@testable import JarvisCore

/// MK2-EPIC-07 acceptance: heartbeat emitter writes `heartbeat` rows with
/// the dashboard-defined contract, and the dashboard pill logic
/// (GREEN<60s, YELLOW<300s, RED otherwise) can be driven from the stored
/// timestamps.
final class HeartbeatEmitterTests: XCTestCase {

    private final class FixedProvider: HeartbeatStateProvider {
        let snapshot: HeartbeatSnapshot
        init(_ s: HeartbeatSnapshot) { self.snapshot = s }
        func currentHeartbeat() -> HeartbeatSnapshot { snapshot }
    }

    private func makeStore() throws -> (TelemetryStore, WorkspacePaths) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-heartbeat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tmp)
        let store = try TelemetryStore(paths: paths)
        return (store, paths)
    }

    private func readRows(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            }
    }

    func testTickWritesHeartbeatRowWithContract() throws {
        let (store, _) = try makeStore()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let emitter = HeartbeatEmitter(
            telemetry: store,
            provider: FixedProvider(HeartbeatSnapshot(
                voiceGateOK: true,
                tunnelClients: 3,
                memoryVersion: "mem-v42",
                lastIntentAt: when
            )),
            interval: 30
        )
        emitter.tick()
        let rows = try readRows(store.tableURL("heartbeat"))
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row["event"] as? String, "heartbeat")
        XCTAssertEqual(row["voiceGateOK"] as? Bool, true)
        XCTAssertEqual(row["tunnelClients"] as? Int, 3)
        XCTAssertEqual(row["memoryVersion"] as? String, "mem-v42")
        XCTAssertNotNil(row["lastIntentAt"] as? String)
        XCTAssertNotNil(row["timestamp"] as? String)
        XCTAssertNotNil(row["rowHash"] as? String)
    }

    func testTickOmitsLastIntentWhenAbsent() throws {
        let (store, _) = try makeStore()
        let emitter = HeartbeatEmitter(
            telemetry: store,
            provider: FixedProvider(HeartbeatSnapshot(
                voiceGateOK: false,
                tunnelClients: 0,
                memoryVersion: "mem-v0",
                lastIntentAt: nil
            )),
            interval: 30
        )
        emitter.tick()
        let rows = try readRows(store.tableURL("heartbeat"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0]["lastIntentAt"])
        XCTAssertEqual(rows[0]["voiceGateOK"] as? Bool, false)
    }

    func testMultipleTicksAppendMultipleRows() throws {
        let (store, _) = try makeStore()
        let emitter = HeartbeatEmitter(
            telemetry: store,
            provider: FixedProvider(HeartbeatSnapshot(
                voiceGateOK: true,
                tunnelClients: 1,
                memoryVersion: "v1",
                lastIntentAt: nil
            )),
            interval: 30
        )
        emitter.tick()
        emitter.tick()
        emitter.tick()
        let rows = try readRows(store.tableURL("heartbeat"))
        XCTAssertEqual(rows.count, 3)
    }

    func testHealthPillRulesFromTimestamps() throws {
        // Dashboard contract: GREEN if age < 60s, YELLOW if < 300s, else RED.
        // Validate the pure-function side of the contract so the dashboard
        // and Swift-side agree on the threshold constants.
        let now = Date()
        let ages: [(age: TimeInterval, expected: String)] = [
            (0,    "GREEN"),
            (59,   "GREEN"),
            (60,   "YELLOW"),
            (299,  "YELLOW"),
            (300,  "RED"),
            (3600, "RED")
        ]
        for (age, expected) in ages {
            let last = now.addingTimeInterval(-age)
            let pill = HeartbeatEmitterTests.pill(lastHeartbeat: last, now: now)
            XCTAssertEqual(pill, expected, "age=\(age)s should map to \(expected)")
        }
    }

    // Mirrors the dashboard's JavaScript; lives in the test file to keep
    // the production type minimal (dashboard is Python/JS, not Swift).
    static func pill(lastHeartbeat: Date?, now: Date) -> String {
        guard let last = lastHeartbeat else { return "RED" }
        let age = now.timeIntervalSince(last)
        if age < 60 { return "GREEN" }
        if age < 300 { return "YELLOW" }
        return "RED"
    }
}
