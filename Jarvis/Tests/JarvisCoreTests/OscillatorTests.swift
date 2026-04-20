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

    // MARK: - MasterOscillator direct-construction branches

    func testConfigurationIntervalSeconds() {
        XCTAssertEqual(MasterOscillator.Configuration(bpm: 60).intervalSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(MasterOscillator.Configuration(bpm: 120).intervalSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(MasterOscillator.Configuration(bpm: 30).intervalSeconds, 2.0, accuracy: 1e-9)
    }

    func testIsRunningTogglesWithStartStop() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(
            telemetry: tel,
            configuration: .init(bpm: 600, telemetryEvery: 1000)  // 100ms interval, rare telemetry
        )
        XCTAssertFalse(osc.isRunning)
        osc.start()
        XCTAssertTrue(osc.isRunning)
        // Double-start is a no-op.
        osc.start()
        XCTAssertTrue(osc.isRunning)
        osc.stop()
        XCTAssertFalse(osc.isRunning)
        osc.stop()  // double-stop no-op
        XCTAssertFalse(osc.isRunning)
    }

    func testManualTickDriftAndInterval() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel, configuration: .init(bpm: 60))  // 1s interval
        let base = Date(timeIntervalSince1970: 10_000)
        let t1 = osc.manualTick(at: base)
        XCTAssertEqual(t1.sequence, 1)
        XCTAssertEqual(t1.intervalMilliseconds, 1000, accuracy: 1e-6)
        // First tick scheduled == emitted → drift 0.
        XCTAssertEqual(t1.driftMilliseconds, 0, accuracy: 1e-6)

        // Emit the next tick 1.25s later: scheduled = base+1.0, drift = +250ms.
        let t2 = osc.manualTick(at: base.addingTimeInterval(1.25))
        XCTAssertEqual(t2.sequence, 2)
        XCTAssertEqual(t2.driftMilliseconds, 250, accuracy: 1e-6)
    }

    func testWeakSubscriberIsReleased() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel)
        let held = Recorder("sticky")
        osc.subscribe(held)

        // Scope an ephemeral subscriber so ARC releases it.
        do {
            let ephemeral = Recorder("ephemeral")
            osc.subscribe(ephemeral)
            osc.manualTick()
            XCTAssertEqual(ephemeral.ticks.count, 1)
        }

        // Next tick must not crash and must still deliver to `held`.
        let tick = osc.manualTick()
        XCTAssertEqual(tick.sequence, 2)
        XCTAssertEqual(held.ticks.count, 2)
    }

    func testSetBPMOutsideBandClampsWithoutDesync() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel, configuration: .init(bpm: 60, minBPM: 40, maxBPM: 120))
        osc.setBPM(10)
        XCTAssertEqual(osc.currentBPM, 40)
        osc.setBPM(9999)
        XCTAssertEqual(osc.currentBPM, 120)
        osc.setBPM(72)
        XCTAssertEqual(osc.currentBPM, 72)
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

    // MARK: - Additional coverage

    func testOscillatorTickEquatableAndCodableRoundTrip() throws {
        let base = Date(timeIntervalSince1970: 20_000)
        let a = OscillatorTick(sequence: 7, scheduled: base,
                               emitted: base.addingTimeInterval(0.01),
                               driftMilliseconds: 10, intervalMilliseconds: 1000)
        let b = OscillatorTick(sequence: 7, scheduled: base,
                               emitted: base.addingTimeInterval(0.01),
                               driftMilliseconds: 10, intervalMilliseconds: 1000)
        let c = OscillatorTick(sequence: 8, scheduled: base,
                               emitted: base, driftMilliseconds: 0, intervalMilliseconds: 1000)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        let roundTripped = try dec.decode(OscillatorTick.self, from: enc.encode(a))
        XCTAssertEqual(roundTripped, a)
    }

    func testConfigurationDefaultsMatchContract() {
        let cfg = MasterOscillator.Configuration()
        XCTAssertEqual(cfg.bpm, 60, accuracy: 1e-9)
        XCTAssertEqual(cfg.minBPM, 30, accuracy: 1e-9)
        XCTAssertEqual(cfg.maxBPM, 180, accuracy: 1e-9)
        XCTAssertEqual(cfg.telemetryEvery, 30)
        XCTAssertEqual(cfg.intervalSeconds, 1.0, accuracy: 1e-9)
    }

    func testMultipleLiveSubscribersAllReceiveSameTick() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel)
        let a = Recorder("a"), b = Recorder("b"), c = Recorder("c")
        osc.subscribe(a); osc.subscribe(b); osc.subscribe(c)
        let tick = osc.manualTick()
        XCTAssertEqual(a.ticks.map(\.sequence), [tick.sequence])
        XCTAssertEqual(b.ticks.map(\.sequence), [tick.sequence])
        XCTAssertEqual(c.ticks.map(\.sequence), [tick.sequence])
    }

    func testResubscribeWithSameIDReplacesPriorEntry() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel)
        let first = Recorder("dup")
        let second = Recorder("dup")
        osc.subscribe(first)
        osc.subscribe(second) // same subscriberID — replaces first
        osc.manualTick()
        XCTAssertEqual(first.ticks.count, 0, "first recorder must be dropped by re-subscribe")
        XCTAssertEqual(second.ticks.count, 1)
    }

    func testStopWithoutStartIsNoOp() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel)
        XCTAssertFalse(osc.isRunning)
        osc.stop() // must not crash or change state
        XCTAssertFalse(osc.isRunning)
    }

    func testSetBPMToCurrentValueIsStable() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel, configuration: .init(bpm: 72))
        osc.setBPM(72)
        XCTAssertEqual(osc.currentBPM, 72, accuracy: 1e-9)
        XCTAssertFalse(osc.isRunning, "setBPM with no change must not trigger a restart into running state")
    }

    func testManualTickWithNoSubscribersDoesNotCrash() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel)
        let tick = osc.manualTick()
        XCTAssertEqual(tick.sequence, 1)
        XCTAssertEqual(tick.driftMilliseconds, 0, accuracy: 1e-6)
    }

    func testFirstTickHasZeroDriftRegardlessOfEmitTime() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel, configuration: .init(bpm: 60))
        // Emitting far from any hypothetical schedule: lastEmitted is nil → scheduled=emitted → drift=0.
        let t = osc.manualTick(at: Date(timeIntervalSince1970: 99_999_999))
        XCTAssertEqual(t.driftMilliseconds, 0, accuracy: 1e-6)
        XCTAssertEqual(t.scheduled, t.emitted)
    }
}
