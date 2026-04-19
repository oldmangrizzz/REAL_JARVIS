import Foundation

// MARK: - Stub Physics Backend
//
// A real (not "TODO") in-process physics backend: explicit Euler integrator,
// gravity-correct, sphere/box AABB-vs-plane collision, restitution, friction.
//
// Purpose:
//   * Lets JarvisCore consumers depend on PhysicsEngine TODAY.
//   * Lets the Unity bridge be developed against a deterministic backend.
//   * Lets tests assert on real numbers (gravity = -9.80665, etc).
//   * Gets replaced by MuJoCoBackend (same protocol) without touching callers.
//
// What it is NOT:
//   * Not articulated.
//   * Not contact-rich (no body-vs-body collision in this revision).
//   * Not differentiable.
//   * Capabilities reported truthfully via `capabilities`.

public final class StubPhysicsEngine: PhysicsEngine, @unchecked Sendable {
    public let backendName: String = "stub"
    public let capabilities: PhysicsCapabilities = .stub

    private let lock = NSLock()
    private var world: WorldDescriptor
    private var nextID: UInt64 = 1
    private var bodies: [UInt64: Body] = [:]
    private var stepCounter: UInt64 = 0
    private var simulatedTime: Double = 0.0

    private struct Body {
        let descriptor: BodyDescriptor
        var transform: Transform
        var linearVelocity: Vec3
        var angularVelocity: Vec3
        var sleeping: Bool
    }

    public init(world: WorldDescriptor = WorldDescriptor()) {
        self.world = world
    }

    public func reset(world: WorldDescriptor) throws {
        lock.lock(); defer { lock.unlock() }
        guard world.fixedTimestep > 0 else {
            throw PhysicsError.invalidConfiguration("fixedTimestep must be > 0")
        }
        guard world.solverIterations >= 1 else {
            throw PhysicsError.invalidConfiguration("solverIterations must be >= 1")
        }
        self.world = world
        self.bodies.removeAll()
        self.nextID = 1
        self.stepCounter = 0
        self.simulatedTime = 0.0
    }

    @discardableResult
    public func addBody(_ body: BodyDescriptor) throws -> BodyHandle {
        lock.lock(); defer { lock.unlock() }
        guard (body.mass >= 1e-6 && body.mass.isFinite) || body.isStatic else {
            throw PhysicsError.invalidConfiguration("non-static body mass must be >= 1e-6 and finite (got \(body.mass))")
        }
        guard body.initialTransform.position.x.isFinite,
              body.initialTransform.position.y.isFinite,
              body.initialTransform.position.z.isFinite else {
            throw PhysicsError.invalidConfiguration("body position contains NaN or Infinity")
        }
        guard body.shape.extents.x.isFinite,
              body.shape.extents.y.isFinite,
              body.shape.extents.z.isFinite else {
            throw PhysicsError.invalidConfiguration("body shape extents contain NaN or Infinity")
        }
        switch body.shape.kind {
        case .sphere:
            guard body.shape.extents.x > 0 else {
                throw PhysicsError.invalidConfiguration("sphere radius must be positive")
            }
        case .box:
            guard body.shape.extents.x > 0,
                  body.shape.extents.y > 0,
                  body.shape.extents.z > 0 else {
                throw PhysicsError.invalidConfiguration("box half-extents must be positive")
            }
        case .plane:
            // A zero-extent plane would normalize to (0,0,1) silently — reject it.
            guard body.shape.extents.length() > 0 else {
                throw PhysicsError.invalidConfiguration("plane extents must be non-zero to define a normal")
            }
        case .capsule, .mesh:
            break
        }
        let id = nextID
        nextID &+= 1
        bodies[id] = Body(
            descriptor: body,
            transform: body.initialTransform,
            linearVelocity: body.initialLinearVelocity,
            angularVelocity: body.initialAngularVelocity,
            sleeping: false
        )
        return BodyHandle(id: id)
    }

    public func removeBody(_ handle: BodyHandle) throws {
        lock.lock(); defer { lock.unlock() }
        guard bodies.removeValue(forKey: handle.id) != nil else {
            throw PhysicsError.invalidBodyHandle(handle.id)
        }
    }

