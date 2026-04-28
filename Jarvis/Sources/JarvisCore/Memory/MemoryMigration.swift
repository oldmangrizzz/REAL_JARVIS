import CryptoKit
import Foundation

// MARK: - EPIC-04 — v0 → v1 Memory Graph Migration

/// Handles migration from the legacy `knowledge-graph.json` (v0, no version field)
/// to the v1 Merkle-chain format at `knowledge-graph.v1.json`.
///
/// Migration is idempotent: if the v1 file already exists it is loaded directly.
/// A copy of the v0 file is preserved as `knowledge-graph.v0.bak`.
public struct MemoryMigration {

    // MARK: - On-disk v1 envelope

    struct V1Envelope: Codable {
        let version: Int
        let genesisSha256: String
        let createdAt: String
        var entries: [MemoryEntry]
        let indexSha256: String
    }

    // MARK: - File names

    static let v1FileName   = "knowledge-graph.v1.json"
    static let v0BakFileName = "knowledge-graph.v0.bak"

    // MARK: - Public API

    /// Load the v1 entry list from `storageDirectory`, migrating from v0 if needed.
    ///
    /// - Parameters:
    ///   - storageDirectory: The `.jarvis/storage` directory for this workspace.
    ///   - legacyGraph:      The already-decoded v0 `KnowledgeGraph` (used only if v1 doesn't exist).
    ///   - telemetry:        Receives a `memory.migrated.v0_to_v1` trace when migration occurs.
    ///   - dateString:       ISO-8601 creation timestamp written into the envelope (injectable for tests).
    /// - Returns: The decoded `[MemoryEntry]` list, guaranteed to be in ascending-`createdAt` chain order.
    @discardableResult
    public static func loadOrMigrate(
        storageDirectory: URL,
        legacyGraph: KnowledgeGraph,
        telemetry: TelemetryStore,
        dateString: String = ISO8601DateFormatter().string(from: Date())
    ) throws -> [MemoryEntry] {
        let v1URL  = storageDirectory.appendingPathComponent(v1FileName)
        let v0URL  = storageDirectory.appendingPathComponent("knowledge-graph.json")
        let bakURL = storageDirectory.appendingPathComponent(v0BakFileName)

        if FileManager.default.fileExists(atPath: v1URL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: v1URL)
            let envelope = try decoder.decode(V1Envelope.self, from: data)
            return envelope.entries
        }

        // v1 absent → build from legacy graph and write
        let entries = buildEntries(from: legacyGraph)
        let genesis   = entries.first?.witnessSha256 ?? sha256hex("genesis-empty")
        let indexHash = sha256hex(entries.map(\.id).joined())

        let envelope = V1Envelope(
            version:      1,
            genesisSha256: genesis,
            createdAt:    dateString,
            entries:      entries,
            indexSha256:  indexHash
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting   = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try data.write(to: v1URL)

        // Preserve v0 as .bak (copy, leave original for MemoryEngine)
        if FileManager.default.fileExists(atPath: v0URL.path),
           !FileManager.default.fileExists(atPath: bakURL.path) {
            try FileManager.default.copyItem(at: v0URL, to: bakURL)
        }

        try? telemetry.logExecutionTrace(
            workflowID:    "memory-migration",
            stepID:        "memory.migrated.v0_to_v1",
            inputContext:  "nodes=\(legacyGraph.nodes.count)",
            outputResult:  "entries=\(entries.count)",
            status:        "success"
        )

        return entries
    }

    // MARK: - Internal helpers

    /// Convert legacy KnowledgeGraph nodes into a Merkle-chained `[MemoryEntry]`.
    static func buildEntries(from graph: KnowledgeGraph) -> [MemoryEntry] {
        let formatter = ISO8601DateFormatter()
        var prevHash: String? = nil

        // Sort ascending so older entries link to earlier hashes
        let ordered = graph.nodes.sorted {
            let a = formatter.date(from: $0.timestamp) ?? .distantPast
            let b = formatter.date(from: $1.timestamp) ?? .distantPast
            return a < b
        }

        return ordered.map { node in
            let kind      = MemoryKind.from(nodeKind: node.kind)
            let createdAt = formatter.date(from: node.timestamp) ?? .distantPast
            let entityIDs = graph.edges
                .filter { $0.source == node.id && $0.relation == "mentions" }
                .map(\.target)
            let entityTexts = entityIDs.compactMap { eid in
                graph.nodes.first(where: { $0.id == eid })?.text
            }
            let witness = sha256hex("\(node.id)|\(kind.rawValue)|\(node.text)|\(prevHash ?? "")")
            let entry = MemoryEntry(
                id:           node.id,
                kind:         kind,
                payload:      node.text,
                entities:     entityTexts,
                witnessSha256: witness,
                createdAt:    createdAt,
                prevSha256:   prevHash
            )
            prevHash = witness
            return entry
        }
    }
}
