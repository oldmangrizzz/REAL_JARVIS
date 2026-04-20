import Foundation

/// NAV-001 Phase D: TTL-gated in-memory hazard cache.
///
/// Actor-isolated for thread safety. No disk persistence — hazards
/// are refreshed from OSINT sources and pruned when stale.
/// Production may later add a disk-backed cache, but this spec
/// explicitly scopes to in-memory only.
public actor HazardCache {
    private let ttl: TimeInterval
    private var store: [String: (features: [HazardOverlayFeature], insertedAt: Date)] = [:]

    public init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    /// Get cached features if still fresh. Returns nil if expired or missing.
    public func get(_ key: String) -> [HazardOverlayFeature]? {
        guard let entry = store[key] else { return nil }
        let age = Date().timeIntervalSince(entry.insertedAt)
        guard age < ttl else {
            store.removeValue(forKey: key)
            return nil
        }
        return entry.features
    }

    /// Store features with current timestamp.
    public func put(_ key: String, _ value: [HazardOverlayFeature]) {
        store[key] = (features: value, insertedAt: Date())
    }
}