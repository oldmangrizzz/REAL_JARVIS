import Foundation

/// A single memory recalled for prompt enrichment.
public struct RetrievedMemory: Sendable, Equatable {
    public let nodeID: String
    public let kind: String
    public let text: String
    public let score: Double

    public init(nodeID: String, kind: String, text: String, score: Double) {
        self.nodeID = nodeID
        self.kind = kind
        self.text = text
        self.score = score
    }
}

/// A pheromone-favored follow-up edge, seeded from a retrieved memory.
public struct PheromonePath: Sendable, Equatable {
    public let source: String
    public let target: String
    public let pheromone: Double
    public let somaticWeight: Double

    public var combinedWeight: Double { pheromone + somaticWeight }

    public init(source: String, target: String, pheromone: Double, somaticWeight: Double) {
        self.source = source
        self.target = target
        self.pheromone = pheromone
        self.somaticWeight = somaticWeight
    }
}

/// Combined semantic + stigmergic context for RLM prompt enrichment.
public struct RetrievalContext: Sendable, Equatable {
    public let query: String
    public let semanticMatches: [RetrievedMemory]
    public let pheromonePaths: [PheromonePath]

    public var isEmpty: Bool { semanticMatches.isEmpty && pheromonePaths.isEmpty }

    public init(query: String, semanticMatches: [RetrievedMemory], pheromonePaths: [PheromonePath]) {
        self.query = query
        self.semanticMatches = semanticMatches
        self.pheromonePaths = pheromonePaths
    }
}

/// Bridges the semantic memory graph (MemoryEngine) and the stigmergic
/// pheromone graph (PheromindEngine) into a single retrieval context that
/// can be prepended to an RLM prompt. Bridge is stateless aside from its
/// engine references and performs no persistence or telemetry of its own —
/// callers decide when to log via the engines they already own.
public final class ContextualRetrievalBridge {
    private let memory: MemoryEngine
    private let pheromind: PheromindEngine

    public init(memory: MemoryEngine, pheromind: PheromindEngine) {
        self.memory = memory
        self.pheromind = pheromind
    }

    /// Retrieve a `RetrievalContext` for the given query.
    /// - Parameters:
    ///   - query: Natural-language query used for semantic ranking.
    ///   - limit: Maximum number of semantic matches (also upper-bounds pheromone paths).
    public func retrieve(query: String, limit: Int = 4) -> RetrievalContext {
        guard limit > 0 else {
            return RetrievalContext(query: query, semanticMatches: [], pheromonePaths: [])
        }

        let ranked = memory.retrieveRanked(query: query, limit: limit)
        let semanticMatches = ranked.map {
            RetrievedMemory(nodeID: $0.node.id, kind: $0.node.kind, text: $0.node.text, score: $0.score)
        }

        var seenEdges: Set<String> = []
        var paths: [PheromonePath] = []
        for match in semanticMatches {
            guard let edge = pheromind.chooseNextEdge(from: match.nodeID) else { continue }
            let key = "\(edge.source)→\(edge.target)"
            guard !seenEdges.contains(key) else { continue }
            seenEdges.insert(key)
            guard let state = pheromind.state(for: edge) else { continue }
            paths.append(PheromonePath(
                source: edge.source,
                target: edge.target,
                pheromone: state.pheromone,
                somaticWeight: state.somaticWeight
            ))
        }

        paths.sort { $0.combinedWeight > $1.combinedWeight }
        if paths.count > limit {
            paths = Array(paths.prefix(limit))
        }

        return RetrievalContext(
            query: query,
            semanticMatches: semanticMatches,
            pheromonePaths: paths
        )
    }

    /// Wrap `basePrompt` with a structured retrieval header so an RLM can
    /// treat the recalled memories and pheromone paths as first-class symbols.
    /// When retrieval is empty, the base prompt is returned unchanged so RLM
    /// behavior on cold memory is identical to pre-bridge behavior.
    public func enrichedPrompt(basePrompt: String, query: String, limit: Int = 4) -> String {
        let context = retrieve(query: query, limit: limit)
        return Self.format(basePrompt: basePrompt, context: context)
    }

    static func format(basePrompt: String, context: RetrievalContext) -> String {
        if context.isEmpty { return basePrompt }

        var lines: [String] = []
        lines.append("## Retrieved Context")
        lines.append("Query: \(context.query)")

        if !context.semanticMatches.isEmpty {
            lines.append("")
            lines.append("### Semantic memories")
            for (index, match) in context.semanticMatches.enumerated() {
                let score = String(format: "%.3f", match.score)
                lines.append("M\(index) [\(match.kind) score=\(score)]: \(match.text)")
            }
        }

        if !context.pheromonePaths.isEmpty {
            lines.append("")
            lines.append("### Pheromone paths")
            for (index, path) in context.pheromonePaths.enumerated() {
                let pher = String(format: "%.3f", path.pheromone)
                let soma = String(format: "%.3f", path.somaticWeight)
                lines.append("E\(index): \(path.source) → \(path.target) [pheromone=\(pher) somatic=\(soma)]")
            }
        }

        lines.append("")
        lines.append("## Prompt")
        lines.append(basePrompt)
        return lines.joined(separator: "\n")
    }

    /// Close the loop: deposit pheromone on every edge surfaced in the
    /// supplied `RetrievalContext`. Called by an RLM orchestrator after it
    /// observes whether a recalled path helped the answer. `signal` is the
    /// outcome classifier (reinforce on success, repel on failure,
    /// neutral to apply passive evaporation only). `magnitude` defaults to
    /// 1.0; callers can dampen low-confidence signals by passing a smaller
    /// value.
    ///
    /// Returns the number of edges actually deposited on. Edges are looked
    /// up by the exact `(source, target)` pair reported in the context;
    /// this makes the call idempotent with respect to the retrieval that
    /// produced it — no stale-path re-amplification.
    @discardableResult
    public func recordOutcome(
        context: RetrievalContext,
        signal: TernarySignal,
        magnitude: Double = 1.0,
        agentID: String,
        now: Date = Date()
    ) throws -> Int {
        guard !context.pheromonePaths.isEmpty else { return 0 }
        guard magnitude > 0.0 else { return 0 }

        let deposits = context.pheromonePaths.map { path in
            PheromoneDeposit(
                edge: EdgeKey(source: path.source, target: path.target),
                signal: signal,
                magnitude: magnitude,
                agentID: agentID,
                timestamp: now
            )
        }
        _ = try pheromind.applyGlobalUpdate(deposits: deposits, now: now)
        return deposits.count
    }
}
