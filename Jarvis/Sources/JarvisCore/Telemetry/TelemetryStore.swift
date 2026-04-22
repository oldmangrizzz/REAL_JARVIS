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

    // MARK: - AMBIENT-002 ambient audio gateway telemetry
    //
    // Every route transition and SLA breach is witnessed by the bound
    // principal's tier token via the SPEC-009 hash chain. Chain verification
    // runs against table name `ambient_audio_gateway`.

    public func logAmbientGatewayTransition(hostNode: String,
                                            fromRoute: AmbientGatewayRoute,
                                            toRoute: AmbientGatewayRoute,
                                            endpointID: String?,
                                            tunnelReachable: Bool,
                                            wristAttached: Bool,
                                            principal: Principal,
                                            at timestamp: Date = Date()) throws {
        var payload: [String: Any] = [
            "hostNode": hostNode,
            "eventType": "transition",
            "fromRoute": fromRoute.rawValue,
            "toRoute": toRoute.rawValue,
            "tunnelReachable": tunnelReachable,
            "wristAttached": wristAttached,
            "timestamp": encoder.string(from: timestamp)
        ]
        if let endpointID { payload["endpointID"] = endpointID }
        try append(record: payload, to: "ambient_audio_gateway", principal: principal)
    }

    public func logAmbientGatewayLatencySLAMiss(hostNode: String,
                                                hopName: String,
                                                measuredMs: Double,
                                                ceilingMs: Double,
                                                principal: Principal,
                                                at timestamp: Date = Date()) throws {
        let payload: [String: Any] = [
            "hostNode": hostNode,
            "eventType": "latencySLAMiss",
            "hopName": hopName,
            "measuredMs": measuredMs,
            "ceilingMs": ceilingMs,
            "timestamp": encoder.string(from: timestamp)
        ]
        try append(record: payload, to: "ambient_audio_gateway", principal: principal)
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

    // MARK: - Chain verification

    /// SPEC-009 tier-witness chain verifier. Replays the file line-by-line,
    /// rebuilding each row's expected rowHash from the serialized body +
    /// prevRowHash. Any drift — a flipped bit, a silently edited principal
    /// tag, a reordered row — fails verification with the offending line
    /// number. Legacy rows with no rowHash field are treated as a chain
    /// break and verification resumes from the next row that DOES carry
    /// a hash (so a table migrated mid-life still validates its new
    /// segment). Caller-supplied hash fields on NEW writes are stripped;
    /// only the store computes them.
    public func verifyChain(table: String) throws -> TelemetryChainReport {
        let url = tableURL(table)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return TelemetryChainReport(table: table, totalRows: 0, hashedRows: 0, legacyRows: 0, brokenAt: nil)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw JarvisError.processFailure("Telemetry file \(url.path) is not valid UTF-8")
        }
        var prev = Self.chainGenesis
        var hashed = 0
        var legacy = 0
        var total = 0
        var lineNo = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            let line = String(rawLine)
            if line.isEmpty { continue }
            total += 1
            guard let rowData = line.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: rowData) as? [String: Any] else {
                throw JarvisError.processFailure("Telemetry row \(lineNo) in \(table) is not valid JSON")
            }
            guard let claimed = obj["rowHash"] as? String else {
                // Legacy / pre-chain row. Reset chain to genesis; the next
                // hashed row must explicitly claim GENESIS or pick up from
                // whatever its prevRowHash says.
                legacy += 1
                prev = Self.chainGenesis
                continue
            }
            guard let claimedPrev = obj["prevRowHash"] as? String else {
                throw JarvisError.processFailure("Telemetry row \(lineNo) in \(table) has rowHash but no prevRowHash")
            }
            if claimedPrev != prev {
                return TelemetryChainReport(table: table, totalRows: total, hashedRows: hashed, legacyRows: legacy, brokenAt: lineNo)
            }
            var body = obj
            body.removeValue(forKey: "rowHash")
            let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let expected = Self.sha256Hex(bodyData)
            if expected != claimed {
                return TelemetryChainReport(table: table, totalRows: total, hashedRows: hashed, legacyRows: legacy, brokenAt: lineNo)
            }
            hashed += 1
            prev = claimed
        }
        return TelemetryChainReport(table: table, totalRows: total, hashedRows: hashed, legacyRows: legacy, brokenAt: nil)
    }

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the rowHash of the last line in the file (unlocked — caller
    /// holds the store lock). Nil if file missing, empty, or tail row is
    /// a pre-chain legacy row with no rowHash field.
    private static func tailRowHashUnlocked(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last,
              let rowData = String(last).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: rowData) as? [String: Any],
              let hash = obj["rowHash"] as? String else {
            return nil
        }
        return hash
    }
}

public struct TelemetryChainReport: Equatable, Sendable {
    public let table: String
    public let totalRows: Int
    public let hashedRows: Int
    public let legacyRows: Int
    /// 1-indexed line number where the chain first failed, or nil if
    /// every hashed row validated against its prevRowHash.
    public let brokenAt: Int?

    public var isIntact: Bool { brokenAt == nil }
}
