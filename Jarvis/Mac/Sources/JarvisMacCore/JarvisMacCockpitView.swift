import SwiftUI

public struct JarvisMacCockpitView: View {
    @ObservedObject var store: JarvisMacCockpitStore
    @State private var selectedPanel: Panel? = .status

    enum Panel: String, CaseIterable {
        case status = "Status"
        case voiceGate = "Voice Gate"
        case spatialHUD = "Spatial HUD"
        case authorization = "Authorization"
        case homeKit = "HomeKit"
        case obsidian = "Obsidian"
        case thought = "Thought"
        case signal = "Signal"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPanel) {
                ForEach(Panel.allCases, id: \.self) { panel in
                    NavigationLink(panel.rawValue, value: panel)
                }
            }
            .navigationTitle("JARVIS")
            .listStyle(SidebarListStyle())
        } detail: {
            switch selectedPanel {
            case .status:
                JarvisStatusPanel(store: store)
            case .voiceGate:
                JarvisVoiceGatePanel(store: store)
            case .spatialHUD:
                JarvisSpatialHUDPanel(store: store)
            case .authorization:
                JarvisAuthorizationPanel(store: store)
            case .homeKit:
                JarvisHomeKitPanel(store: store)
            case .obsidian:
                JarvisObsidianPanel(store: store)
            case .thought:
                JarvisThoughtPanel(store: store)
            case .signal:
                JarvisSignalPanel(store: store)
            case nil:
                JarvisWelcomePanel()
            }
        }
    }
}

// MARK: - Status Panel
struct JarvisStatusPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    Text("State")
                    Spacer()
                    Text(store.connectionState.description)
                        .fontWeight(.semibold)
                        .foregroundColor(stateColor(store.connectionState))
                }
                if !store.diagnostics.isEmpty {
                    HStack {
                        Text("Diagnostics")
                        Spacer()
                        Text(store.diagnostics)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Voice Gate") {
                if let gate = store.voiceGate {
                    HStack {
                        Text("State")
                        Spacer()
                        Text(gate.state.description)
                            .fontWeight(.semibold)
                            .foregroundColor(gateStateColor(gate.state))
                    }
                } else {
                    Text("Voice gate not available")
                        .foregroundColor(.secondary)
                }
            }

            Section("Spatial HUD") {
                Text("\(store.spatialHUD.count) elements")
                    .font(.headline)
                if !store.spatialHUD.isEmpty {
                    List(store.spatialHUD, id: \.id) { element in
                        HStack {
                            Text(element.title ?? "Untitled")
                            Spacer()
                            Circle()
                                .fill(gateStateColor(element.state))
                                .frame(width: 8, height: 8)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.systemBackground))
    }

    func stateColor(_ state: JarvisConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .error: return .red
        }
    }

    func gateStateColor(_ state: JarvisVoiceGateState) -> Color {
        switch state {
        case .green: return .green
        case .red: return .red
        case .yellow, .orange: return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Voice Gate Panel
struct JarvisVoiceGatePanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Gate Status")
                .font(.headline)
                .padding(.bottom, 8)

            if let gate = store.voiceGate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("State")
                        Spacer()
                        Text(gate.state.description)
                            .font(.headline)
                            .foregroundColor(gateStateColor(gate.state))
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        Text(gate.model)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("References")
                        Spacer()
                        Text("\(gate.referenceCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                Text("Voice gate not initialized")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    func gateStateColor(_ state: JarvisVoiceGateState) -> Color {
        switch state {
        case .green: return .green
        case .red: return .red
        case .yellow, .orange: return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Spatial HUD Panel
struct JarvisSpatialHUDPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        List(store.spatialHUD, id: \.id) { element in
            VStack(alignment: .leading, spacing: 4) {
                Text(element.title ?? "Untitled")
                    .font(.headline)
                Text(element.anchor.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let content = element.content {
                    Text(content)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(gateStateColor(element.state).opacity(0.1))
            .cornerRadius(8)
        }
        .listStyle(PlainListStyle())
        .padding(16)
    }

    func gateStateColor(_ state: JarvisVoiceGateState) -> Color {
        switch state {
        case .green: return .green
        case .red: return .red
        case .yellow, .orange: return .yellow
        default: return .secondary
        }
    }
}

// MARK: - Authorization Panel
struct JarvisAuthorizationPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authorization Status")
                .font(.headline)
                .padding(.bottom, 8)

            HStack {
                Text("Connection")
                Spacer()
                if store.connectionState == .connected {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.green)
                    Text("Secure")
                        .foregroundColor(.green)
                        .font(.headline)
                } else {
                    Image(systemName: "lock.open")
                        .foregroundColor(.red)
                    Text("Insecure")
                        .foregroundColor(.red)
                        .font(.headline)
                }
            }

            Divider()

            HStack {
                Text("Tunnel")
                Spacer()
                Text(store.connectionState == .connected ? "Active" : "Inactive")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Role")
                Spacer()
                Text("macDesktop")
                    .font(.headline)
            }
        }
        .padding(16)
    }
}

// MARK: - HomeKit Panel
struct JarvisHomeKitPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(spacing: 16) {
            Text("HomeKit Bridge Status")
                .font(.headline)

            if let bridge = store.state.snapshot?.homeKitBridge {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bridge State")
                        Spacer()
                        Text(bridge.bridgeState)
                            .font(.headline)
                            .foregroundColor(bridge.reachable ? .green : .red)
                    }
                    if let address = bridge.charlieAddress {
                        HStack {
                            Text("Host")
                            Spacer()
                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let sources = bridge.authorizedCommandSources {
                        HStack {
                            Text("Authorized Sources")
                            Spacer()
                            Text(sources.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                Text("No HomeKit bridge data available")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Obsidian Panel
struct JarvisObsidianPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(spacing: 16) {
            Text("Obsidian Integration")
                .font(.headline)

            HStack {
                Button("Sync Vault") {
                    print("Syncing Obsidian vault...")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Divider()

            HStack {
                Text("Live Sync")
                Spacer()
                Text("Active")
                    .foregroundColor(.green)
            }

            HStack {
                Text("UATU Engine")
                Spacer()
                Text("Ready")
                    .foregroundColor(.green)
            }
        }
        .padding(16)
    }
}

// MARK: - Thought Panel
struct JarvisThoughtPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Thoughts")
                .font(.headline)
                .padding(.bottom, 8)

            if let thoughts = store.state.thoughts, !thoughts.isEmpty {
                ForEach(Array(thoughts.prefix(5)), id: \.self) { thought in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thought)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }
            } else {
                Text("No recent thoughts")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Signal Panel
struct JarvisSignalPanel: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Signals")
                .font(.headline)
                .padding(.bottom, 8)

            if let signals = store.state.signals, !signals.isEmpty {
                ForEach(Array(signals.prefix(5)), id: \.self) { signal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }
            } else {
                Text("No recent signals")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Welcome Panel
struct JarvisWelcomePanel: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.indigo)

            Text("Jarvis Desktop")
                .font(.title)
                .fontWeight(.bold)

            Text("Select a panel from the sidebar to view system status, spatial HUD, and more.")

            Button("Get Started") {
                // Initial setup
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
