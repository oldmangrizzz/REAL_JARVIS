import SwiftUI

public enum JarvisCockpitLayout {
    case phone
    case tablet
}

public struct JarvisCockpitView: View {
    @ObservedObject private var store: JarvisMobileCockpitStore
    private let layout: JarvisCockpitLayout

    public init(store: JarvisMobileCockpitStore, layout: JarvisCockpitLayout) {
        self.store = store
        self.layout = layout
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: JarvisGMRIPalette.blackHex)
                    .ignoresSafeArea()

                ScrollView {
                    if layout == .tablet {
                        tabletBody
                    } else {
                        phoneBody
                    }
                }
            }
            .navigationTitle("JARVIS Cockpit")
            .toolbarBackground(Color(hex: JarvisGMRIPalette.blackHex), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusPanel
            voiceGatePanel
            spatialHUDPanel
            actionPanel
            bridgePanel
            vaultPanel
            thoughtPanel
            signalPanel
        }
        .padding()
    }

    private var tabletBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    statusPanel
                    voiceGatePanel
                    spatialHUDPanel
                }
                VStack(alignment: .leading, spacing: 20) {
                    actionPanel
                    bridgePanel
                    vaultPanel
                }
            }
            HStack(alignment: .top, spacing: 20) {
                thoughtPanel
                signalPanel
            }
        }
        .padding(24)
    }

    private var statusPanel: some View {
        WorkshopPanel(title: "Central Brain", glyph: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.state.snapshot?.statusLine ?? "Awaiting host snapshot.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex))

                Divider().background(Color(hex: JarvisGMRIPalette.emeraldGreenHex).opacity(0.3))

                LabeledWorkshopContent("Tunnel", value: store.connectionState.rawValue)
                LabeledWorkshopContent("Voice", value: store.voiceState)

                if !store.latestResponse.isEmpty {
                    LabeledWorkshopContent("Response", value: store.latestResponse)
                }

                if !store.diagnostics.isEmpty {
                    Text(store.diagnostics)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
                }
            }
        }
    }

    private var voiceGatePanel: some View {
        let gate = store.voiceGate
        let color = gateColor(gate?.state ?? .grey)

        return WorkshopPanel(title: "Voice Approval Gate", glyph: "shield.lefthalf.filled", color: color) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledWorkshopContent("State", value: gate?.stateName.uppercased() ?? "ABSENT", color: color)

                if let composite = gate?.composite {
                    LabeledWorkshopContent("Fingerprint", value: "\(composite.prefix(12))...")
                }

                if let repo = gate?.modelRepository {
                    LabeledWorkshopContent("Model", value: repo)
                }

                if let version = gate?.personaFramingVersion {
                    LabeledWorkshopContent("Framing", value: version)
                }

                if let approvedAt = gate?.approvedAtISO8601 {
                    LabeledWorkshopContent("Approved", value: approvedAt)
                }

                if let operatorLabel = gate?.operatorLabel {
                    LabeledWorkshopContent("Operator", value: operatorLabel)
                }

                if let notes = gate?.notes {
                    Text(notes)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var spatialHUDPanel: some View {
        let elements = store.spatialHUD
        return WorkshopPanel(title: "Spatial HUD Elements", glyph: "viewfinder.circle") {
            VStack(alignment: .leading, spacing: 10) {
                if elements.isEmpty {
                    Text("NO ACTIVE HOLOGRAPHIC ELEMENTS")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.5))
                } else {
                    ForEach(elements) { element in
                        HStack {
                            Image(systemName: element.glyph)
                                .foregroundStyle(gateColor(element.state))
                            VStack(alignment: .leading) {
                                Text(element.label)
                                    .font(.system(.subheadline, design: .monospaced))
                                if let detail = element.detail {
                                    Text(detail)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.8))
                                }
                            }
                            Spacer()
                            Text(element.anchor.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(4)
                                .background(Color(hex: JarvisGMRIPalette.emeraldGreenHex).opacity(0.1))
                        }
                    }
                }
            }
        }
    }

    private var actionPanel: some View {
        WorkshopPanel(title: "Authorization", glyph: "lock.shield") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Command execution restricted to Obsidian Command Bar and terminal.")
                    .font(.system(.caption, design: .monospaced))

                if let bridge = store.state.homeKitBridge {
                    LabeledWorkshopContent("Sources", value: bridge.authorizedCommandSources.joined(separator: ", "))
                    LabeledWorkshopContent("Regulation", value: "\(bridge.regulationVisibility) / \(bridge.distressState)")
                }
            }
        }
    }

    private var bridgePanel: some View {
        WorkshopPanel(title: "HomeKit Bridge", glyph: "house.fill") {
            VStack(alignment: .leading, spacing: 8) {
                if let bridge = store.state.homeKitBridge {
                    LabeledWorkshopContent("Bridge", value: bridge.bridgeName)
                    LabeledWorkshopContent("Node", value: "\(bridge.charlieAddress):\(bridge.homebridgePort)")
                    LabeledWorkshopContent("State", value: bridge.bridgeState)
                    LabeledWorkshopContent("Intercom", value: bridge.voiceIntercomRoute)
                } else {
                    Text("OFFLINE")
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.crimsonHex))
                }
            }
        }
    }

    private var vaultPanel: some View {
        WorkshopPanel(title: "Obsidian Control Plane", glyph: "square.stack.3d.up.fill") {
            VStack(alignment: .leading, spacing: 8) {
                if let vault = store.state.obsidianVault {
                    LabeledWorkshopContent("Vault", value: vault.databaseName)
                    LabeledWorkshopContent("Docs", value: "\(vault.docCount)")
                    LabeledWorkshopContent("Replication", value: vault.replicationObserved ? "ONLINE" : "PENDING")
                } else {
                    Text("NO SNAPSHOT")
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.5))
                }
            }
        }
    }

    private var thoughtPanel: some View {
        WorkshopPanel(title: "Recursive Thoughts", glyph: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                if store.state.thoughts.isEmpty {
                    Text("QUIET")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.5))
                } else {
                    ForEach(store.state.thoughts) { thought in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thought.trace.joined(separator: " > "))
                                .font(.system(.caption, design: .monospaced))
                            Text(thought.timestamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.6))
                        }
                    }
                }
            }
        }
    }

    private var signalPanel: some View {
        WorkshopPanel(title: "Stigmergic Signals", glyph: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                if store.state.signals.isEmpty {
                    Text("NO TRAFFIC")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.5))
                } else {
                    ForEach(store.state.signals) { signal in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(signal.nodeSource) -> \(signal.nodeTarget)")
                                    .font(.system(.caption, design: .monospaced))
                                Text("τ \(signal.ternaryValue) | φ \(String(format: "%.2f", signal.pheromone))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Color(hex: JarvisGMRIPalette.emeraldGreenHex).opacity(0.8))
                            }
                            Spacer()
                            Text(signal.timestamp.suffix(8))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.6))
                        }
                    }
                }
            }
        }
    }

    private func gateColor(_ state: JarvisSpatialIndicatorState) -> Color {
        Color(hex: state.paletteHex)
    }
}

// MARK: - Workshop Components (mobile-only)
//
// WorkshopPanel, LabeledWorkshopContent, and Color(hex:) are defined here
// because they are used exclusively by JarvisMobileCore's cockpit view.
// The watch app uses a different, simpler cockpit UI without these components.
// Do NOT import JarvisMobileCore into JarvisWatchCore or JarvisShared.

// MARK: - Workshop Components

struct WorkshopPanel<Content: View>: View {
    let title: String
    let glyph: String?
    let color: Color
    let content: Content

    init(title: String, glyph: String? = nil, color: Color = Color(hex: JarvisGMRIPalette.emeraldGreenHex), @ViewBuilder content: () -> Content) {
        self.title = title
        self.glyph = glyph
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let glyph {
                    Image(systemName: glyph)
                        .foregroundStyle(color)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
            }

            content
        }
        .padding(14)
        .background(Color(hex: JarvisGMRIPalette.blackHex).opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}

struct LabeledWorkshopContent: View {
    let label: String
    let value: String
    let color: Color

    init(_ label: String, value: String, color: Color = Color(hex: JarvisGMRIPalette.silverHex)) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: JarvisGMRIPalette.silverHex).opacity(0.7))
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Spacer()
        }
    }
}

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
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
