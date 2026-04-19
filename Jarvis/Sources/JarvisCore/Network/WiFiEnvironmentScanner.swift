import CoreWLAN
import Foundation

public final class WiFiEnvironmentScanner {
    private let client = CWWiFiClient.shared()

    public struct WiFiSnapshot: Sendable {
        public let ssid: String?
        public let bssid: String?
        public let rssi: Int
        public let channel: Int
        public let channelWidth: Int
        public let phyMode: String
        public let noise: Int?
        public let timestamp: String
    }

    public func currentSnapshot() -> WiFiSnapshot {
        let iface = client.interface()
        return WiFiSnapshot(
            ssid: iface?.ssid(),
            bssid: iface?.bssid(),
            rssi: iface?.rssiValue() ?? 0,
            channel: iface?.wlanChannel().channelNumber ?? 0,
            channelWidth: iface?.wlanChannel().channelWidth.rawValue ?? 0,
            phyMode: phyModeString(iface?.activePHYMode()),
            noise: nil,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    public func scanForNetworks() -> [CWWiFiScanResult] {
        let iface = client.interface()
        return (try? iface?.scanForNetworks(withSSID: nil)) ?? []
    }

    private func phyModeString(_ mode: CWPhyMode?) -> String {
        guard let m = mode else { return "unknown" }
        switch m {
        case .wiFiMode80211a: return "802.11a"
        case .wiFiMode80211b: return "802.11b"
        case .wiFiMode80211g: return "802.11g"
        case .wiFiMode80211n: return "802.11n"
        case .wiFiMode80211ac: return "802.11ac"
        case .wiFiMode80211ax: return "802.11ax"
        default: return "unknown"
        }
    }
}
