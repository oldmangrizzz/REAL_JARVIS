import SwiftUI
import JarvisWatchCore

@main
struct RealJarvisWatchApp: App {
    @StateObject private var store: JarvisWatchCockpitStore

    init() {
        _store = StateObject(wrappedValue: JarvisWatchCockpitStore())
    }

    var body: some Scene {
        WindowGroup {
            JarvisWatchCockpitView(store: store)
                .task {
                    await store.start()
                }
        }
    }
}
