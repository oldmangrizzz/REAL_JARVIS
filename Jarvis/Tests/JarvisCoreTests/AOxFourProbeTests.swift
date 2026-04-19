import XCTest
@testable import JarvisCore

final class AOxFourProbeTests: XCTestCase {
    private func writeGenesis(_ json: String, at paths: WorkspacePaths) throws {
        let dir = paths.root
            .appendingPathComponent(".jarvis", isDirectory: true)
            .appendingPathComponent("soul_anchor", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("genesis.json"), atomically: true, encoding: .utf8)
    }

    func testPersonUnoriented_whenGenesisMissing() throws {
        let paths = try makeTestWorkspace()
        // Explicitly remove the genesis created by makeTestWorkspace to test missing file
        let genesisURL = paths.root.appendingPathComponent(".jarvis/soul_anchor/genesis.json")
        try? FileManager.default.removeItem(at: genesisURL)
        
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probePerson()
        XCTAssertFalse(r.isOriented)
        XCTAssertEqual(r.confidence, 0.0, accuracy: 0.0001)
    }

    func testPersonOriented_whenRatifiedGenesisPresent() throws {
        let paths = try makeTestWorkspace()
        try writeGenesis("""
        {
          "version": "1.0.0",
          "status": "RATIFIED",
          "operator": {
            "callsign": "Grizz",
            "legal_name": "Robert Barclay Hanson",
            "credentials": "EMT-P Ret."
          }
        }
        """, at: paths)
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probePerson()
        XCTAssertTrue(r.isOriented)
        XCTAssertGreaterThanOrEqual(r.confidence, 0.75)
        XCTAssertTrue(r.payload?.contains("Grizz") == true)
    }

    func testPersonDegraded_whenStatusNotRatified() throws {
        let paths = try makeTestWorkspace()
        try writeGenesis(#"{"status":"DRAFT","operator":{"callsign":"Grizz"}}"#, at: paths)
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probePerson()
        // 0.70 < threshold 0.75 → not oriented, as designed.
        XCTAssertFalse(r.isOriented)
        XCTAssertEqual(r.confidence, 0.70, accuracy: 0.0001)
    }

    func testPlaceProducesStableFingerprint() throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let a = probe.probePlace()
        let b = probe.probePlace()
        XCTAssertEqual(a.payload, b.payload)
        XCTAssertTrue(a.payload?.contains("fp:") == true)
        XCTAssertTrue(a.payload?.contains("host:") == true)
    }

    func testTimeOrientedUnderNormalClock() throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probeTime()
        XCTAssertTrue(r.isOriented)
        XCTAssertGreaterThan(r.confidence, 0.90)
    }

    func testEventIdle_whenNoTelemetry() throws {
        let paths = try makeTestWorkspace()
        // Remove boot telemetry so event probe sees no active streams
        let bootFile = paths.root.appendingPathComponent(".jarvis/telemetry/boot_event.jsonl")
        try? FileManager.default.removeItem(at: bootFile)
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probeEvent()
        // No JSONL files present, so idle branch.
        XCTAssertFalse(r.isOriented) // 0.55 < 0.75
        XCTAssertTrue(r.payload?.contains("idle") == true ||
                      r.payload?.contains("streams:") == true)
    }

    func testEventOriented_afterTelemetryWrite() throws {
        let paths = try makeTestWorkspace()
        let telemetry = try TelemetryStore(paths: paths)
        try telemetry.append(record: ["marker": "live"], to: "heartbeat")
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let r = probe.probeEvent()
        XCTAssertTrue(r.isOriented)
        XCTAssertTrue(r.payload?.contains("heartbeat") == true)
    }

    func testRequireFullOrientationThrowsWhenDegraded() throws {
        let paths = try makeTestWorkspace()
        // Remove genesis so Person is unoriented → A&Ox < 4.
        let genesisFile = paths.root.appendingPathComponent(".jarvis/soul_anchor/genesis.json")
        try? FileManager.default.removeItem(at: genesisFile)
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        XCTAssertThrowsError(try probe.requireFullOrientation())
    }

    func testStatusCompositeMatchesOrientedAxes() throws {
        let paths = try makeTestWorkspace()
        try writeGenesis(#"{"status":"RATIFIED","operator":{"callsign":"Grizz"}}"#, at: paths)
        let telemetry = try TelemetryStore(paths: paths)
        try telemetry.append(record: ["marker": "live"], to: "heartbeat")
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let s = try probe.status()
        XCTAssertEqual(s.level, s.orientedAxes)
        XCTAssertEqual(s.results.count, 4)
    }

    func testStatusPersistsLatestFileForOutOfProcessGates() throws {
        let paths = try makeTestWorkspace()
        try writeGenesis(#"{"status":"RATIFIED","operator":{"callsign":"Grizz"}}"#, at: paths)
        let telemetry = try TelemetryStore(paths: paths)
        try telemetry.append(record: ["marker": "live"], to: "heartbeat")
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)
        let s = try probe.status()

        let latestURL = probe.latestStatusURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: latestURL.path),
                      "aox4_latest.json was not written at \(latestURL.path)")

        let data = try Data(contentsOf: latestURL)
        let decoded = try JSONDecoder().decode(AOxStatus.self, from: data)
        XCTAssertEqual(decoded.level, s.level)
        XCTAssertEqual(decoded.results.count, 4)
        XCTAssertEqual(decoded.timestamp, s.timestamp)
    }

    func testStatusRewritesLatestFileAtomically() throws {
        let paths = try makeTestWorkspace()
        try writeGenesis(#"{"status":"RATIFIED","operator":{"callsign":"Grizz"}}"#, at: paths)
        let telemetry = try TelemetryStore(paths: paths)
        let probe = AOxFourProbe(paths: paths, telemetry: telemetry)

        _ = try probe.status()
        let firstMtime = try FileManager.default.attributesOfItem(atPath: probe.latestStatusURL.path)[.modificationDate] as? Date

        // Minimum delay for mtime granularity on some filesystems.
        Thread.sleep(forTimeInterval: 1.05)

        _ = try probe.status()
        let secondMtime = try FileManager.default.attributesOfItem(atPath: probe.latestStatusURL.path)[.modificationDate] as? Date

        XCTAssertNotNil(firstMtime)
        XCTAssertNotNil(secondMtime)
        XCTAssertGreaterThan(secondMtime!, firstMtime!)
    }
}
