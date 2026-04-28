import SwiftUI
import RealityKit

/// GrizzOS Main HUD Overlay
/// Tactical Wilderness FOB Theme - Green Phosphor / Red / Black / Silver
public struct HUDView: View {
    @ObservedObject var telemetry: TelemetryManager
    @ObservedObject var voiceManager: VoiceManager

    public init(telemetry: TelemetryManager, voiceManager: VoiceManager) {
        self.telemetry = telemetry
        self.voiceManager = voiceManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Upper Left Panel
            VStack(alignment: .leading, spacing: 8) {
                Text("LATENT TOKENS ACTIVE. WAITING FOR PROMPT.")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#DC143C"))

                Text("GrizzOS")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: "#50C878"))
                    .shadow(color: Color(hex: "#50C878").opacity(0.4), radius: 5)

                Text("Generative Ambient Spatial Workspace.\nMark LXVIII Interface Online.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: "#C0C0C0"))

                // Metrics Grid
                HStack(spacing: 20) {
                    MetricView(label: "A&Ox4 Status", value: telemetry.aox4Status, valueColor: telemetry.aox4Status == "NOMINAL" ? "#50C878" : "#DC143C")
                    MetricView(label: "Quorum Mesh", value: telemetry.isSynced ? "5/5 SYNCED" : "SYNC LOST", valueColor: telemetry.isSynced ? "#C0C0C0" : "#DC143C")
                }
                .padding(.top, 10)

                HStack(spacing: 20) {
                    MetricView(label: "Pheromind", value: "ACTIVE", valueColor: "#DC143C")
                    MetricView(label: "TinCan Firewall", value: "SECURE", valueColor: "#50C878")
                }

                // Log Output
                VStack(alignment: .leading, spacing: 4) {
                    LogLine(text: "[SYS] Listening via Coqui XTTS v2 (\(voiceManager.isConnected ? "Connected" : "Disconnected"))")
                    LogLine(text: "[SYS] RoomPlan LiDAR Mesh Loaded")
                    LogLine(text: "[SYS] Generative ambient tokens floating. Look to collapse.")
                }
                .padding(.top, 10)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#0c120c").opacity(0.88))
                    .border(Color(hex: "#50C878").opacity(0.5), width: 1)
            )
            .shadow(color: Color(hex: "#50C878").opacity(0.15), radius: 15)

            Spacer()
        }
        .padding(30)
    }
}

struct MetricView: View {
    let label: String
    let value: String
    let valueColor: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex: "#C0C0C0").opacity(0.7))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: valueColor))
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .overlay(Rectangle().frame(width: 2).foregroundColor(Color(hex: "#50C878")), alignment: .leading)
    }
}

struct LogLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(hex: "#C0C0C0").opacity(0.8))
    }
}

// Helper for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}