import XCTest
import CryptoKit
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

    func testAppendWithResponderPrincipalWritesRoleScopedToken() throws {
        let (store, _) = try makeStore()
        try store.append(record: ["kind": "event"], to: "witness_test", principal: .responder(role: .emt))
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows[0]["principal"] as? String, "responder:emt")
    }

    func testAppendWithGuestPrincipalWritesGuestToken() throws {
        let (store, _) = try makeStore()
        try store.append(record: ["kind": "event"], to: "witness_test", principal: .guestTier)
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertEqual(rows[0]["principal"] as? String, "guest")
    }

    func testRowHashChainLinksAcrossAppends() throws {
        let (store, _) = try makeStore()
        try store.append(record: ["n": 1], to: "chain_test", principal: .operatorTier)
        try store.append(record: ["n": 2], to: "chain_test", principal: .operatorTier)
        try store.append(record: ["n": 3], to: "chain_test", principal: .operatorTier)
        let rows = try readLines(store.tableURL("chain_test"))
        XCTAssertEqual(rows.count, 3)
        // Every row has both rowHash and prevRowHash fields.
        for row in rows {
            XCTAssertNotNil(row["rowHash"] as? String)
            XCTAssertNotNil(row["prevRowHash"] as? String)
        }
        // row[n].prevRowHash == row[n-1].rowHash forms the chain.
        XCTAssertEqual(rows[1]["prevRowHash"] as? String, rows[0]["rowHash"] as? String)
        XCTAssertEqual(rows[2]["prevRowHash"] as? String, rows[1]["rowHash"] as? String)
        // Chain is tamper-evident: verify returns no break.
        let report = try store.verifyChain(table: "chain_test")
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertEqual(report.hashedRows, 3)
        XCTAssertNil(report.brokenAt)
    }

    func testCallerSuppliedRowHashIsStripped() throws {
        let (store, _) = try makeStore()
        // Caller attempts to pre-assert hash chain values. Store must
        // strip them and compute its own, otherwise an attacker could
        // forge continuity.
        try store.append(
            record: ["kind": "event", "rowHash": "DEADBEEF", "prevRowHash": "DEADBEEF"],
            to: "witness_test",
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("witness_test"))
        XCTAssertNotEqual(rows[0]["rowHash"] as? String, "DEADBEEF")
        XCTAssertNotEqual(rows[0]["prevRowHash"] as? String, "DEADBEEF")
        XCTAssertEqual((rows[0]["rowHash"] as? String)?.count, 64)
    }

    func testSecondStoreInstanceResumesChainFromTail() throws {
        let (store1, paths) = try makeStore()
        try store1.append(record: ["n": 1], to: "resume_test", principal: .operatorTier)
        try store1.append(record: ["n": 2], to: "resume_test", principal: .operatorTier)

        // New store instance on same paths must pick the chain back up
        // from the tail rowHash rather than restarting at genesis.
        let store2 = try TelemetryStore(paths: paths)
        try store2.append(record: ["n": 3], to: "resume_test", principal: .operatorTier)

        let rows = try readLines(store2.tableURL("resume_test"))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[2]["prevRowHash"] as? String, rows[1]["rowHash"] as? String,
                       "second store must resume chain from tail, not reset to genesis")
        XCTAssertNil(try store2.verifyChain(table: "resume_test").brokenAt)
    }

    // MARK: - Additional coverage

    func testFirstRowPrevHashIsGenesisSentinel() throws {
        // The genesis marker is a concrete non-empty string; a silent change
        // to it would break verifyChain's starting state and every stored
        // chain globally, so lock the sentinel value down.
        let (store, _) = try makeStore()
        try store.append(record: ["first": true], to: "genesis_test", principal: .operatorTier)
        let rows = try readLines(store.tableURL("genesis_test"))
        XCTAssertEqual(rows[0]["prevRowHash"] as? String, "GENESIS",
                       "first row must link to the 'GENESIS' sentinel")
    }

    func testVerifyChainOnMissingTableReturnsEmptyIntactReport() throws {
        let (store, _) = try makeStore()
        let report = try store.verifyChain(table: "never_written")
        XCTAssertEqual(report.totalRows, 0)
        XCTAssertEqual(report.hashedRows, 0)
        XCTAssertEqual(report.legacyRows, 0)
        XCTAssertNil(report.brokenAt)
        XCTAssertTrue(report.isIntact, "an absent table must report intact, not throw")
        XCTAssertEqual(report.table, "never_written")
    }

    func testVerifyChainDetectsTamperedPrincipalMidFile() throws {
        // Any edit to a committed row (including a silent principal swap)
        // must break the chain at that row. Write three rows, then flip
        // the principal on row 2 from "grizz" to "guest" on disk. verifyChain
        // must report brokenAt = 2.
        let (store, _) = try makeStore()
        try store.append(record: ["n": 1], to: "tamper_test", principal: .operatorTier)
        try store.append(record: ["n": 2], to: "tamper_test", principal: .operatorTier)
        try store.append(record: ["n": 3], to: "tamper_test", principal: .operatorTier)

        let url = store.tableURL("tamper_test")
        var text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 3)
        // Flip the principal field in row 2; leave the rowHash untouched
        // so the mismatch is the tamper signal, not a shape error.
        let tamperedLine2 = lines[1].replacingOccurrences(of: "\"principal\":\"grizz\"", with: "\"principal\":\"guest\"")
        XCTAssertNotEqual(tamperedLine2, lines[1], "sanity: tamper must actually change the line")
        text = ([lines[0], tamperedLine2, lines[2]].joined(separator: "\n")) + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let report = try store.verifyChain(table: "tamper_test")
        XCTAssertEqual(report.brokenAt, 2, "chain break must point at the tampered line")
        XCTAssertFalse(report.isIntact)
    }

    func testVerifyChainDetectsBrokenPrevRowHashLink() throws {
        // Even if the row's own rowHash is internally consistent, a bad
        // prevRowHash must fail the chain — otherwise an attacker who
        // controlled row insertion could splice in forged history.
        let (store, _) = try makeStore()
        try store.append(record: ["n": 1], to: "link_test", principal: .operatorTier)
        try store.append(record: ["n": 2], to: "link_test", principal: .operatorTier)

        let url = store.tableURL("link_test")
        var rows = try readLines(url)
        // Corrupt prevRowHash on row 2 with a plausible-looking sha256 value
        // and recompute the row's own rowHash so row-internal validation
        // would pass — the only remaining break signal is the link.
        rows[1]["prevRowHash"] = String(repeating: "a", count: 64)
        var body = rows[1]
        body.removeValue(forKey: "rowHash")
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let newHash = bodyData.sha256HexForTest()
        rows[1]["rowHash"] = newHash

        let line0 = try JSONSerialization.data(withJSONObject: rows[0], options: [.sortedKeys])
        let line1 = try JSONSerialization.data(withJSONObject: rows[1], options: [.sortedKeys])
        let rebuilt = String(data: line0, encoding: .utf8)! + "\n" + String(data: line1, encoding: .utf8)! + "\n"
        try rebuilt.write(to: url, atomically: true, encoding: .utf8)

        let report = try store.verifyChain(table: "link_test")
        XCTAssertEqual(report.brokenAt, 2,
                       "forged prevRowHash must fail the chain even if row's own hash is self-consistent")
    }

    func testVerifyChainCountsLegacyRowsAndResumesOnNextHashed() throws {
        // A legacy row (no rowHash field) resets the chain to genesis; the
        // next hashed row MUST carry prevRowHash == "GENESIS" for the chain
        // to re-seal. Simulate a migration gap: one legacy row at line 1,
        // two fresh hashed rows after.
        let (store, _) = try makeStore()
        let url = store.tableURL("mixed_test")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Write one legacy row directly (no rowHash, no prevRowHash).
        let legacy = #"{"kind":"legacy","note":"pre-spec-009"}"# + "\n"
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        // Now use the store API to append two fresh rows. Because the
        // existing tail row has no rowHash, tailRowHashUnlocked returns nil,
        // and the store primes the chain from genesis — exactly the
        // post-migration behavior we need to lock in.
        try store.append(record: ["n": 1], to: "mixed_test", principal: .operatorTier)
        try store.append(record: ["n": 2], to: "mixed_test", principal: .operatorTier)

        let report = try store.verifyChain(table: "mixed_test")
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertEqual(report.legacyRows, 1, "the single pre-hash row must count as legacy")
        XCTAssertEqual(report.hashedRows, 2, "both new rows must validate")
        XCTAssertNil(report.brokenAt, "legacy → hashed transition must not break the chain")
    }

    func testLogExecutionTraceWithoutPrincipalOmitsField() throws {
        // Principal is optional on logExecutionTrace; when absent, the row
        // must NOT invent a tier token — legacy / system-source traces
        // stay principal-less rather than impersonating operator.
        let (store, _) = try makeStore()
        try store.logExecutionTrace(
            workflowID: "watchdog",
            stepID: "heartbeat",
            inputContext: "tick",
            outputResult: "ok",
            status: "success"
        )
        let rows = try readLines(store.tableURL("execution_traces"))
        XCTAssertNil(rows[0]["principal"],
                     "system-source traces must not invent a principal tag")
        XCTAssertEqual(rows[0]["workflowId"] as? String, "watchdog")
    }

    func testAppendWithNestedDictAndArrayRoundTrips() throws {
        // Telemetry rows sometimes carry structured payloads (e.g. intent
        // parse trees, capability sets). Canonical JSON with sortedKeys
        // must preserve nested objects and arrays through the append +
        // read-back path, and the chain must still seal.
        let (store, _) = try makeStore()
        let nested: [String: Any] = [
            "intent": "status",
            "context": [
                "location": "kitchen",
                "devices": ["lights", "speaker"]
            ]
        ]
        try store.append(record: nested, to: "nested_test", principal: .operatorTier)
        let rows = try readLines(store.tableURL("nested_test"))
        let ctx = try XCTUnwrap(rows[0]["context"] as? [String: Any])
        XCTAssertEqual(ctx["location"] as? String, "kitchen")
        XCTAssertEqual(ctx["devices"] as? [String], ["lights", "speaker"])
        XCTAssertNil(try store.verifyChain(table: "nested_test").brokenAt)
    }

    func testChainReportIsIntactReflectsBrokenAt() {
        let clean = TelemetryChainReport(table: "t", totalRows: 3, hashedRows: 3, legacyRows: 0, brokenAt: nil)
        let broken = TelemetryChainReport(table: "t", totalRows: 3, hashedRows: 2, legacyRows: 0, brokenAt: 2)
        XCTAssertTrue(clean.isIntact)
        XCTAssertFalse(broken.isIntact)
        XCTAssertNotEqual(clean, broken, "report must be Equatable on brokenAt")
    }
}

// Test-local sha256 helper so the tamper fixture can rebuild a legitimate
// row hash without exposing the store's private hasher.
private extension Data {
    func sha256HexForTest() -> String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
