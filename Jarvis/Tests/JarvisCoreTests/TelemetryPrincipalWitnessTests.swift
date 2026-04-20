import XCTest
@testable import JarvisCore

/// SPEC-009 evidence-corpus hardening: every telemetry row gets witnessed
/// by the bound principal's tier token so the chain of custody can answer
/// "who was Jarvis serving when this was emitted?"
final class TelemetryPrincipalWitnessTests: XCTestCase {

    private func makeStore() throws -> (TelemetryStore, WorkspacePaths) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-principal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tmp)
        let store = try TelemetryStore(paths: paths)
        return (store, paths)
    }

    private func readLines(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            }
    }

    func testAppendWithoutPrincipalLeavesFieldAbsent() throws {
        let (store, _) = try makeStore()
        try store.append(record: ["kind": "legacy"], to: "witness_test")
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0]["principal"], "legacy path must not invent a principal field")
    }

    func testAppendWithOperatorPrincipalWritesGrizzToken() throws {
        let (store, _) = try makeStore()
        try store.append(record: ["kind": "event"], to: "witness_test", principal: .operatorTier)
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows[0]["principal"] as? String, "grizz")
    }

    func testAppendWithCompanionPrincipalWritesMemberScopedToken() throws {
        let (store, _) = try makeStore()
        try store.append(
            record: ["kind": "event"],
            to: "witness_test",
            principal: .companion(memberID: "melissa")
        )
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows[0]["principal"] as? String, "companion:melissa")
    }

    func testPrincipalParameterOverridesCallerSuppliedField() throws {
        // CANON: client-asserted principal fields must never win over the
        // server-resolved principal. If a caller merges in "principal":"grizz"
        // from an untrusted source, the explicit param still overrides.
        let (store, _) = try makeStore()
        try store.append(
            record: ["kind": "event", "principal": "grizz"],
            to: "witness_test",
            principal: .guestTier
        )
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows[0]["principal"] as? String, "guest",
                       "explicit principal param must override caller-supplied key")
    }

    func testLogExecutionTraceCarriesPrincipal() throws {
        let (store, _) = try makeStore()
        try store.logExecutionTrace(
            workflowID: "voice-command-router",
            stepID: "spec-009-companion-policy",
            inputContext: "jarvis shutdown",
            outputResult: "companion:destructive-or-admin:operator-only",
            status: "command_refused",
            principal: .companion(memberID: "melissa")
        )
        let rows = try readLines(store.tableURL("execution_traces"))
        XCTAssertEqual(rows[0]["principal"] as? String, "companion:melissa")
        XCTAssertEqual(rows[0]["stepId"] as? String, "spec-009-companion-policy")
    }
}
