import SwiftUI

@main
struct GrizzOSApp: SwiftUI.App {
    @StateObject private var telemetry = TelemetryManager()
    @StateObject private var voiceManager = VoiceManager()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ZStack {
                // The Base AR / LiDAR Layer
                ConstructARView()
                    .ignoresSafeArea()

                // The Tactical Wilderness FOB HUD
                HUDView(telemetry: telemetry, voiceManager: voiceManager)
            }
            .onAppear {
                print("[GrizzOS] Mark LXVIII Ambient Interface Online.")
            }
        }
    }
}
