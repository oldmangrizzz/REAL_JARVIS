import Foundation

// MARK: - MK2-EPIC-02: Replay defense (T2)
//
// Tracks nonces for destructive tunnel frames within a 15-minute sliding
// window. Any frame whose nonce was already seen is dropped, preventing
// an attacker who captured a frame from replaying it.
//
// Actor preferred per spec; the host tunnel server bridges into this from
// its serial DispatchQueue via a DispatchSemaphore wrapper (see
// JarvisHostTunnelServer.validateDestructiveNonce).

public actor DestructiveNonceTracker {
    private var window: [String: Date] = [:]
    private let windowDuration: TimeInterval = 15 * 60  // 15 min

    public init() {}

    /// Insert `nonce` and return `true` if it is fresh (not seen before).
    /// Returns `false` if the nonce is a replay or empty.
    public func insertAndValidate(_ nonce: String) -> Bool {
        guard !nonce.isEmpty else { return false }
        pruneExpired()
        guard window[nonce] == nil else { return false }
        window[nonce] = Date()
        return true
    }

    /// Current window size (for testing).
    public var count: Int { window.count }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        window = window.filter { $0.value > cutoff }
    }
}
