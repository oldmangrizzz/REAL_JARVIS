import XCTest
@testable import JarvisCore

final class PheromindTests: XCTestCase {
    private func makeEngine(base: Double = 0.12) throws -> (PheromindEngine, TelemetryStore) {
        let ws = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: ws)
        let engine = PheromindEngine(baseEvaporation: base, learningRate: 0.35, telemetry: tel)
        return (engine, tel)
    }

    func testGlobalUpdateEquationAndTernaryController() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let edge = EdgeKey(source: "planning", target: "implementation")

        runtime.pheromind.baseEvaporation = 0.10
        runtime.pheromind.register(edge: edge, pheromone: 0.6, somaticWeight: 0.2)
        let deposits = [
            PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 1.0, agentID: "a", timestamp: Date())
        ]

        let states = try runtime.pheromind.applyGlobalUpdate(deposits: deposits)
        let state = try XCTUnwrap(states[edge])

        XCTAssertEqual(TernarySignal.regulate(score: 0.8), .reinforce)
        XCTAssertEqual(round(state.pheromone * 100) / 100, 1.54)
        XCTAssertGreaterThan(state.somaticWeight, 0.2)
        XCTAssertEqual(runtime.pheromind.chooseNextEdge(from: "planning"), edge)
    }

    // MARK: - TernarySignal.regulate thresholds

    func testTernaryRegulateDefaultThresholds() {
        XCTAssertEqual(TernarySignal.regulate(score:  0.21), .reinforce)
        XCTAssertEqual(TernarySignal.regulate(score:  0.20), .reinforce) // boundary inclusive
        XCTAssertEqual(TernarySignal.regulate(score:  0.0),  .neutral)
        XCTAssertEqual(TernarySignal.regulate(score: -0.19), .neutral)
        XCTAssertEqual(TernarySignal.regulate(score: -0.20), .repel)    // boundary inclusive
        XCTAssertEqual(TernarySignal.regulate(score: -1.0),  .repel)
    }

    func testTernaryRegulateCustomThresholds() {
        XCTAssertEqual(TernarySignal.regulate(score: 0.4, positiveThreshold: 0.5, negativeThreshold: -0.5), .neutral)
        XCTAssertEqual(TernarySignal.regulate(score: 0.5, positiveThreshold: 0.5, negativeThreshold: -0.5), .reinforce)
    }

    // MARK: - register / state

    func testRegisterIsIdempotent() throws {
        let (engine, _) = try makeEngine()
        let e = EdgeKey(source: "a", target: "b")
        engine.register(edge: e, pheromone: 0.7, somaticWeight: 0.3)
        // Second register with different seed must NOT overwrite.
        engine.register(edge: e, pheromone: 9.9, somaticWeight: 9.9)
        let s = try XCTUnwrap(engine.state(for: e))
        XCTAssertEqual(s.pheromone, 0.7)
        XCTAssertEqual(s.somaticWeight, 0.3)
    }

    func testStateReturnsNilForUnknownEdge() throws {
        let (engine, _) = try makeEngine()
        XCTAssertNil(engine.state(for: EdgeKey(source: "x", target: "y")))
    }

    // MARK: - effectiveEvaporation

    func testEvaporationFloor() throws {
        let (engine, _) = try makeEngine(base: 0.001)
        let fresh = PheromoneEdgeState(pheromone: 0, somaticWeight: 0, lastUpdated: Date(), successCount: 10, failureCount: 0)
        // Floor clamps evaporation to >= 0.05 even with tiny base + all successes.
        XCTAssertGreaterThanOrEqual(engine.effectiveEvaporation(for: fresh, now: Date()), 0.05)
    }

    func testEvaporationCeiling() throws {
        let (engine, _) = try makeEngine(base: 0.90)
        // High failureBias (0.2) + staleness cap (0.25) + base 0.90 would exceed 1;
        // ceiling clamps to 0.95.
        let stale = PheromoneEdgeState(
            pheromone: 1.0, somaticWeight: 0,
            lastUpdated: Date().addingTimeInterval(-7200),  // 2 hours ago → staleness cap
            successCount: 0, failureCount: 100
        )
        XCTAssertEqual(engine.effectiveEvaporation(for: stale, now: Date()), 0.95, accuracy: 1e-9)
    }

    func testEvaporationFailureBias() throws {
        let (engine, _) = try makeEngine(base: 0.10)
        let now = Date()
        let allSuccess = PheromoneEdgeState(pheromone: 0, somaticWeight: 0, lastUpdated: now, successCount: 10, failureCount: 0)
        let allFail    = PheromoneEdgeState(pheromone: 0, somaticWeight: 0, lastUpdated: now, successCount: 0, failureCount: 10)
        XCTAssertLessThan(engine.effectiveEvaporation(for: allSuccess, now: now),
                          engine.effectiveEvaporation(for: allFail, now: now),
                          "all-failure edges must evaporate faster than all-success edges")
    }

    // MARK: - applyGlobalUpdate

    func testRepelDecreasesPheromoneAndIncrementsFailure() throws {
        let (engine, _) = try makeEngine(base: 0.10)
        let edge = EdgeKey(source: "s", target: "t")
        engine.register(edge: edge, pheromone: 1.0, somaticWeight: 0.5)
        let now = Date()
        let deposits = [PheromoneDeposit(edge: edge, signal: .repel, magnitude: 0.4, agentID: "a", timestamp: now)]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        let s = try XCTUnwrap(states[edge])
        // (1 - 0.10)*1.0 + (-1)*0.4 = 0.5
        XCTAssertEqual(s.pheromone, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.failureCount, 1)
        XCTAssertEqual(s.successCount, 0)
        XCTAssertLessThan(s.somaticWeight, 0.5)
    }

    func testNeutralDoesNotIncrementCounters() throws {
        let (engine, _) = try makeEngine()
        let edge = EdgeKey(source: "a", target: "b")
        engine.register(edge: edge, pheromone: 0.5)
        let now = Date()
        let deposits = [PheromoneDeposit(edge: edge, signal: .neutral, magnitude: 1.0, agentID: "a", timestamp: now)]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        let s = try XCTUnwrap(states[edge])
        XCTAssertEqual(s.successCount, 0)
        XCTAssertEqual(s.failureCount, 0)
    }

    func testPassiveDecayAppliesToNonDepositedEdges() throws {
        let (engine, _) = try makeEngine(base: 0.20)
        let touched = EdgeKey(source: "a", target: "b")
        let untouched = EdgeKey(source: "a", target: "c")
        engine.register(edge: touched, pheromone: 1.0)
        engine.register(edge: untouched, pheromone: 1.0)
        let now = Date()
        let deposits = [PheromoneDeposit(edge: touched, signal: .reinforce, magnitude: 0.5, agentID: "x", timestamp: now)]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        let u = try XCTUnwrap(states[untouched])
        // No deposit: just (1 - 0.20) * 1.0 = 0.80
        XCTAssertEqual(u.pheromone, 0.80, accuracy: 1e-9)
    }

    func testAutoRegistersUnknownEdgeFromDeposit() throws {
        let (engine, _) = try makeEngine(base: 0.10)
        let edge = EdgeKey(source: "new-src", target: "new-tgt")
        XCTAssertNil(engine.state(for: edge))
        let now = Date()
        _ = try engine.applyGlobalUpdate(
            deposits: [PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 1.0, agentID: "a", timestamp: now)],
            now: now
        )
        XCTAssertNotNil(engine.state(for: edge))
    }

    func testMultipleDepositsSameEdgeAggregateIntoSingleUpdate() throws {
        let (engine, _) = try makeEngine(base: 0.10)
        let edge = EdgeKey(source: "a", target: "b")
        engine.register(edge: edge, pheromone: 0.0)
        let now = Date()
        let deposits = [
            PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 0.3, agentID: "a", timestamp: now),
            PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 0.2, agentID: "b", timestamp: now),
            PheromoneDeposit(edge: edge, signal: .repel,     magnitude: 0.1, agentID: "c", timestamp: now)
        ]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        let s = try XCTUnwrap(states[edge])
        // (1 - 0.10)*0 + (0.3 + 0.2 - 0.1) = 0.4
        XCTAssertEqual(s.pheromone, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.successCount, 2)
        XCTAssertEqual(s.failureCount, 1)
    }

    func testPheromoneClampedAtCeiling() throws {
        let (engine, _) = try makeEngine(base: 0.0)
        let edge = EdgeKey(source: "a", target: "b")
        engine.register(edge: edge, pheromone: 999.0)
        let now = Date()
        let deposits = [PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 500.0, agentID: "x", timestamp: now)]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        XCTAssertEqual(states[edge]?.pheromone, 1000.0, "CX-033 infinity clamp")
    }

    func testSomaticWeightClampedAtZeroFromBelow() throws {
        let (engine, _) = try makeEngine(base: 0.0)
        let edge = EdgeKey(source: "a", target: "b")
        engine.register(edge: edge, pheromone: 0.0, somaticWeight: 0.05)
        let now = Date()
        let deposits = [PheromoneDeposit(edge: edge, signal: .repel, magnitude: 10.0, agentID: "x", timestamp: now)]
        let states = try engine.applyGlobalUpdate(deposits: deposits, now: now)
        let s = try XCTUnwrap(states[edge])
        XCTAssertGreaterThanOrEqual(s.somaticWeight, 0.0)
    }

    // MARK: - chooseNextEdge

    func testChooseNextEdgePicksHighestCombinedScore() throws {
        let (engine, _) = try makeEngine()
        let better = EdgeKey(source: "s", target: "good")
        let worse  = EdgeKey(source: "s", target: "bad")
        let other  = EdgeKey(source: "other", target: "z")
        engine.register(edge: better, pheromone: 0.6, somaticWeight: 0.3)   // sum 0.9
        engine.register(edge: worse,  pheromone: 0.7, somaticWeight: 0.1)   // sum 0.8
        engine.register(edge: other,  pheromone: 5.0, somaticWeight: 5.0)   // different source
        XCTAssertEqual(engine.chooseNextEdge(from: "s"), better)
    }

    func testChooseNextEdgeReturnsNilWhenNoOutgoingEdges() throws {
        let (engine, _) = try makeEngine()
        engine.register(edge: EdgeKey(source: "a", target: "b"))
        XCTAssertNil(engine.chooseNextEdge(from: "nowhere"))
    }
}

