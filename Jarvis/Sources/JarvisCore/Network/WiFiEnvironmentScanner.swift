import CoreWLAN
import CryptoKit
import Foundation

/// SPEC-009 fail-closed Wi-Fi environment scanner.
///
/// Tier discipline:
///   - Operator tier sees raw SSID + BSSID. Everyone else sees only a
///     stable SHA-256 hash of the BSSID (enough for room-clustering by
///     PresenceDetector) and NO SSID. We never leak network identity
///     through a family-tier or guest-tier surface.
///   - If the WLAN interface is absent (no hardware, entitlement
///     denied, or scanner unavailable), we fail CLOSED: status is set
///     to `.noInterface`, all identifiers are nil, and RSSI is 0. A
///     caller that doesn't inspect `status` simply sees "nobody home"
///     rather than a plausible-looking zero snapshot.
@available(macOS 12.0, *)
public final class WiFiEnvironmentScanner {
    private let client: CWWiFiClient?

    public init() {
        // CoreWLAN sandboxing on some hosts may refuse to vend a client.
        // Treat that as a permission failure and fail closed downstream.
        self.client = CWWiFiClient.shared()
    }

    public enum Status: String, Sendable, Equatable {
        /// Interface available, snapshot populated.
        case ok
        /// No WLAN interface present (no hardware, sandboxed, or
        /// entitlement denied).
        case noInterface
    }

    public struct WiFiSnapshot: Sendable {
        /// Raw SSID. Populated only when snapshot is resolved for the
        /// operator tier. Nil otherwise.
        public let ssid: String?
        /// Raw BSSID (MAC). Operator tier only.
        public let bssid: String?
        /// Stable SHA-256 hash of the BSSID, safe to expose to any tier.
        /// Nil when no interface was readable.
        public let bssidHash: String?
        public let rssi: Int
        public let channel: Int
        public let channelWidth: Int
        public let phyMode: String
        public let noise: Int?
        public let timestamp: String
        public let status: Status
    }

    /// Returns an operator-tier snapshot. Kept for legacy callers; new
    /// code on any surface that might bind a non-operator principal
    /// should call `currentSnapshot(for:)` instead.
    public func currentSnapshot() -> WiFiSnapshot {
        currentSnapshot(for: .operatorTier)
    }

    public func currentSnapshot(for principal: Principal) -> WiFiSnapshot {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        guard let iface = client?.interface() else {
            return WiFiSnapshot(
                ssid: nil,
                bssid: nil,
                bssidHash: nil,
                rssi: 0,
                channel: 0,
                channelWidth: 0,
                phyMode: "unknown",
                noise: nil,
                timestamp: timestamp,
                status: .noInterface
            )
        }
        let rawSSID = iface.ssid()
        let rawBSSID = iface.bssid()
        let hash = rawBSSID.flatMap { Self.stableHash(of: $0) }
        let channel = iface.wlanChannel()
        let isOperator: Bool
        switch principal {
        case .operatorTier: isOperator = true
        case .companion, .guestTier, .responder: isOperator = false
        }
        return WiFiSnapshot(
            ssid: isOperator ? rawSSID : nil,
            bssid: isOperator ? rawBSSID : nil,
            bssidHash: hash,
            rssi: iface.rssiValue(),
            channel: channel?.channelNumber ?? 0,
            channelWidth: channel?.channelWidth.rawValue ?? 0,
            phyMode: phyModeString(iface.activePHYMode()),
            noise: nil,
            timestamp: timestamp,
            status: .ok
        )
    }

    #if canImport(CoreWLAN) && os(macOS)
    @available(macOS 13.0, *)
    public func scanForNetworks(for principal: Principal = .operatorTier) -> Set<CWNetwork> {
        // Raw network scan results carry SSID/BSSID of every nearby AP,
        // which is strong location-leak material. Fail closed to empty
        // set for any non-operator principal.
        switch principal {
        case .operatorTier:
            guard let iface = client?.interface() else { return [] }
            return (try? iface.scanForNetworks(withSSID: nil)) ?? []
        case .companion, .guestTier, .responder:
            return []
        }
    }
    #endif

    private static func stableHash(of value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func phyModeString(_ mode: Any?) -> String {
        guard mode != nil else { return "unknown" }
        let desc = String(describing: mode)
        if desc.contains("802.11a") { return "802.11a" }
        if desc.contains("802.11b") { return "802.11b" }
        if desc.contains("802.11g") { return "802.11g" }
        if desc.contains("802.11n") { return "802.11n" }
        if desc.contains("802.11ac") { return "802.11ac" }
        if desc.contains("802.11ax") { return "802.11ax" }
        return desc
    }
}