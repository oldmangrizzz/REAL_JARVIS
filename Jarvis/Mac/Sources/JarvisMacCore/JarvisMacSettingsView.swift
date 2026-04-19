import SwiftUI

struct JarvisMacSettingsView: View {
    @ObservedObject var store: JarvisMacCockpitStore

    var body: some View {
        Form {
            Section("Host Connection") {
                TextField("Host Address", text: .constant("charlie.grizzlymedicine.icu"))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                SecureField("Shared Secret", text: .constant(""))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Port", text: .constant("3000"))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
            }

            Section("Voice Gate") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text("Read-only (controlled by host)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let gate = store.voiceGate {
                    HStack {
                        Text("Current State")
                        Spacer()
                        Text(gate.state.description)
                            .fontWeight(.semibold)
                            .foregroundColor(gateStateColor(gate.state))
                    }
                }
            }

            Section("Capabilities") {
                Button("Edit Display Registry") {
                    print("Opening capability registry editor...")
                }
                .buttonStyle(.bordered)

                Button("Edit Accessory Registry") {
                    print("Opening accessory registry editor...")
                }
                .buttonStyle(.bordered)
            }

            Section("Advanced") {
                Toggle(isOn: .constant(false)) {
                    Text("Host Mode (run tunnel server locally)")
                }

                Button("Export Diagnostics") {
                    print("Exporting diagnostics...")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .navigationTitle("Settings")
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
