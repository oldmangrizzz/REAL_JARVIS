import SwiftUI
import JarvisMobileCore

@main
struct RealJarvisPhoneApp: App {
    @UIApplicationDelegateAdaptor(JarvisMobileAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: JarvisMobileCockpitStore

    init() {
        _store = StateObject(wrappedValue: JarvisMobileCockpitStore(role: .phone))
    }

    var body: some Scene {
        WindowGroup {
            JarvisCockpitView(store: store, layout: .phone)
                .task {
                    await store.start()
                    await MainActor.run {
                        JarvisMobileSystemHooks.shared.configure(store: store)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await store.start()
                }
            }
        }
    }
}
