import CryptoKit
import Foundation

// MARK: - Errors

public enum ARCSubmissionError: Error, CustomStringConvertible, Sendable {
    case invalidJSON(String)
    case shapeMismatch(expected: String, actual: String)
    case rlmTimeout
    case emptyTask

    public var description: String {
        switch self {
        case let .invalidJSON(msg):          return "arc.submit: invalid_json — \(msg)"
        case let .shapeMismatch(exp, act):   return "arc.submit: shape_mismatch — expected \(exp), got \(act)"
        case .rlmTimeout:                    return "arc.submit: rlm_timeout"
        case .emptyTask:                     return "arc.submit: empty_task — no test cases in task file"
        }
    }
}

// MARK: - Artifact

public struct ARCSubmissionArtifact: Codable, Sendable {
    public let taskId: String
    public let candidateGrid: [[Int]]
    public let latencyMs: Int
    public let ttl: TimeInterval
    public let witnessSha256: String

    public init(taskId: String, candidateGrid: [[Int]], latencyMs: Int, ttl: TimeInterval, witnessSha256: String) {
        self.taskId = taskId
        self.candidateGrid = candidateGrid
        self.latencyMs = latencyMs
        self.ttl = ttl
        self.witnessSha256 = witnessSha256
    }
}

// MARK: - GridProposer Protocol

/// Abstraction for the RLM inference step. Lets tests inject a stub without
/// spawning a Python subprocess.
public protocol GridProposer: AnyObject, Sendable {
    /// Given a grid state (as raw [[Int]]) and a timestep budget, return the proposed output grid.
    func propose(gridState: [[Int]], timestep: Int) throws -> [[Int]]
}

// MARK: - Orchestrator

public final class ARCSubmissionOrchestrator: @unchecked Sendable {
    private let telemetry: TelemetryStore
    private let physics: PhysicsEngine
    private let proposer: any GridProposer

    public init(telemetry: TelemetryStore, physics: PhysicsEngine, proposer: any GridProposer) {
        self.telemetry = telemetry
        self.physics = physics
        self.proposer = proposer
    }

    /// Load a task file, run physics + RLM, validate shape, and return a submission artifact.
    public func run(taskFileURL: URL) async throws -> ARCSubmissionArtifact {
        let start = Date()
        let taskId = taskFileURL.deletingPathExtension().lastPathComponent

        logEvent("arc.submit.start", taskId: taskId)

        // — Load task JSON ——————————————————————————————————————————————
        let data: Data
        do {
            data = try Data(contentsOf: taskFileURL)
        } catch {
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "invalid_json"])
            throw ARCSubmissionError.invalidJSON("Cannot read file: \(error.localizedDescription)")
        }

        let taskFile: ARCTaskFile
        do {
            taskFile = try JSONDecoder().decode(ARCTaskFile.self, from: data)
        } catch {
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "invalid_json"])
            throw ARCSubmissionError.invalidJSON("JSON parse error: \(error.localizedDescription)")
        }

        guard let firstTest = taskFile.test.first else {
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "empty_task"])
            throw ARCSubmissionError.emptyTask
        }

        let inputGrid = firstTest.input

        // Derive expected output shape from training pair output (if available).
        let expectedRows = taskFile.train.first?.output.count ?? inputGrid.count
        let expectedCols = taskFile.train.first?.output.first?.count ?? (inputGrid.first?.count ?? 0)

        // — Physics world load ——————————————————————————————————————————
        let arcGrid = ARCGrid(cells: inputGrid)
        let physicsBridge = ARCPhysicsBridge(engine: physics)
        let mapping = try physicsBridge.loadGrid(arcGrid)
        logEvent("arc.submit.physics_loaded", taskId: taskId, extra: ["bodies": "\(mapping.count)"])

        // — RLM propose —————————————————————————————————————————————————
        let candidate: [[Int]]
        do {
            candidate = try proposer.propose(gridState: inputGrid, timestep: 0)
        } catch let e as JarvisError {
            if case .processFailure(let msg) = e, msg.lowercased().contains("timed out") {
                logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "rlm_timeout"])
                throw ARCSubmissionError.rlmTimeout
            }
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "rlm_error"])
            throw e
        } catch let e as ARCSubmissionError {
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": e.description])
            throw e
        }
        logEvent("arc.submit.rlm_response", taskId: taskId, extra: ["rows": "\(candidate.count)"])

        // — Shape validation ————————————————————————————————————————————
        let actualRows = candidate.count
        let actualCols = candidate.first?.count ?? 0
        guard actualRows == expectedRows, actualCols == expectedCols else {
            let exp = "\(expectedRows)x\(expectedCols)"
            let act = "\(actualRows)x\(actualCols)"
            logEvent("arc.submit.failed", taskId: taskId, extra: ["reason": "shape_mismatch"])
            throw ARCSubmissionError.shapeMismatch(expected: exp, actual: act)
        }
        logEvent("arc.submit.validated", taskId: taskId)

        // — Witness SHA-256 —————————————————————————————————————————————
        let gridJSON = try JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])
        let sha = SHA256.hash(data: gridJSON)
        let witnessHex = sha.compactMap { String(format: "%02x", $0) }.joined()

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let ttl = Date().timeIntervalSince1970 + 300  // 5 min from now

        let artifact = ARCSubmissionArtifact(
            taskId: taskId,
            candidateGrid: candidate,
            latencyMs: latencyMs,
            ttl: ttl,
            witnessSha256: witnessHex
        )
        logEvent("arc.submit.done", taskId: taskId, extra: ["latencyMs": "\(latencyMs)", "witnessSha256": witnessHex])
        return artifact
    }

    // MARK: - Telemetry

    private func logEvent(_ event: String, taskId: String, extra: [String: Any] = [:]) {
        var record: [String: Any] = ["event": event, "taskId": taskId]
        for (k, v) in extra { record[k] = v }
        try? telemetry.append(record: record, to: "arc_submission_events")
    }
}

// MARK: - Internal ARC-AGI File Format

/// Mirrors the public ARC-AGI JSON schema where grids are raw [[Int]] arrays,
/// not wrapped in a {"cells": ...} envelope like ARCGrid uses internally.
private struct ARCTaskFile: Codable {
    let train: [TrainPair]
    let test: [TestCase]

    struct TrainPair: Codable {
        let input: [[Int]]
        let output: [[Int]]
    }

    struct TestCase: Codable {
        let input: [[Int]]
    }
}
