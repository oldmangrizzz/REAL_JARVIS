#if canImport(RealityKit) && os(visionOS)
import SwiftUI
import RealityKit

/// The main entry point for the VisionOS thin‑client target.
///
/// When the VisionOS SDK is available this app launches an
/// `ImmersiveSpace` that hosts ``JarvisVisionImmersiveView``.  A
/// fallback `WindowGroup` is provided for previewing on macOS or for
/// situations where the user launches the app outside of an immersive
/// session.  The fallback simply shows a title and an “Enter Immersive”
/// button (the button is a placeholder – the system UI is used to
/// actually enter the immersive space).
@main
struct RealJarvisVisionApp: App {
    var body: some Scene {
        // Regular window used for previews / non‑immersive launch.
        WindowGroup {
            VisionEntryView()
        }

        // VisionOS immersive space.  This scene is only compiled when the
        // RealityKit framework and the visionOS platform are available.
        ImmersiveSpace {
            JarvisVisionImmersiveView()
        }
    }
}

/// Simple placeholder UI shown when the app is launched in a normal
/// window.  The button does not perform any action – entering the
/// immersive space is handled by the system UI (e.g. the “Enter
/// Immersive” button that appears in the window’s title bar on
/// visionOS).
private struct VisionEntryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Jarvis Vision")
                .font(.title)
                .bold()
            Button("Enter Immersive") {
                // No‑op: the real immersive entry point is the ImmersiveSpace
                // defined above.  This button exists solely to give developers
                // a visible UI element when previewing on other platforms.
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
#else
// ---------------------------------------------------------------------------
// VisionOS SDK not available – provide a minimal stub so the project still
// builds on macOS, iOS, etc.
// ---------------------------------------------------------------------------

import SwiftUI

@main
struct RealJarvisVisionApp: App {
    var body: some Scene {
        WindowGroup {
            Text("VisionOS SDK not available.")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}
#endif