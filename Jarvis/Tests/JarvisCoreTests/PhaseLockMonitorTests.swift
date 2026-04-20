import XCTest
@testable import JarvisCore

final class PhaseLockMonitorTests: XCTestCase {
    private func makeTelemetry() throws -> TelemetryStore {
        let ws = try makeTestWorkspace()
        return try TelemetryStore(paths: ws)
    }

    private func tick(seq: UInt64, scheduled: Date, driftMs: Double, intervalMs: Double = 1000.0) -> OscillatorTick {
        OscillatorTick(
            sequence: seq,
            scheduled: scheduled,
            emitted: scheduled.addingTimeInterval(driftMs / 1000.0),
            driftMilliseconds: driftMs,
            intervalMilliseconds: intervalMs
        )
    }

    // Helper: feed N completions where completion-emitted drift (ms) comes
    // from `drifts`. `scoreEvery=1` in config to score on every completion.
    private func feed(monitor: PhaseLockMonitor, subscriber: String, drifts: [Double], intervalMs: Double = 1000.0) {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for (i, driftMs) in drifts.enumerated() {
            let t = tick(
                seq: UInt64(i + 1),
                scheduled: base.addingTimeInterval(Double(i) * (intervalMs / 1000.0)),
                driftMs: 0,
                intervalMs: intervalMs
            )
            let completedAt = t.emitted.addingTimeInterval(driftMs / 1000.0)
            monitor.recordCompletion(subscriberID: subscriber, tick: t, completedAt: completedAt)
        }
    }

    func testNoScoreUntilCadenceReached() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t, configuration: .init(windowSize: 32, scoreEvery: 8))
        feed(monitor: m, subscriber: "sub-A", drifts: Array(repeating: 2.0, count: 4))
        XCTAssertNil(m.currentScore(for: "sub-A"), "should not score before scoreEvery cadence")
    }

    func testStableLowDriftProducesReinforce() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 16, scoreEvery: 8))
        // Small non-zero jitter → healthy PLV band (not flatlined).
        let drifts = (0..<16).map { i -> Double in (i % 2 == 0) ? 40.0 : 50.0 }
        feed(monitor: m, subscriber: "sub-healthy", drifts: drifts)

        guard let score = m.currentScore(for: "sub-healthy") else {
            return XCTFail("expected score after cadence")
        }
        XCTAssertEqual(score.regulated, .reinforce,
                       "healthy-band PLV (\(score.plv)) should reinforce")
        XCTAssertGreaterThan(score.plv, 0.70)
        XCTAssertLessThanOrEqual(score.plv, 0.97)
    }

    func testHighVarianceDriftRepels() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 16, scoreEvery: 8))
        // Drifts spanning a full interval → normalized stddev ≈ 1 → plv ≈ 0.
        let drifts = (0..<16).map { i -> Double in (i % 2 == 0) ? -900.0 : 900.0 }
        feed(monitor: m, subscriber: "sub-chaos", drifts: drifts)

        guard let score = m.currentScore(for: "sub-chaos") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.regulated, .repel)
        XCTAssertLessThan(score.plv, 0.45)
    }

    func testPerfectLockIsFlatlinePenalizedIntoHealthyBand() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 16, scoreEvery: 8))
        // Zero drift, zero variance → rawPLV = 1.0, flatline penalty applies.
        feed(monitor: m, subscriber: "sub-flat", drifts: Array(repeating: 0.0, count: 16))
        guard let score = m.currentScore(for: "sub-flat") else {
            return XCTFail("expected score")
        }
        XCTAssertLessThanOrEqual(score.plv, 0.95 + 1e-9,
                                 "flatline penalty should cap plv below 0.96")
        XCTAssertEqual(score.regulated, .reinforce,
                       "post-penalty plv should still land in healthy band")
    }

    func testResetClearsSubscriberState() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t, configuration: .init(scoreEvery: 1))
        feed(monitor: m, subscriber: "sub-reset", drifts: [10, 20, 30, 40, 50, 60, 70, 80])
        XCTAssertNotNil(m.currentScore(for: "sub-reset"))
        m.reset(subscriberID: "sub-reset")
        XCTAssertNil(m.currentScore(for: "sub-reset"))
    }

    func testAllScoresReturnsStableSortedByID() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 8, scoreEvery: 8))
        feed(monitor: m, subscriber: "z-sub", drifts: Array(repeating: 5.0, count: 8))
        feed(monitor: m, subscriber: "a-sub", drifts: Array(repeating: 5.0, count: 8))
        feed(monitor: m, subscriber: "m-sub", drifts: Array(repeating: 5.0, count: 8))
        let scores = m.allScores()
        XCTAssertEqual(scores.map(\.subscriberID), ["a-sub", "m-sub", "z-sub"])
    }

    func testWindowIsBoundedBySize() throws {
        let t = try makeTelemetry()
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 8, scoreEvery: 1))
        // Feed 20 samples; only the last 8 should influence the score.
        let early = Array(repeating: 500.0, count: 12)   // chaos prefix
        let late  = Array(repeating: 5.0, count: 8)      // clean suffix
        feed(monitor: m, subscriber: "sub-window", drifts: early + late)
        guard let score = m.currentScore(for: "sub-window") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.sampleCount, 8)
        XCTAssertEqual(score.meanDriftMilliseconds, 5.0, accuracy: 0.001,
                       "early chaotic samples must be evicted from window")
    }

    func testTelemetryReceivesPLVRecord() throws {
        let ws = try makeTestWorkspace()
        let t = try TelemetryStore(paths: ws)
        let m = PhaseLockMonitor(telemetry: t,
                                 configuration: .init(windowSize: 8, scoreEvery: 8))
        feed(monitor: m, subscriber: "sub-telem", drifts: Array(repeating: 10.0, count: 8))
        let url = t.tableURL("oscillator_plv")
        let lines = try String(contentsOf: url).split(separator: "\n")
        XCTAssertFalse(lines.isEmpty, "oscillator_plv table should have at least one row")
        let last = String(lines.last!)
        XCTAssertTrue(last.contains("\"subscriber\":\"sub-telem\""), last)
        XCTAssertTrue(last.contains("\"event\":\"plv_score\""), last)
    }
}
