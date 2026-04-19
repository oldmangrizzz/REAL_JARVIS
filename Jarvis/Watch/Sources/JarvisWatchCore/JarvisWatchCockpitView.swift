import SwiftUI

public struct JarvisWatchCockpitView: View {
    @ObservedObject private var store: JarvisWatchCockpitStore

    public init(store: JarvisWatchCockpitStore) {
        self.store = store
    }

    public var body: some View {
        List {
            Section("Vitals") {
                LabeledContent("Heart Rate", value: store.vitals.heartRateLine)
                if !store.vitals.lastUpdated.isEmpty {
                    Text(store.vitals.lastUpdated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Host State") {
                Text(store.state.snapshot?.statusLine ?? "Awaiting host snapshot.")
                LabeledContent("Tunnel", value: store.connectionState.rawValue)
                if !store.diagnostics.isEmpty {
                    Text(store.diagnostics)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Authorization") {
                Text("Commands are restricted to the Obsidian Command Bar and terminal.")
                Button("Refresh") {
                    Task {
                        await store.refresh()
                    }
                }
            }

            Section("Thoughts") {
                if store.state.thoughts.isEmpty {
                    Text("No mirrored thought traces.")
                } else {
                    ForEach(store.state.thoughts.prefix(3)) { thought in
                        Text(thought.trace.joined(separator: " | "))
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Jarvis")
    }
}
