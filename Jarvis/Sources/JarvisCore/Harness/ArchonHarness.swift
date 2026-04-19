import CryptoKit
import Foundation

public struct ArchonNode: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var command: String
    public var dependsOn: [String]
}

public struct ArchonWorkflow: Equatable, Sendable {
    public var name: String
    public var version: Int
    public var nodes: [ArchonNode]
}

public struct HarnessMutationResult: Sendable {
    public let workflowName: String
    public let mutationApplied: Bool
    public let diagnosis: String
    public let evaluationScore: Double
    public let workflowPath: String
    public let rollbackHash: String

    public var json: [String: Any] {
        [
            "workflowName": workflowName,
            "mutationApplied": mutationApplied,
            "diagnosis": diagnosis,
            "evaluationScore": evaluationScore,
            "workflowPath": workflowPath,
            "rollbackHash": rollbackHash
        ]
    }
}

private struct ExecutionTrace {
    let workflowID: String
    let stepID: String
    let inputContext: String
    let outputResult: String
    let status: String
}

public final class MetaHarness {
    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore

    public init(paths: WorkspacePaths, telemetry: TelemetryStore) {
        self.paths = paths
        self.telemetry = telemetry
    }

    public func diagnoseAndRewrite(workflowURL: URL, traceDirectory: URL) throws -> HarnessMutationResult {
        try ensureDefaultWorkflow(at: workflowURL)
        let original = try String(contentsOf: workflowURL, encoding: .utf8)
        var workflow = try ArchonYAMLCodec.decode(original)

        // CX-042: feedback loop guard — reject re-entrant mutation on already-mutated workflows
        let mutationCount = workflow.nodes.filter { $0.id == "validation" || $0.id == "counterfactual-diagnosis" }.count
        guard mutationCount < 3 else {
            throw JarvisError.processFailure("Archon feedback loop: workflow already contains \(mutationCount) injected nodes. Manual review required.")
        }

        let traces = try loadExecutionTraces(from: traceDirectory)

        let failureCounts = traces.reduce(into: [String: Int]()) { partial, trace in
            if trace.status.lowercased() != "success" {
                partial[trace.stepID, default: 0] += 1
            }
        }
        let diagnosis = diagnose(from: traces, failureCounts: failureCounts)

        var mutationApplied = false
        if !workflow.nodes.contains(where: { $0.kind == "validation" }) {
            let validation = ArchonNode(
                id: "validation",
                kind: "validation",
                command: "xcodebuild -project Jarvis.xcodeproj -scheme Jarvis build test",
                dependsOn: ["implementation"]
            )
            if let implementationIndex = workflow.nodes.firstIndex(where: { $0.id == "implementation" }) {
                workflow.nodes.insert(validation, at: implementationIndex + 1)
            } else {
                workflow.nodes.append(validation)
            }
            mutationApplied = true
        }

        if let reviewIndex = workflow.nodes.firstIndex(where: { $0.id == "review" }) {
            if !workflow.nodes[reviewIndex].dependsOn.contains("validation") {
                workflow.nodes[reviewIndex].dependsOn.append("validation")
                mutationApplied = true
            }
        }

        if let hotspot = failureCounts.max(by: { $0.value < $1.value })?.key,
           diagnosis.contains("missing dependency"),
           !workflow.nodes.contains(where: { $0.id == "counterfactual-diagnosis" }) {
            let diagnosisNode = ArchonNode(
                id: "counterfactual-diagnosis",
                kind: "diagnosis",
                command: "Inspect raw traces and repair \(hotspot) dependencies",
                dependsOn: [hotspot]
            )
            workflow.nodes.append(diagnosisNode)
            mutationApplied = true
        }

        let mutated = ArchonYAMLCodec.encode(workflow)
        let rollbackHash = sha256(of: original)
        if mutationApplied {
            try mutated.write(to: workflowURL, atomically: true, encoding: .utf8)
        }

        let evaluationScore = evaluate(traces: traces, mutationApplied: mutationApplied)
        try telemetry.logHarnessMutation(
            versionID: UUID().uuidString,
            workflowID: workflow.name,
            diffPatch: makePatch(before: original, after: mutated),
            evaluationScore: evaluationScore,
            rollbackHash: rollbackHash
        )

        return HarnessMutationResult(
            workflowName: workflow.name,
            mutationApplied: mutationApplied,
            diagnosis: diagnosis,
            evaluationScore: evaluationScore,
            workflowPath: workflowURL.path,
            rollbackHash: rollbackHash
        )
    }

