import XCTest
@testable import JarvisCore

/// SPEC-009 tier-witness chain. Telemetry rows must form a SHA-256 hash
/// chain where each row references the rowHash of the prior row. Any
/// tamper — a silently edited principal tag, reordered rows, or a bit
/// flip — must break verifyChain. This is the "evidence corpus can't
/// lie" contract.
final class TelemetryChainWitnessTests: XCTestCase {

    private var workspace: WorkspacePaths!
    private var store: TelemetryStore!

    override func setUpWithError() throws {
        workspace = try makeTestWorkspace()
        store = try TelemetryStore(paths: workspace)
    }

    override func tearDownWithError() throws {
        if let workspace { try? FileManager.default.removeItem(at: workspace.root) }
    }

    func testChainOfAppendsVerifies() throws {
        try store.append(record: ["k": "a"], to: "chain_test", principal: .operatorTier)
        try store.append(record: ["k": "b"], to: "chain_test", principal: .guestTier)
        try store.append(record: ["k": "c"], to: "chain_test", principal: .companion(memberID: "c-1"))

        let report = try store.verifyChain(table: "chain_test")
        XCTAssertTrue(report.isIntact, "expected intact chain, got \(report)")
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertEqual(report.hashedRows, 3)
        XCTAssertEqual(report.legacyRows, 0)
        XCTAssertNil(report.brokenAt)
    }

    func testTamperedPrincipalBreaksChain() throws {
        try store.append(record: ["k": "a"], to: "tamper_test", principal: .operatorTier)
        try store.append(record: ["k": "b"], to: "tamper_test", principal: .guestTier)
        try store.append(record: ["k": "c"], to: "tamper_test", principal: .operatorTier)

        // Rewrite middle row with a forged principal but keeping its
        // rowHash intact. verifyChain must catch the body/hash mismatch.
        let url = store.tableURL("tamper_test")
        var lines = (try String(contentsOf: url)).split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        XCTAssertEqual(lines.count, 3)
        var middle = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        middle["principal"] = "grizz"  // escalate guest → operator
        let forged = try JSONSerialization.data(withJSONObject: middle, options: [.sortedKeys])
        lines[1] = String(data: forged, encoding: .utf8)!
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)

        let report = try store.verifyChain(table: "tamper_test")
        XCTAssertFalse(report.isIntact)
        XCTAssertEqual(report.brokenAt, 2, "expected break at line 2 (the forged row)")
    }

    func testCallerSuppliedHashFieldsAreStripped() throws {
        // Any attempt to self-assert rowHash / prevRowHash must be ignored.
        // The store computes canonical hashes; client assertions cannot
        // forge chain membership.
        try store.append(
            record: ["k": "x", "rowHash": "DEADBEEF", "prevRowHash": "CAFEBABE"],
            to: "hash_strip_test",
            principal: .operatorTier
        )
        let url = store.tableURL("hash_strip_test")
        let line = try String(contentsOf: url).split(separator: "\n").first!
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(String(line).utf8)) as? [String: Any])
        XCTAssertNotEqual(obj["rowHash"] as? String, "DEADBEEF")
        XCTAssertEqual(obj["prevRowHash"] as? String, "GENESIS")
        let report = try store.verifyChain(table: "hash_strip_test")
        XCTAssertTrue(report.isIntact)
    }

    func testFirstRowLinksToGenesisSentinel() throws {
        try store.append(record: ["k": "only"], to: "genesis_test", principal: nil)
        let url = store.tableURL("genesis_test")
        let line = try XCTUnwrap(try String(contentsOf: url).split(separator: "\n").first.map(String.init))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(obj["prevRowHash"] as? String, "GENESIS")
        XCTAssertNotNil(obj["rowHash"] as? String)
    }

    func testLegacyRowsWithoutHashDoNotBreakVerification() throws {
        // Simulate a pre-chain file (no rowHash field on any row).
        let url = store.tableURL("legacy_test")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = """
        {"k":"old-a","timestamp":"2025-01-01T00:00:00Z"}
        {"k":"old-b","timestamp":"2025-01-01T00:00:01Z"}

        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        // Now append a fresh hashed row.
        try store.append(record: ["k": "new"], to: "legacy_test", principal: .operatorTier)

        let report = try store.verifyChain(table: "legacy_test")
        XCTAssertTrue(report.isIntact, "mixed legacy + hashed segment should still verify: \(report)")
        XCTAssertEqual(report.legacyRows, 2)
        XCTAssertEqual(report.hashedRows, 1)
    }

    func testCrossTableChainsAreIndependent() throws {
        try store.append(record: ["k": "a"], to: "table_x", principal: .operatorTier)
        try store.append(record: ["k": "a"], to: "table_y", principal: .operatorTier)
        try store.append(record: ["k": "b"], to: "table_x", principal: .operatorTier)

        XCTAssertTrue(try store.verifyChain(table: "table_x").isIntact)
        XCTAssertTrue(try store.verifyChain(table: "table_y").isIntact)
    }
}
