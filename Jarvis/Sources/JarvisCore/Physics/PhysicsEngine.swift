import Foundation

// MARK: - Physics Layer
//
// Local-first, language-free physics oracle for embodied reasoning.
//
// JARVIS does not "imagine" what happens when a thing is pushed. JARVIS
// asks the engine. The engine returns ground truth. Reasoning is checked
// against physics before it leaves the host.
//
// Architecture (locked):
//
//   Mac (host)              ←  truth-physics, JarvisCore consumer
//     └── PhysicsEngine     ← protocol defined here
//          └── MuJoCoBackend ← real backend, plugged in later
//
//   Renderers (cockpit / kiosks / Quest 3 / glasses)
//     └── Unity client      ← dumb renderer, OpenXR-portable
//          └── streams scene state from host over LAN
//
// This file defines the boundary. The boundary is what we test, what we
// gate, what we hash. Backends drop in behind it without consumers ever
// learning a new API.
//
// Natural Language Barrier rule (PRINCIPLES.md §6): physics state crossing
// into the LLM context window is summarized, never raw arrays. Raw arrays
// stay on the Swift side of the wall. Summaries cross. This protocol
// returns native Swift values; the summarizer (separate module) is what
// the LLM ever sees.

// MARK: - Vectors / Quaternions

public struct Vec3: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let up = Vec3(0, 0, 1)

    public func length() -> Double { (x*x + y*y + z*z).squareRoot() }
}

public struct Quat: Codable, Sendable, Equatable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w; self.x = x; self.y = y; self.z = z
    }

    public static let identity = Quat(w: 1, x: 0, y: 0, z: 0)
}

public struct Transform: Codable, Sendable, Equatable {
    public var position: Vec3
    public var orientation: Quat

    public init(position: Vec3 = .zero, orientation: Quat = .identity) {
        self.position = position
        self.orientation = orientation
    }
}

// MARK: - Bodies and Shapes

public enum ShapeKind: String, Codable, Sendable {
    case sphere
    case box
    case capsule
    case plane
    case mesh
}

public struct Shape: Codable, Sendable, Equatable {
    public let kind: ShapeKind
    /// Half-extents for box, radius/height for capsule/sphere, normal for plane.
    public let extents: Vec3
    /// Optional asset key when kind == .mesh; resolved by the backend.
    public let meshKey: String?

    public init(kind: ShapeKind, extents: Vec3 = .zero, meshKey: String? = nil) {
        self.kind = kind
        self.extents = extents
        self.meshKey = meshKey
    }
}

public struct BodyDescriptor: Codable, Sendable, Equatable {
    public let label: String
    public let shape: Shape
    public let mass: Double
    public let isStatic: Bool
    public let initialTransform: Transform
    public let initialLinearVelocity: Vec3
    public let initialAngularVelocity: Vec3

    public init(
        label: String,
        shape: Shape,
        mass: Double = 1.0,
        isStatic: Bool = false,
        initialTransform: Transform = Transform(),
        initialLinearVelocity: Vec3 = .zero,
        initialAngularVelocity: Vec3 = .zero
    ) {
        self.label = label
        self.shape = shape
        self.mass = mass
        self.isStatic = isStatic
        self.initialTransform = initialTransform
        self.initialLinearVelocity = initialLinearVelocity
        self.initialAngularVelocity = initialAngularVelocity
    }
}

public struct BodyHandle: Codable, Sendable, Equatable, Hashable {
    public let id: UInt64
    public init(id: UInt64) { self.id = id }
}

public struct BodyState: Codable, Sendable, Equatable {
    public let handle: BodyHandle
    public let label: String
    public let transform: Transform
    public let linearVelocity: Vec3
    public let angularVelocity: Vec3
    public let isSleeping: Bool
}

// MARK: - Queries

public struct RayHit: Codable, Sendable, Equatable {
    public let body: BodyHandle
    public let point: Vec3
    public let normal: Vec3
    public let distance: Double
}

public struct ContactSummary: Codable, Sendable, Equatable {
    public let bodyA: BodyHandle
    public let bodyB: BodyHandle
    public let point: Vec3
    public let normal: Vec3
    public let impulse: Double
}

public struct StepReport: Codable, Sendable, Equatable {
    public let simulatedTime: Double
    public let stepCount: UInt64
    public let contacts: [ContactSummary]
    /// Wall-clock elapsed for this step (for budget enforcement).
    public let wallClockSeconds: Double
}

public struct WorldDescriptor: Codable, Sendable, Equatable {
    public var gravity: Vec3
    public var fixedTimestep: Double
    public var solverIterations: Int

    public init(
        gravity: Vec3 = Vec3(0, 0, -9.80665),
        fixedTimestep: Double = 1.0 / 240.0,
        solverIterations: Int = 12
    ) {
        self.gravity = gravity
        self.fixedTimestep = fixedTimestep
        self.solverIterations = solverIterations
    }
}

// MARK: - Errors

public enum PhysicsError: Error, Sendable, Equatable {
    case backendUnavailable(String)
    case invalidBodyHandle(UInt64)
    case invalidConfiguration(String)
    case stepBudgetExceeded(budgetSeconds: Double, observedSeconds: Double)
    case backendInternal(String)
}

// MARK: - Engine Protocol
//
// Every backend (MuJoCo, Bullet, RealityKit shim, in-process stub) implements
// this. JarvisCore consumers depend on the protocol, never the backend.

public protocol PhysicsEngine: AnyObject, Sendable {
    /// Backend identifier ("mujoco", "stub", "bullet", "realitykit").
    var backendName: String { get }

    /// Reset world to a fresh state with the given configuration.
    func reset(world: WorldDescriptor) throws

    /// Add a body to the active world. Returns its handle.
    @discardableResult
    func addBody(_ body: BodyDescriptor) throws -> BodyHandle

    /// Remove a body from the active world.
    func removeBody(_ handle: BodyHandle) throws

    /// Snapshot a body's state.
    func state(of handle: BodyHandle) throws -> BodyState

    /// Snapshot all body states.
    func snapshot() throws -> [BodyState]

    /// Apply an instantaneous impulse at a body's center of mass.
    func applyImpulse(_ impulse: Vec3, to handle: BodyHandle) throws

    /// Step the simulation forward by `seconds` (multiple of fixedTimestep).
    func step(seconds: Double) throws -> StepReport

    /// Cast a ray and return the nearest hit, if any.
    func raycast(origin: Vec3, direction: Vec3, maxDistance: Double) throws -> RayHit?
}

// MARK: - Engine Capabilities

public struct PhysicsCapabilities: Codable, Sendable, Equatable {
    public let supportsContinuousCollision: Bool
    public let supportsArticulation: Bool
    public let supportsDifferentiable: Bool
    public let supportsMeshCollision: Bool
    public let isRealtime: Bool

    public init(
        supportsContinuousCollision: Bool,
        supportsArticulation: Bool,
        supportsDifferentiable: Bool,
        supportsMeshCollision: Bool,
        isRealtime: Bool
    ) {
        self.supportsContinuousCollision = supportsContinuousCollision
        self.supportsArticulation = supportsArticulation
        self.supportsDifferentiable = supportsDifferentiable
        self.supportsMeshCollision = supportsMeshCollision
        self.isRealtime = isRealtime
    }

    public static let stub = PhysicsCapabilities(
        supportsContinuousCollision: false,
        supportsArticulation: false,
        supportsDifferentiable: false,
        supportsMeshCollision: false,
        isRealtime: true
    )
}
