import Foundation

public final class TelemetryStore: @unchecked Sendable {
    private let paths: WorkspacePaths
    private let encoder = ISO8601DateFormatter()
    private let lock = NSLock()
    private let maxFileSizeBytes: Int = 10_485_760  // CX-035: 10MB rotation threshold

    public init(paths: WorkspacePaths) throws {
        self.paths = paths
        try paths.ensureSupportDirectories()
    }

    public func tableURL(_ name: String) -> URL {
        paths.telemetryDirectory.appendingPathComponent("\(name).jsonl")
    }

    public func append(record: [String: Any], to table: String) throws {
        let url = tableURL(table)
        var payload = record
        if payload["timestamp"] == nil {
            payload["timestamp"] = encoder.string(from: Date())
        }
        // CX-036: serialize outside lock to reduce contention
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        lock.lock()
        defer { lock.unlock() }

        // CX-035: rotate if file exceeds threshold
        // R04: keep at most maxRotations backup files, delete oldest
        let maxRotations = 2
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path),
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > maxFileSizeBytes {
            // Shift existing rotation files: .N → .N+1, delete the oldest
            for i in stride(from: maxRotations, through: 1, by: -1) {
                let rotatedN = url.deletingPathExtension().appendingPathExtension("jsonl.\(i)")
                try? fm.removeItem(at: rotatedN)
                if i > 1 {
                    let rotatedPrev = url.deletingPathExtension().appendingPathExtension("jsonl.\(i - 1)")
                    try? fm.moveItem(at: rotatedPrev, to: rotatedN)
                }
            }
            let rotated1 = url.deletingPathExtension().appendingPathExtension("jsonl.1")
            try? fm.removeItem(at: rotated1)
            try? fm.moveItem(at: url, to: rotated1)
        }

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw JarvisError.processFailure("Unable to open telemetry file \(url.path): \(error.localizedDescription)")
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let newline = "\n".data(using: .utf8) {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: newline)
        }
    }

    public func logExecutionTrace(workflowID: String, stepID: String, inputContext: String, outputResult: String, status: String) throws {
        try append(record: [
            "workflowId": workflowID,
            "stepId": stepID,
            "inputContext": inputContext,
            "outputResult": outputResult,
            "status": status
        ], to: "execution_traces")
    }

    public func logStigmergicSignal(edge: EdgeKey, signal: TernarySignal, agentID: String, pheromone: Double) throws {
        try append(record: [
            "nodeSource": edge.source,
            "nodeTarget": edge.target,
            "ternaryValue": signal.rawValue,
            "agentId": agentID,
            "pheromone": pheromone
        ], to: "stigmergic_signals")
    }

    public func logRecursiveThought(sessionID: String, trace: [String], memoryPageFault: Bool) throws {
        try append(record: [
            "sessionId": sessionID,
            "thoughtTrace": trace,
            "memoryPageFault": memoryPageFault
        ], to: "recursive_thoughts")
    }

    public func logVagalTone(sourceNode: String, value: Double, state: String) throws {
        try append(record: [
            "sourceNode": sourceNode,
            "value": value,
            "state": state
        ], to: "vagal_tone")
    }

    public func logNodeHeartbeat(nodeName: String, address: String?, rustDeskID: String?, tunnelState: String, guiReachable: Bool) throws {
        try append(record: [
            "nodeName": nodeName,
            "address": address ?? "",
            "rustDeskID": rustDeskID ?? "",
            "tunnelState": tunnelState,
            "guiReachable": guiReachable
        ], to: "node_registry")
    }

    public func logHarnessMutation(versionID: String, workflowID: String, diffPatch: String, evaluationScore: Double, rollbackHash: String) throws {
        try append(record: [
            "versionId": versionID,
            "workflowId": workflowID,
            "diffPatch": diffPatch,
            "evaluationScore": evaluationScore,
            "rollbackHash": rollbackHash
        ], to: "harness_mutations")
    }

    public func syncVoiceGateState(hostNode: String,
                                   state: String,
                                   composite: String?,
                                   expectedComposite: String?,
                                   referenceAudioDigest: String?,
                                   referenceTranscriptDigest: String?,
                                   modelRepository: String?,
                                   personaFramingVersion: String?,
                                   operatorLabel: String?,
                                   approvedAtISO8601: String?,
                                   notes: String?) throws {
        var payload: [String: Any] = [
            "hostNode": hostNode,
            "state": state,
            "lastSync": encoder.string(from: Date())
        ]
        if let composite { payload["composite"] = composite }
        if let expectedComposite { payload["expectedComposite"] = expectedComposite }
        if let referenceAudioDigest { payload["referenceAudioDigest"] = referenceAudioDigest }
        if let referenceTranscriptDigest { payload["referenceTranscriptDigest"] = referenceTranscriptDigest }
        if let modelRepository { payload["modelRepository"] = modelRepository }
        if let personaFramingVersion { payload["personaFramingVersion"] = personaFramingVersion }
        if let operatorLabel { payload["operatorLabel"] = operatorLabel }
        if let approvedAtISO8601 { payload["approvedAtISO8601"] = approvedAtISO8601 }
        if let notes { payload["notes"] = notes }
        try append(record: payload, to: "voice_gate_state")
    }

    public func logVoiceGateEvent(hostNode: String,
                                  eventType: String,
                                  composite: String?,
                                  expectedComposite: String?,
                                  operatorLabel: String?,
                                  notes: String?) throws {
        var payload: [String: Any] = [
            "hostNode": hostNode,
            "eventType": eventType
        ]
        if let composite { payload["composite"] = composite }
        if let expectedComposite { payload["expectedComposite"] = expectedComposite }
        if let operatorLabel { payload["operatorLabel"] = operatorLabel }
        if let notes { payload["notes"] = notes }
        try append(record: payload, to: "voice_gate_events")
    }
}
