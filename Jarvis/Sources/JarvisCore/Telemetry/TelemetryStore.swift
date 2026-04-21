import Foundation
import CryptoKit

public final class TelemetryStore: @unchecked Sendable {
    private let paths: WorkspacePaths
    private let encoder = ISO8601DateFormatter()
    private let lock = NSLock()
    private let maxFileSizeBytes: Int = 10_485_760  // CX-035: 10MB rotation threshold

    /// SPEC-009 evidence-corpus hash chain. For each telemetry table we
    /// remember the rowHash of the most recently appended row. The next
    /// row's `prevRowHash` references it, so tampering with any middle
    /// row invalidates every row after it. Sentinel `chainGenesis` marks
    /// the start of a chain (new table OR first row after a migration
    /// from pre-chain legacy rows that had no rowHash field).
    private static let chainGenesis = "GENESIS"
    private var lastRowHashes: [String: String] = [:]
    private var chainPrimed: Set<String> = []

    public init(paths: WorkspacePaths) throws {
        self.paths = paths
        try paths.ensureSupportDirectories()
    }

    public func tableURL(_ name: String) -> URL {
        paths.telemetryDirectory.appendingPathComponent("\(name).jsonl")
    }

    public func append(record: [String: Any], to table: String, principal: Principal? = nil) throws {
        let url = tableURL(table)
        var payload = record
        if payload["timestamp"] == nil {
            payload["timestamp"] = encoder.string(from: Date())
        }
        // SPEC-009 evidence corpus: every row is witnessed by the bound
        // principal's tier token so the chain of custody can answer
        // "who was Jarvis serving when this was emitted." Explicit param
        // wins over any caller-supplied "principal" key to avoid client
        // self-assertion. Nil principal leaves the field absent for
        // legacy / pre-principal rows.
        if let principal {
            payload["principal"] = principal.tierToken
        }
        // Strip any caller-supplied hash fields — rowHash/prevRowHash
        // are computed by the store, never self-asserted.
        payload.removeValue(forKey: "prevRowHash")
        payload.removeValue(forKey: "rowHash")

        lock.lock()
        defer { lock.unlock() }

        // Prime chain state from the tail of the existing file on first touch.
        if !chainPrimed.contains(table) {
            lastRowHashes[table] = Self.tailRowHashUnlocked(url: url) ?? Self.chainGenesis
            chainPrimed.insert(table)
        }
        let prev = lastRowHashes[table] ?? Self.chainGenesis
        payload["prevRowHash"] = prev

        // Canonical JSON of the ROW-BODY (everything except rowHash itself)
        // is what gets hashed. Including prevRowHash in the hashed body is
        // what forms the chain.
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let rowHash = Self.sha256Hex(bodyData)
        payload["rowHash"] = rowHash

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        // CX-035: rotate if file exceeds threshold
        // R04: keep at most maxRotations backup files, delete oldest
        let maxRotations = 2
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path),
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > maxFileSizeBytes {
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
            // After rotation, restart chain (the previous chain is now in
            // the rotated archive; new live file is a fresh segment).
            lastRowHashes[table] = Self.chainGenesis
            // Recompute with correct prev so the FIRST row of the new
            // segment links back to genesis cleanly.
            payload["prevRowHash"] = Self.chainGenesis
            let reBody = try JSONSerialization.data(withJSONObject: payload.filter { $0.key != "rowHash" }, options: [.sortedKeys])
            let reHash = Self.sha256Hex(reBody)
            payload["rowHash"] = reHash
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
        let finalData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        if let newline = "\n".data(using: .utf8) {
            try handle.write(contentsOf: finalData)
            try handle.write(contentsOf: newline)
        }
        // Advance chain state for this table.
        lastRowHashes[table] = payload["rowHash"] as? String ?? Self.chainGenesis
        _ = data  // retained to minimise diff noise; actual write uses finalData
    }

    public func logExecutionTrace(workflowID: String, stepID: String, inputContext: String, outputResult: String, status: String, principal: Principal? = nil) throws {
        try append(record: [
            "workflowId": workflowID,
            "stepId": stepID,
            "inputContext": inputContext,
            "outputResult": outputResult,
            "status": status
        ], to: "execution_traces", principal: principal)
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
                                   principal: Principal? = nil) throws {
        try append(record: [
            "hostNode": hostNode,
            "state": state,
            "composite": composite ?? "",
            "expectedComposite": expectedComposite ?? ""
        ], to: "voice_gate_state", principal: principal)
    }

    // MARK: - Ambient Audio Gateway Logging

    /// Logs a state transition event for the ambient audio gateway.
    ///
    /// - Parameters:
    ///   - hostNode: Identifier of the host node where the transition occurred.
    ///   - transition: Human‑readable description of the transition (e.g. `"idle→listening"`).
    ///   - principal: Optional principal whose tier token should be attached to the record.
    public func logAmbientGatewayTransition(hostNode: String,
                                            transition: String,
                                            principal: Principal? = nil) throws {
        try append(record: [
            "hostNode": hostNode,
            "transition": transition
        ], to: "ambient_audio_gateway", principal: principal)
    }

    /// Logs a latency SLA miss event for the ambient audio gateway.
    ///
    /// - Parameters:
    ///   - hostNode: Identifier of the host node where the latency miss was observed.
    ///   - observedLatencyMs: The measured latency in milliseconds.
    ///   - slaMs: The SLA threshold in milliseconds that was missed.
    ///   - principal: Optional principal whose tier token should be attached to the record.
    public func logAmbientGatewayLatencySLAMiss(hostNode: String,
                                                observedLatencyMs: Double,
                                                slaMs: Double,
                                                principal: Principal? = nil) throws {
        try append(record: [
            "hostNode": hostNode,
            "observedLatencyMs": observedLatencyMs,
            "slaMs": slaMs
        ], to: "ambient_audio_gateway", principal: principal)
    }

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func tailRowHashUnlocked(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Seek to near the end and read backwards to find the last newline.
        // This is a simple heuristic; for production use a more robust
        // reverse‑line‑reader.
        let chunkSize = 4096
        var offset = max(0, (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0 - UInt64(chunkSize))
        while offset > 0 {
            try? handle.seek(toOffset: offset)
            let data = try? handle.read(upToCount: chunkSize)
            if let data = data, let str = String(data: data, encoding: .utf8), let range = str.range(of: "\n", options: .backwards) {
                let lineStart = str.index(range.upperBound, offsetBy: 0)
                let line = String(str[lineStart...])
                if let json = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: []) as? [String: Any],
                   let hash = json["rowHash"] as? String {
                    return hash
                }
            }
            offset = offset > UInt64(chunkSize) ? offset - UInt64(chunkSize) : 0
        }
        return nil
    }
}