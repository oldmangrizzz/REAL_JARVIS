import CryptoKit
import Foundation
import XCTest

@testable import JarvisCore

// MARK: - Stub Proposer

/// Thread-safe test double for GridProposer.
final class MockGridProposer: GridProposer, @unchecked Sendable {
    var gridToReturn: [[Int]]?
    var errorToThrow: Error?

    func propose(gridState: [[Int]], timestep: Int) throws -> [[Int]] {
        if let err = errorToThrow { throw err }
        return gridToReturn ?? gridState
    }
}

// MARK: - Helpers

private func makeOrchestrator(proposer: any GridProposer, paths: WorkspacePaths) throws -> ARCSubmissionOrchestrator {
    let telemetry = try TelemetryStore(paths: paths)
    let physics = StubPhysicsEngine()
    return ARCSubmissionOrchestrator(telemetry: telemetry, physics: physics, proposer: proposer)
}

private func sampleTaskURL(in dir: URL) throws -> URL {
    let taskJSON = """
    {"train":[{"input":[[1,0,0],[0,1,0],[0,0,1]],"output":[[1,0,0],[0,1,0],[0,0,1]]}],\
    "test":[{"input":[[1,0,0],[0,1,0],[0,0,1]]}]}
    """
    let url = dir.appendingPathComponent("SAMPLE-0001.json")
    try taskJSON.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// MARK: - Tests

final class ARCSubmissionTests: XCTestCase {

    // ── Test 1: Happy path ───────────────────────────────────────────────────
    // Stub proposer returns the input grid unchanged; artifact must match.

    func testHappyPath_candidateGridMatchesInput() async throws {
        let paths = try makeTestWorkspace()
        let taskDir = paths.storageRoot.appendingPathComponent("arc-tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        let taskURL = try sampleTaskURL(in: taskDir)

        let proposer = MockGridProposer()  // returns identity by default
        let orchestrator = try makeOrchestrator(proposer: proposer, paths: paths)
        let artifact = try await orchestrator.run(taskFileURL: taskURL)

        let expected: [[Int]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        XCTAssertEqual(artifact.candidateGrid, expected)
        XCTAssertFalse(artifact.witnessSha256.isEmpty)
        XCTAssertEqual(artifact.taskId, "SAMPLE-0001")
        XCTAssertGreaterThan(artifact.ttl, Date().timeIntervalSince1970)
        XCTAssertGreaterThanOrEqual(artifact.latencyMs, 0)
    }

    // ── Test 2: Invalid JSON → throws ARCSubmissionError.invalidJSON ─────────

    func testInvalidJSON_throwsInvalidJSON() async throws {
        let paths = try makeTestWorkspace()
        let taskDir = paths.storageRoot.appendingPathComponent("arc-tasks2", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)

        let badURL = taskDir.appendingPathComponent("bad.json")
        try "{ this is not valid json }".write(to: badURL, atomically: true, encoding: .utf8)

        let proposer = MockGridProposer()
        let orchestrator = try makeOrchestrator(proposer: proposer, paths: paths)

        do {
            _ = try await orchestrator.run(taskFileURL: badURL)
            XCTFail("Expected ARCSubmissionError.invalidJSON to be thrown.")
        } catch ARCSubmissionError.invalidJSON {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // ── Test 3: RLM timeout → throws ARCSubmissionError.rlmTimeout ──────────

    func testRLMTimeout_throwsRlmTimeout() async throws {
        let paths = try makeTestWorkspace()
        let taskDir = paths.storageRoot.appendingPathComponent("arc-tasks3", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        let taskURL = try sampleTaskURL(in: taskDir)

        let proposer = MockGridProposer()
        proposer.errorToThrow = JarvisError.processFailure("Python bridge timed out after 30s.")

        let orchestrator = try makeOrchestrator(proposer: proposer, paths: paths)

        do {
            _ = try await orchestrator.run(taskFileURL: taskURL)
            XCTFail("Expected ARCSubmissionError.rlmTimeout to be thrown.")
        } catch ARCSubmissionError.rlmTimeout {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // ── Test 4: Shape mismatch (RLM returns 2×2 for 3×3 task) → throws ──────

    func testShapeMismatch_throwsShapeMismatch() async throws {
        let paths = try makeTestWorkspace()
        let taskDir = paths.storageRoot.appendingPathComponent("arc-tasks4", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        let taskURL = try sampleTaskURL(in: taskDir)

        let proposer = MockGridProposer()
        proposer.gridToReturn = [[1, 0], [0, 1]]  // 2×2, not 3×3

        let orchestrator = try makeOrchestrator(proposer: proposer, paths: paths)

        do {
            _ = try await orchestrator.run(taskFileURL: taskURL)
            XCTFail("Expected ARCSubmissionError.shapeMismatch to be thrown.")
        } catch ARCSubmissionError.shapeMismatch(let expected, let actual) {
            XCTAssertEqual(expected, "3x3")
            XCTAssertEqual(actual, "2x2")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // ── Test 5: Witness tamper — mutating the grid changes witnessSha256 ─────

    func testWitnessSha256_reflectsCandidateBytes() async throws {
        let paths = try makeTestWorkspace()
        let taskDir = paths.storageRoot.appendingPathComponent("arc-tasks5", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        let taskURL = try sampleTaskURL(in: taskDir)

        let proposerA = MockGridProposer()
        proposerA.gridToReturn = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        let orchestratorA = try makeOrchestrator(proposer: proposerA, paths: paths)
        let artifactA = try await orchestratorA.run(taskFileURL: taskURL)

        let proposerB = MockGridProposer()
        proposerB.gridToReturn = [[2, 0, 0], [0, 2, 0], [0, 0, 2]]  // different grid
        let orchestratorB = try makeOrchestrator(proposer: proposerB, paths: paths)
        let artifactB = try await orchestratorB.run(taskFileURL: taskURL)

        XCTAssertNotEqual(artifactA.witnessSha256, artifactB.witnessSha256,
                          "Different candidate grids must produce different witness hashes.")
        XCTAssertFalse(artifactA.witnessSha256.isEmpty)
        XCTAssertEqual(artifactA.witnessSha256.count, 64)  // SHA-256 hex = 64 chars
    }
}
