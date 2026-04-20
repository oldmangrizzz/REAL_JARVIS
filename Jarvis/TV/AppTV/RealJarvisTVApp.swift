import SwiftUI
import JarvisTVCore

@main
struct RealJarvisTVApp: App {
    @StateObject private var store = JarvisTVCockpitStore()

    var body: some Scene {
        WindowGroup {
            JarvisTVCockpitView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}
