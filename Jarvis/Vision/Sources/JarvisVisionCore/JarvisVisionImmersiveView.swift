#if canImport(RealityKit) && os(visionOS)

import SwiftUI
import RealityKit
import Combine

/// Immersive view for VisionOS that renders the spatial HUD received from the host.
///
/// The view subscribes to ``JarvisTunnelClient`` for ``HostSnapshot/spatialHUD`` updates and
/// creates a ``ModelEntity`` for each ``JarvisSpatialHUDElement``.  Each entity displays a
/// text mesh, is positioned in 3‑D space, and is coloured using the GMRI palette supplied
/// by the element.
///
/// The implementation is wrapped in a compile‑time guard so the package builds on platforms
/// that do not have the VisionOS SDK.
public struct JarvisVisionImmersiveView: View {
    @StateObject private var client = JarvisTunnelClient.shared
    @State private var cancellable: AnyCancellable?
    @State private var hudElements: [JarvisSpatialHUDElement] = []

    public init() {}

    public var body: some View {
        ImmersiveSpace {
            // Render each HUD element as a text entity in the immersive space.
            ForEach(hudElements) { element in
                RealityKitEntityView(element: element)
            }
        }
        .onAppear {
            subscribe()
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }

    /// Subscribes to the tunnel client and updates ``hudElements`` whenever a new
    /// ``HostSnapshot`` containing a ``spatialHUD`` arrives.
    private func subscribe() {
        cancellable = client.hostSnapshotPublisher
            .compactMap { $0?.spatialHUD }
            .receive(on: DispatchQueue.main)
            .sink { hud in
                self.hudElements = hud.elements
            }
    }
}

/// Helper view that creates a ``ModelEntity`` representing a single HUD element.
///
/// The view is a ``UIViewRepresentable`` that hosts an ``ARView``.  The AR view contains a
/// single anchor with a child ``ModelEntity`` that displays the element's label as a
/// text mesh, positioned according to the element's 3‑D coordinates, and coloured using
/// the element's GMRI palette.
private struct RealityKitEntityView: UIViewRepresentable {
    let element: JarvisSpatialHUDElement

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Generate a text mesh for the element's label.
        let mesh = MeshResource.generateText(
            element.label,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )

        // Apply the GMRI colour from the element's palette.
        let material = SimpleMaterial(color: element.palette.gmriColor, isMetallic: false)

        // Create the entity and position it.
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3<Float>(element.position.x,
                                      element.position.y,
                                      element.position.z)

        // Anchor the entity in world space.
        let anchor = AnchorEntity(world: entity.position)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // No dynamic updates required – the parent view rebuilds when `hudElements` changes.
    }
}

#else
// MARK: - Stub implementation for non‑VisionOS platforms

import SwiftUI

/// Placeholder view used when VisionOS support is unavailable.
///
/// The stub allows the package to compile on macOS, iOS, tvOS, etc. without pulling in
/// RealityKit or VisionOS‑specific APIs.
public struct JarvisVisionImmersiveView: View {
    public init() {}

    public var body: some View {
        Text("Jarvis Vision Immersive View is unavailable on this platform.")
    }
}
#endif