import Foundation
import CryptoKit  // CX-037: SHA256 for stableHash

public struct MainContext: Codable, Sendable {
    public var systemInstructions: String
    public var workingContext: [String: String]
    public var fifoQueue: [String]
}

public struct KnowledgeNode: Codable, Sendable {
    public let id: String
    public let kind: String
    public let text: String
    public let embedding: [Double]
    public let timestamp: String
}

public struct KnowledgeEdge: Codable, Sendable {
    public let source: String
    public let target: String
    public let relation: String
    public var weight: Double
    public let timestamp: String?
}

public struct KnowledgeGraph: Codable, Sendable {
    public var nodes: [KnowledgeNode]
    public var edges: [KnowledgeEdge]
}

public struct MemifyResult: Sendable {
    public let ingestedFiles: [String]
    public let nodeCount: Int
    public let edgeCount: Int
    public let episodicEdgeCount: Int

    public var json: [String: Any] {
        [
            "ingestedFiles": ingestedFiles,
            "nodeCount": nodeCount,
            "edgeCount": edgeCount,
            "episodicEdgeCount": episodicEdgeCount
        ]
    }
}

public struct PageInResult {
    public let query: String
    public let pageFaultTriggered: Bool
    public let matches: [String]
    public let somaticEdges: [[String: Any]]

    public var json: [String: Any] {
        [
            "query": query,
            "pageFaultTriggered": pageFaultTriggered,
            "matches": matches,
            "somaticEdges": somaticEdges
        ]
    }
}

public final class MemoryEngine {
    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore
    private let graphURL: URL
    private let contextURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dateFormatter = ISO8601DateFormatter()
    private let lock = NSLock()
    private let maxNodes = 50_000  // CX-013: cap graph growth to prevent OOM

    private(set) var graph: KnowledgeGraph
    private(set) var mainContext: MainContext

