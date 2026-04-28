import Foundation

// MARK: - EPIC-04 Recall types

public typealias MemoryID = String

/// Episodic/semantic/somatic classification for v1 memory entries.
public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case episodic
    case semantic
    case somatic

    /// Map legacy KnowledgeNode.kind strings to MemoryKind.
    static func from(nodeKind: String) -> MemoryKind {
        switch nodeKind {
        case "entity":  return .semantic
        case "somatic": return .somatic
        default:        return .episodic   // document, chunk, unknown
        }
    }
}

/// Filter descriptor passed to `MemoryEngine.recall(query:)`.
///
/// - `entities` — case-insensitive substring match against entry payload + entity tags.
///   Empty list matches all entries.
/// - `kinds`    — restrict to the given `MemoryKind` set. Empty set resolves to all kinds.
/// - `since`    — exclude entries older than this date.
/// - `limit`    — maximum number of entries to return; clamped to [1, 200].
public struct RecallQuery: Codable, Sendable {
    public let entities: [String]
    public let kinds: Set<MemoryKind>
    public let since: Date?
    public let limit: Int

    public init(
        entities: [String] = [],
        kinds: Set<MemoryKind> = Set(MemoryKind.allCases),
        since: Date? = nil,
        limit: Int = 20
    ) {
        self.entities = entities
        self.kinds = kinds.isEmpty ? Set(MemoryKind.allCases) : kinds
        self.since = since
        self.limit = min(max(1, limit), 200)
    }
}
