import CryptoKit
import Foundation

// MARK: - EPIC-04 Result types

/// A single entry in the v1 episodic memory chain.
public struct MemoryEntry: Codable, Sendable, Identifiable {
    public let id: MemoryID
    public let kind: MemoryKind
    public let payload: String
    public let entities: [String]
    public let witnessSha256: String
    public let createdAt: Date
    public let prevSha256: String?

    public init(
        id: MemoryID,
        kind: MemoryKind,
        payload: String,
        entities: [String],
        witnessSha256: String,
        createdAt: Date,
        prevSha256: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.entities = entities
        self.witnessSha256 = witnessSha256
        self.createdAt = createdAt
        self.prevSha256 = prevSha256
    }

    /// Recompute the SHA-256 witness for this entry's content.
    /// Use to verify chain integrity after loading from disk.
    public func computeWitnessSha256() -> String {
        sha256hex("\(id)|\(kind.rawValue)|\(payload)|\(prevSha256 ?? "")")
    }
}

/// Return type of `MemoryEngine.recall(query:)`.
public struct RecallResult: Codable, Sendable {
    /// Entries sorted by `createdAt` descending.
    public let entries: [MemoryEntry]
    /// `true` iff every returned entry's `witnessSha256` matches its recomputed hash.
    public let integrityOK: Bool
    /// ID of the first entry where the chain breaks, or `nil` when `integrityOK` is `true`.
    public let chainBreakAt: MemoryID?

    public init(entries: [MemoryEntry], integrityOK: Bool, chainBreakAt: MemoryID? = nil) {
        self.entries = entries
        self.integrityOK = integrityOK
        self.chainBreakAt = chainBreakAt
    }

    /// Verify the chain of `entries` against their stored `witnessSha256` values.
    /// O(n) in the number of entries.
    public static func verify(_ entries: [MemoryEntry]) -> (integrityOK: Bool, chainBreakAt: MemoryID?) {
        for entry in entries {
            if entry.computeWitnessSha256() != entry.witnessSha256 {
                return (false, entry.id)
            }
        }
        return (true, nil)
    }
}

// MARK: - Internal utility

func sha256hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
