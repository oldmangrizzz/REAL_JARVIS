import XCTest
@testable import JarvisCore

final class OscillatorTests: XCTestCase {
    final class Recorder: PhaseLockedSubscriber {
        let subscriberID: String
        var ticks: [OscillatorTick] = []
        init(_ id: String) { self.subscriberID = id }
        func onTick(_ tick: OscillatorTick) { ticks.append(tick) }
    }

    func testManualTickMonotonicSequence() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let r = Recorder("unit-a")
        runtime.oscillator.subscribe(r)

        let t1 = runtime.oscillator.manualTick()
        let t2 = runtime.oscillator.manualTick()
        let t3 = runtime.oscillator.manualTick()

        XCTAssertEqual([t1.sequence, t2.sequence, t3.sequence], [1, 2, 3])
        XCTAssertEqual(r.ticks.count, 3)
        XCTAssertEqual(r.ticks.last?.sequence, 3)
    }

    func testBPMClampedWithinBand() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        runtime.oscillator.setBPM(5)
        XCTAssertEqual(runtime.oscillator.currentBPM, 30, accuracy: 0.0001)
        runtime.oscillator.setBPM(500)
        XCTAssertEqual(runtime.oscillator.currentBPM, 180, accuracy: 0.0001)
        runtime.oscillator.setBPM(72)
        XCTAssertEqual(runtime.oscillator.currentBPM, 72, accuracy: 0.0001)
    }

    func testUnsubscribeStopsDelivery() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let r = Recorder("goodbye")
        runtime.oscillator.subscribe(r)
        runtime.oscillator.manualTick()
        runtime.oscillator.unsubscribe("goodbye")
        runtime.oscillator.manualTick()
        XCTAssertEqual(r.ticks.count, 1)
    }

    func testPhaseLockReinforceOnSteadyInPhaseCompletion() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let id = "in-phase"
        // Biological-analog jitter: 40 ticks, completion lags by ~40ms ± 80ms.
        // Tight enough to lock, loose enough to avoid flatline-penalty ceiling.
        for _ in 0..<40 {
            let tick = runtime.oscillator.manualTick()
            let jitter = Double.random(in: -80.0...80.0) / 1000.0
            let completedAt = tick.emitted.addingTimeInterval(0.040 + jitter)
            runtime.phaseLock.recordCompletion(subscriberID: id, tick: tick, completedAt: completedAt)
        }
        let score = try XCTUnwrap(runtime.phaseLock.currentScore(for: id))
        XCTAssertGreaterThanOrEqual(score.plv, 0.70)
        XCTAssertLessThanOrEqual(score.plv, 0.97)
        XCTAssertEqual(score.regulated, .reinforce)
    }

    func testPhaseLockRepelOnCatastrophicDrift() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let id = "decoupled"
        for _ in 0..<40 {
            let tick = runtime.oscillator.manualTick()
            // Drift is a full interval or more — pathological decoupling.
            let drift = Double.random(in: 900...1400) / 1000.0
            let completedAt = tick.emitted.addingTimeInterval(drift)
            runtime.phaseLock.recordCompletion(subscriberID: id, tick: tick, completedAt: completedAt)
        }
        let score = try XCTUnwrap(runtime.phaseLock.currentScore(for: id))
        XCTAssertLessThan(score.plv, 0.45)
        XCTAssertEqual(score.regulated, .repel)
    }

    func testAllScoresAggregatesMultipleSubscribers() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        for _ in 0..<16 {
            let tick = runtime.oscillator.manualTick()
            runtime.phaseLock.recordCompletion(subscriberID: "alpha", tick: tick,
                completedAt: tick.emitted.addingTimeInterval(0.004))
            runtime.phaseLock.recordCompletion(subscriberID: "bravo", tick: tick,
                completedAt: tick.emitted.addingTimeInterval(0.050))
        }
        let scores = runtime.phaseLock.allScores()
        XCTAssertEqual(scores.map(\.subscriberID), ["alpha", "bravo"])
    }
}