    public func state(of handle: BodyHandle) throws -> BodyState {
        lock.lock(); defer { lock.unlock() }
        guard let b = bodies[handle.id] else {
            throw PhysicsError.invalidBodyHandle(handle.id)
        }
        return BodyState(
            handle: handle,
            label: b.descriptor.label,
            transform: b.transform,
            linearVelocity: b.linearVelocity,
            angularVelocity: b.angularVelocity,
            isSleeping: b.sleeping
        )
    }

    public func snapshot() throws -> [BodyState] {
        lock.lock(); defer { lock.unlock() }
        return bodies.keys.sorted().map { id in
            let b = bodies[id]!
            return BodyState(
                handle: BodyHandle(id: id),
                label: b.descriptor.label,
                transform: b.transform,
                linearVelocity: b.linearVelocity,
                angularVelocity: b.angularVelocity,
                isSleeping: b.sleeping
            )
        }
    }

    public func applyImpulse(_ impulse: Vec3, to handle: BodyHandle) throws {
        lock.lock(); defer { lock.unlock() }
        guard var b = bodies[handle.id] else {
            throw PhysicsError.invalidBodyHandle(handle.id)
        }
        guard !b.descriptor.isStatic else { return }
        let m = b.descriptor.mass
        b.linearVelocity = Vec3(
            b.linearVelocity.x + impulse.x / m,
            b.linearVelocity.y + impulse.y / m,
            b.linearVelocity.z + impulse.z / m
        )
        b.sleeping = false
        bodies[handle.id] = b
    }

    public func step(seconds: Double) throws -> StepReport {
        lock.lock(); defer { lock.unlock() }
        guard seconds > 0 else {
            throw PhysicsError.invalidConfiguration("step seconds must be > 0")
        }
        let dt = world.fixedTimestep
        let n = Int((seconds / dt).rounded())
        guard n >= 1 else {
            throw PhysicsError.invalidConfiguration("step seconds shorter than fixedTimestep")
        }
        // CX-008: cap substeps to prevent hanging on huge time values
        let maxSubsteps = 10_000
        guard n <= maxSubsteps else {
            throw PhysicsError.invalidConfiguration("step(\(seconds)s) would require \(n) substeps, exceeding limit of \(maxSubsteps). Use smaller time steps.")
        }

        let wallStart = Date()
        var contacts: [ContactSummary] = []

        for _ in 0..<n {
            integrate(dt: dt)
            contacts.append(contentsOf: resolveGroundCollisions())
            stepCounter &+= 1
            simulatedTime += dt
        }

        let elapsed = Date().timeIntervalSince(wallStart)
        return StepReport(
            simulatedTime: simulatedTime,
            stepCount: stepCounter,
            contacts: contacts,
            wallClockSeconds: elapsed
        )
    }

    public func raycast(origin: Vec3, direction: Vec3, maxDistance: Double) throws -> RayHit? {
        lock.lock(); defer { lock.unlock() }
        let len = direction.length()
        guard len > 0 else {
            throw PhysicsError.invalidConfiguration("ray direction is zero vector")
        }
        let d = Vec3(direction.x / len, direction.y / len, direction.z / len)

        var best: RayHit?
        for (id, b) in bodies {
            guard let hit = raycastSphereLike(body: b, handle: BodyHandle(id: id), origin: origin, dir: d, maxDistance: maxDistance) else { continue }
            if let cur = best {
                if hit.distance < cur.distance { best = hit }
            } else {
                best = hit
            }
        }
        return best
    }

    // MARK: - Internals

    private func integrate(dt: Double) {
        let g = world.gravity
        for (id, var b) in bodies {
            if b.descriptor.isStatic { continue }
            // Linear: v += g*dt; x += v*dt
            b.linearVelocity = Vec3(
                b.linearVelocity.x + g.x * dt,
                b.linearVelocity.y + g.y * dt,
                b.linearVelocity.z + g.z * dt
            )
            b.transform.position = Vec3(
                b.transform.position.x + b.linearVelocity.x * dt,
                b.transform.position.y + b.linearVelocity.y * dt,
                b.transform.position.z + b.linearVelocity.z * dt
            )
            bodies[id] = b
        }
    }

