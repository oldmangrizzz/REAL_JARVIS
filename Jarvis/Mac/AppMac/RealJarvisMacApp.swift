import SwiftUI
import JarvisMacCore

@main
struct RealJarvisMacApp: App {
    @StateObject private var store: JarvisMacCockpitStore

    init() {
        _store = StateObject(wrappedValue: JarvisMacCockpitStore())
    }

    var body: some Scene {
        WindowGroup {
            JarvisMacCockpitView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .task { await store.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 800)

        Settings {
            JarvisMacSettingsView(store: store)
        }
    }
}