    private func ensureDefaultWorkflow(at workflowURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: workflowURL.path) else { return }
        let workflow = ArchonWorkflow(
            name: "jarvis-default",
            version: 1,
            nodes: [
                ArchonNode(id: "planning", kind: "planning", command: "Analyze codebase and write architecture plan", dependsOn: []),
                ArchonNode(id: "implementation", kind: "implementation", command: "Generate code from the planning output", dependsOn: ["planning"]),
                ArchonNode(id: "review", kind: "review", command: "Review code against validation evidence", dependsOn: ["implementation"])
            ]
        )
        try ArchonYAMLCodec.encode(workflow).write(to: workflowURL, atomically: true, encoding: .utf8)
    }

    private func loadExecutionTraces(from traceDirectory: URL) throws -> [ExecutionTrace] {
        var traces: [ExecutionTrace] = []
        let candidateURLs: [URL]
        if FileManager.default.fileExists(atPath: traceDirectory.path) {
            candidateURLs = try FileManager.default.contentsOfDirectory(at: traceDirectory, includingPropertiesForKeys: nil)
        } else {
            candidateURLs = []
        }

        let telemetryTraceURL = telemetry.tableURL("execution_traces")
        let allURLs = candidateURLs + [telemetryTraceURL]
        for url in allURLs where FileManager.default.fileExists(atPath: url.path) {
            let content = try String(contentsOf: url, encoding: .utf8)
            for line in content.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                if let data = line.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    traces.append(ExecutionTrace(
                        workflowID: (object["workflowId"] as? String) ?? "jarvis-default",
                        stepID: (object["stepId"] as? String) ?? url.deletingPathExtension().lastPathComponent,
                        inputContext: (object["inputContext"] as? String) ?? "",
                        outputResult: (object["outputResult"] as? String) ?? "",
                        status: (object["status"] as? String) ?? "pending"
                    ))
                } else {
                    // CX-015: skip non-JSON lines instead of inferring status from substring
                    continue
                }
            }
        }
        return traces
    }

    private func diagnose(from traces: [ExecutionTrace], failureCounts: [String: Int]) -> String {
        let joined = traces.map(\.outputResult).joined(separator: "\n").lowercased()
        if joined.contains("dependency") || joined.contains("depends_on") {
            return "missing dependency detected during counterfactual diagnosis"
        }
        if joined.contains("schema") || joined.contains("decode") || joined.contains("json") {
            return "output schema mismatch detected during counterfactual diagnosis"
        }
        if joined.contains("compile") || joined.contains("xcodebuild") || joined.contains("swift") {
            return "validation failure detected in host build pipeline"
        }
        if failureCounts.isEmpty {
            return "no failure hotspot detected; workflow remains stable"
        }
        return "high failure density detected around \(failureCounts.max(by: { $0.value < $1.value })?.key ?? "unknown")"
    }

    private func evaluate(traces: [ExecutionTrace], mutationApplied: Bool) -> Double {
        let successCount = traces.filter { $0.status.lowercased() == "success" }.count
        let failureCount = traces.count - successCount
        return Double(successCount) - (Double(failureCount) * 1.25) + (mutationApplied ? 2.0 : 0.0)
    }

    private func makePatch(before: String, after: String) -> String {
        guard before != after else { return "No mutation required." }
        return """
        --- before
        \(before)
        --- after
        \(after)
        """
    }

    private func sha256(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum ArchonYAMLCodec {
    static func decode(_ text: String) throws -> ArchonWorkflow {
        var name = "jarvis-default"
        var version = 1
        var nodes: [ArchonNode] = []
        var current: ArchonNode?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("name:") {
                name = value(from: line)
            } else if line.hasPrefix("version:") {
                version = Int(value(from: line)) ?? 1
            } else if line.hasPrefix("- id:") {
                if let current {
                    nodes.append(current)
                }
                current = ArchonNode(id: value(from: line), kind: "task", command: "", dependsOn: [])
            } else if line.hasPrefix("kind:") {
                current?.kind = value(from: line)
            } else if line.hasPrefix("command:") {
                current?.command = try validateCommand(value(from: line))  // CX-025: validate shell metacharacters
            } else if line.hasPrefix("depends_on:") {
                current?.dependsOn = parseArray(value(from: line))
            }
        }

        if let current {
            nodes.append(current)
        }

        return ArchonWorkflow(name: name, version: version, nodes: nodes)
    }

    static func encode(_ workflow: ArchonWorkflow) -> String {
        var lines: [String] = [
            "name: \(workflow.name)",
            "version: \(workflow.version)",
            "nodes:"
        ]

        for node in workflow.nodes {
            lines.append("  - id: \(node.id)")
            lines.append("    kind: \(node.kind)")
            lines.append("    command: \(node.command)")
            let dependsOn = node.dependsOn.joined(separator: ", ")
            lines.append("    depends_on: [\(dependsOn)]")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func value(from line: String) -> String {
        line.split(separator: ":", maxSplits: 1).dropFirst().first?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func parseArray(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Validate that a decoded command doesn't contain injection vectors.
    /// Commands are shell-executed; reject lines with pipe, redirect, or
    /// command chaining that could escape the intended operation.
    private static func validateCommand(_ command: String) throws -> String {
        let forbidden = ["|", ";", "&&", "||", "`", "$(", ">"]
        for pattern in forbidden {
            if command.contains(pattern) {
                throw JarvisError.processFailure(
                    "command contains forbidden shell metacharacter '\(pattern)': \(command)")
            }
        }
        return command
    }
}