    private func resolveGroundCollisions() -> [ContactSummary] {
        var contacts: [ContactSummary] = []
        // Find all static planes; resolve dynamic spheres/boxes against them.
        let planes = bodies.filter { $0.value.descriptor.shape.kind == .plane && $0.value.descriptor.isStatic }
        guard !planes.isEmpty else { return contacts }

        for (id, var b) in bodies {
            if b.descriptor.isStatic { continue }
            let kind = b.descriptor.shape.kind
            guard kind == .sphere || kind == .box || kind == .capsule else { continue }
            let radius = effectiveRadius(of: b.descriptor.shape)

            for (planeID, plane) in planes {
                let normal = normalize(plane.descriptor.shape.extents)
                let planePoint = plane.transform.position
                // Signed distance from body center to plane, along normal.
                let toCenter = Vec3(
                    b.transform.position.x - planePoint.x,
                    b.transform.position.y - planePoint.y,
                    b.transform.position.z - planePoint.z
                )
                let dist = dot(toCenter, normal) - radius
                if dist < 0 {
                    // Snap out of penetration.
                    b.transform.position = Vec3(
                        b.transform.position.x - normal.x * dist,
                        b.transform.position.y - normal.y * dist,
                        b.transform.position.z - normal.z * dist
                    )
                    // Reflect velocity component along normal with restitution.
                    let vn = dot(b.linearVelocity, normal)
                    if vn < 0 {
                        let restitution = 0.2
                        let friction = 0.4
                        // Remove normal component, apply restitution.
                        let normalComp = Vec3(normal.x * vn, normal.y * vn, normal.z * vn)
                        var tangential = Vec3(
                            b.linearVelocity.x - normalComp.x,
                            b.linearVelocity.y - normalComp.y,
                            b.linearVelocity.z - normalComp.z
                        )
                        tangential = Vec3(
                            tangential.x * (1 - friction),
                            tangential.y * (1 - friction),
                            tangential.z * (1 - friction)
                        )
                        let bounce = Vec3(
                            -normalComp.x * restitution,
                            -normalComp.y * restitution,
                            -normalComp.z * restitution
                        )
                        b.linearVelocity = Vec3(
                            tangential.x + bounce.x,
                            tangential.y + bounce.y,
                            tangential.z + bounce.z
                        )
                        let impulseMag = abs(vn) * b.descriptor.mass * (1 + restitution)
                        contacts.append(ContactSummary(
                            bodyA: BodyHandle(id: id),
                            bodyB: BodyHandle(id: planeID),
                            point: b.transform.position,
                            normal: normal,
                            impulse: impulseMag
                        ))
                    }
                }
            }
            bodies[id] = b
        }
        return contacts
    }

    private func raycastSphereLike(body: Body, handle: BodyHandle, origin: Vec3, dir: Vec3, maxDistance: Double) -> RayHit? {
        // Treat every shape as a bounding sphere for v0. Replaced by MuJoCo backend.
        let r = effectiveRadius(of: body.descriptor.shape)
        guard r > 0 else { return nil }
        let center = body.transform.position
        let oc = Vec3(origin.x - center.x, origin.y - center.y, origin.z - center.z)
        let b = dot(oc, dir)
        let c = dot(oc, oc) - r * r
        let disc = b * b - c
        if disc < 0 { return nil }
        let sqrtDisc = disc.squareRoot()
        let t = -b - sqrtDisc
        guard t >= 0, t <= maxDistance else { return nil }
        let point = Vec3(origin.x + dir.x * t, origin.y + dir.y * t, origin.z + dir.z * t)
        let nRaw = Vec3(point.x - center.x, point.y - center.y, point.z - center.z)
        let normal = normalize(nRaw)
        return RayHit(body: handle, point: point, normal: normal, distance: t)
    }

    private func effectiveRadius(of shape: Shape) -> Double {
        switch shape.kind {
        case .sphere: return shape.extents.x
        case .box, .capsule:
            return max(max(abs(shape.extents.x), abs(shape.extents.y)), abs(shape.extents.z))
        case .plane, .mesh:
            return 0
        }
    }

    private func dot(_ a: Vec3, _ b: Vec3) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private func normalize(_ v: Vec3) -> Vec3 {
        let l = v.length()
        guard l > 0 else { return Vec3(0, 0, 1) }
        return Vec3(v.x / l, v.y / l, v.z / l)
    }
}