    public init(paths: WorkspacePaths, telemetry: TelemetryStore) throws {
        self.paths = paths
        self.telemetry = telemetry
        self.graphURL = paths.storageDirectory.appendingPathComponent("knowledge-graph.json")
        self.contextURL = paths.storageDirectory.appendingPathComponent("main-context.json")
        self.graph = KnowledgeGraph(nodes: [], edges: [])
        self.mainContext = MainContext(
            systemInstructions: "Maintain a calm, dry, highly competent British butler persona while operating within deterministic workflows.",
            workingContext: [:],
            fifoQueue: []
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try loadPersistedState()
    }

    public func defaultMemifyTargets() throws -> [URL] {
        let telemetryFiles = ["execution_traces", "recursive_thoughts", "stigmergic_signals", "vagal_tone", "node_registry"].map(telemetry.tableURL)
        let traceFiles = try FileManager.default.contentsOfDirectory(at: paths.traceDirectory, includingPropertiesForKeys: nil)
        return (telemetryFiles + traceFiles).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func memify(logFileURLs: [URL]) throws -> MemifyResult {
        lock.lock(); defer { lock.unlock() }
        var ingestedFiles: [String] = []
        var episodicCount = 0

        for fileURL in logFileURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modified = (attributes?[.modificationDate] as? Date) ?? Date()
            let timestamp = dateFormatter.string(from: modified)

            let documentID = "doc-\(stableHashHex(content + fileURL.lastPathComponent))"
            upsert(node: KnowledgeNode(
                id: documentID,
                kind: "document",
                text: content,
                embedding: embed(content),
                timestamp: timestamp
            ))

            let chunks = semanticChunks(from: content)
            for (index, chunk) in chunks.enumerated() {
                let chunkID = "\(documentID)-chunk-\(index)"
                upsert(node: KnowledgeNode(
                    id: chunkID,
                    kind: "chunk",
                    text: chunk,
                    embedding: embed(chunk),
                    timestamp: timestamp
                ))
                upsert(edge: KnowledgeEdge(source: documentID, target: chunkID, relation: "contains", weight: 0.5, timestamp: timestamp))
                upsert(edge: KnowledgeEdge(source: chunkID, target: documentID, relation: "episode", weight: 1.0, timestamp: timestamp))
                episodicCount += 1
            }

            let entities = extractEntities(from: content)
            for entity in entities {
                let entityID = "entity-\(stableHashHex(entity))"
                upsert(node: KnowledgeNode(
                    id: entityID,
                    kind: "entity",
                    text: entity,
                    embedding: embed(entity),
                    timestamp: timestamp
                ))
                upsert(edge: KnowledgeEdge(source: documentID, target: entityID, relation: "mentions", weight: 0.35, timestamp: timestamp))
            }

            ingestedFiles.append(fileURL.lastPathComponent)
        }

        // CX-013: prune oldest nodes if graph exceeds limit
        if graph.nodes.count > maxNodes {
            let pruneTo = Int(Double(maxNodes) * 0.8)
            let sorted = graph.nodes.sorted { $0.timestamp < $1.timestamp }
            let toRemove = Set(sorted.prefix(graph.nodes.count - pruneTo).map(\.id))
            graph.nodes.removeAll { toRemove.contains($0.id) }
            graph.edges.removeAll { toRemove.contains($0.source) || toRemove.contains($0.target) }
        }

        try persist()
        return MemifyResult(
            ingestedFiles: ingestedFiles,
            nodeCount: graph.nodes.count,
            edgeCount: graph.edges.count,
            episodicEdgeCount: episodicCount
        )
    }

    public func pageIn(query: String, limit: Int) throws -> PageInResult {
        lock.lock(); defer { lock.unlock() }
        let queryVector = embed(query)
        let ranked = graph.nodes
            .map { ($0, cosineSimilarity(lhs: queryVector, rhs: $0.embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

        let matches = ranked.map(\.0.text)
        mainContext.workingContext["lastPagedQuery"] = query
        mainContext.workingContext["lastPagedMatchCount"] = String(matches.count)
        mainContext.fifoQueue.append(query)
        if mainContext.fifoQueue.count > 8 {
            mainContext.fifoQueue.removeFirst(mainContext.fifoQueue.count - 8)
        }
        try persist()

        let topNodeIDs = Set(ranked.map(\.0.id))
        let somaticEdges = graph.edges
            .filter { topNodeIDs.contains($0.source) || topNodeIDs.contains($0.target) }
            .sorted { $0.weight > $1.weight }
            .prefix(limit)
            .map { edge in
                [
                    "source": edge.source,
                    "target": edge.target,
                    "relation": edge.relation,
                    "weight": edge.weight,
                    "timestamp": edge.timestamp ?? ""
                ]
            }

        try telemetry.logRecursiveThought(
            sessionID: "memgpt-page-\(UUID().uuidString)",
            trace: [
                "query=\(query)",
                "ranked_matches=\(matches.count)",
                "working_context_keys=\(mainContext.workingContext.keys.sorted())"
            ],
            memoryPageFault: true
        )

        return PageInResult(
            query: query,
            pageFaultTriggered: true,
            matches: matches,
            somaticEdges: somaticEdges
        )
    }

    /// Pure-read ranked retrieval used by ContextualRetrievalBridge.
    /// No persistence, no telemetry, no fifo mutation — safe for hot-path retrieval
    /// before RLM invocation. Returns (node, cosineScore) sorted high→low.
    public func retrieveRanked(query: String, limit: Int) -> [(node: KnowledgeNode, score: Double)] {
        lock.lock(); defer { lock.unlock() }
        guard limit > 0 else { return [] }
        let queryVector = embed(query)
        return graph.nodes
            .map { ($0, cosineSimilarity(lhs: queryVector, rhs: $0.embedding)) }
            .filter { $0.1 > 0.0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (node: $0.0, score: $0.1) }
    }

    public func recordSomaticPath(edge: EdgeKey, weight: Double) throws {
        lock.lock(); defer { lock.unlock() }
        upsert(edge: KnowledgeEdge(
            source: edge.source,
            target: edge.target,
            relation: "somatic",
            weight: weight,
            timestamp: dateFormatter.string(from: Date())
        ))
        try persist()
    }

    private func loadPersistedState() throws {
        if FileManager.default.fileExists(atPath: graphURL.path) {
            graph = try decoder.decode(KnowledgeGraph.self, from: Data(contentsOf: graphURL))
        }
        if FileManager.default.fileExists(atPath: contextURL.path) {
            mainContext = try decoder.decode(MainContext.self, from: Data(contentsOf: contextURL))
        }
    }

    private func persist() throws {
        try encoder.encode(graph).write(to: graphURL)
        try encoder.encode(mainContext).write(to: contextURL)
    }

    private func upsert(node: KnowledgeNode) {
        if let index = graph.nodes.firstIndex(where: { $0.id == node.id }) {
            graph.nodes[index] = node
        } else {
            graph.nodes.append(node)
        }
    }

    private func upsert(edge: KnowledgeEdge) {
        if let index = graph.edges.firstIndex(where: { $0.source == edge.source && $0.target == edge.target && $0.relation == edge.relation }) {
            var existing = graph.edges[index]
            existing.weight = max(existing.weight, edge.weight)
            graph.edges[index] = existing
        } else {
            graph.edges.append(edge)
        }
    }

    private func semanticChunks(from text: String) -> [String] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .chunked(by: 2)
            .map { $0.joined(separator: " ") }
    }

    private func extractEntities(from text: String) -> [String] {
        let pattern = #"(?:[A-Z][A-Za-z0-9_\-/.]{2,}|[a-z0-9_\-/.]+\.(?:swift|yaml|yml|json|ts|py))"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        let entities = matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        return Array(Set(entities)).sorted()
    }

    private func embed(_ text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: 32)
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        for token in tokens where !token.isEmpty {
            let index = abs(stableHash(String(token))) % vector.count
            vector[index] += 1.0
        }
        return normalize(vector)
    }

    private func cosineSimilarity(lhs: [Double], rhs: [Double]) -> Double {
        guard lhs.count == rhs.count else { return 0.0 }
        let dot = zip(lhs, rhs).reduce(0.0) { $0 + ($1.0 * $1.1) }
        let lhsNorm = sqrt(lhs.reduce(0.0) { $0 + ($1 * $1) })
        let rhsNorm = sqrt(rhs.reduce(0.0) { $0 + ($1 * $1) })
        guard lhsNorm > 0.0, rhsNorm > 0.0 else { return 0.0 }
        return dot / (lhsNorm * rhsNorm)
    }

    private func normalize(_ values: [Double]) -> [Double] {
        let magnitude = sqrt(values.reduce(0.0) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return values }
        return values.map { $0 / magnitude }
    }

    // R03: return full SHA256 hex string for use as document/entity IDs (collision-safe)
    private func stableHashHex(_ text: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func stableHash(_ text: String) -> Int {
        // CX-037: fold SHA256 to Int for vector bucket indexing (64 bits sufficient)
        let digest = CryptoKit.SHA256.hash(data: Data(text.utf8))
        return digest.withUnsafeBytes { ptr in
            let raw = ptr.load(as: UInt64.self)  // fold first 8 bytes
            return Int(truncatingIfNeeded: raw)
        }
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
