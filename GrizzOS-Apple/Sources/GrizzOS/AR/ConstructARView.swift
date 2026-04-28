import SwiftUI
import RealityKit
import ARKit

/// The AR View representing the GrizzOS Ambient Spatial Workspace.
/// Replicates the WebXR environment logic using ARKit and Custom Metal Materials.
public struct ConstructARView: UIViewRepresentable {

    public init() {}

    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Setup AR Configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.environment.sceneUnderstanding.options.insert(.physics)
            print("[SYS] RoomPlan LiDAR Mesh Loaded for Physics Occlusion.")
        }

        arView.session.run(config)

        // Create the Quantum Probability Cloud (Clifford Attractor)
        do {
            let library = try? MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
            let surfaceShader = library?.makeFunction(name: "quantum_attractor_surface")

            let customMaterial = try CustomMaterial(
                surfaceShader: CustomMaterial.SurfaceShader(named: "quantum_attractor_surface", in: library!),
                geometryModifier: nil,
                lightingModel: .unlit
            )

            // Generate latent token cluster
            let mesh = MeshResource.generateSphere(radius: 0.15)
            let entity = ModelEntity(mesh: mesh, materials: [customMaterial])

            // Set initial unobserved state (entanglement = 0.0)
            entity.model?.materials = [customMaterial]

            // Anchor it floating 1 meter in front of the user
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 1.5, -1.0))
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            // Enable interaction
            entity.generateCollisionShapes(recursive: true)
            arView.installGestures(.all, for: entity)

        } catch {
            print("[CRITICAL WOUND] Failed to compile Metal Shaders for Quantum Cloud: \(error)")
        }

        return arView
    }

    public func updateUIView(_ uiView: ARView, context: Context) {
        // Handle dynamic updates from SwiftUI state here
    }
}