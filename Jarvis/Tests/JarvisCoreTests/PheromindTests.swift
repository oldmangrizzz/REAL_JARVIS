import XCTest
@testable import JarvisCore

final class PheromindTests: XCTestCase {
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
}
