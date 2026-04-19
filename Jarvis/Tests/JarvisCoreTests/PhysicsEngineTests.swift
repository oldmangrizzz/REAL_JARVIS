import XCTest
@testable import JarvisCore

final class PhysicsEngineTests: XCTestCase {

    // MARK: - Stub backend: contract

    func testBackendName() {
        let engine = StubPhysicsEngine()
        XCTAssertEqual(engine.backendName, "stub")
    }

    func testResetRejectsBadConfig() {
        let engine = StubPhysicsEngine()
        XCTAssertThrowsError(try engine.reset(world: WorldDescriptor(fixedTimestep: 0))) { err in
            guard case PhysicsError.invalidConfiguration = err else {
                return XCTFail("expected invalidConfiguration, got \(err)")
            }
        }
        XCTAssertThrowsError(try engine.reset(world: WorldDescriptor(solverIterations: 0))) { err in
            guard case PhysicsError.invalidConfiguration = err else {
                return XCTFail("expected invalidConfiguration, got \(err)")
            }
        }
    }

    func testAddRequiresMassForDynamic() {
        let engine = StubPhysicsEngine()
        let bad = BodyDescriptor(label: "ghost", shape: Shape(kind: .sphere, extents: Vec3(0.5, 0, 0)), mass: 0, isStatic: false)
        XCTAssertThrowsError(try engine.addBody(bad))
    }

    func testHandleUniqueness() throws {
        let engine = StubPhysicsEngine()
        let a = try engine.addBody(BodyDescriptor(label: "a", shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0))))
        let b = try engine.addBody(BodyDescriptor(label: "b", shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0))))
        XCTAssertNotEqual(a.id, b.id)
    }

    func testRemoveBody() throws {
        let engine = StubPhysicsEngine()
        let h = try engine.addBody(BodyDescriptor(label: "tmp", shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0))))
        try engine.removeBody(h)
        XCTAssertThrowsError(try engine.state(of: h))
    }

    // MARK: - Physics correctness

    func testGravityFreeFall() throws {
        // Drop a 1m-radius sphere from z=10. After 1s of free fall, expected:
        //   v = g*t = -9.80665 m/s
        //   z ≈ 10 + 0.5*g*t^2 = 10 - 4.903325 = 5.096675
        // Stub uses explicit Euler so there is small drift. Tolerate it.
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor())
        let h = try engine.addBody(BodyDescriptor(
            label: "ball",
            shape: Shape(kind: .sphere, extents: Vec3(1.0, 0, 0)),
            mass: 1.0,
            initialTransform: Transform(position: Vec3(0, 0, 10))
        ))
        _ = try engine.step(seconds: 1.0)
        let s = try engine.state(of: h)
        XCTAssertEqual(s.linearVelocity.z, -9.80665, accuracy: 0.05)
        XCTAssertEqual(s.transform.position.z, 5.096675, accuracy: 0.5)
    }

    func testStaticPlaneStopsFall() throws {
        // Place a +Z plane at z=0. Drop a sphere of radius 0.5 from z=5.
        // After 5s, sphere must be at rest above the plane (z >= 0.5).
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor())
        _ = try engine.addBody(BodyDescriptor(
            label: "ground",
            shape: Shape(kind: .plane, extents: Vec3(0, 0, 1)),
            mass: 0,
            isStatic: true,
            initialTransform: Transform(position: Vec3.zero)
        ))
        let ball = try engine.addBody(BodyDescriptor(
            label: "ball",
            shape: Shape(kind: .sphere, extents: Vec3(0.5, 0, 0)),
            mass: 1.0,
            initialTransform: Transform(position: Vec3(0, 0, 5))
        ))
        _ = try engine.step(seconds: 5.0)
        let s = try engine.state(of: ball)
        XCTAssertGreaterThanOrEqual(s.transform.position.z, 0.499 - 1e-6)
    }

    func testGroundContactReportsContact() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor())
        _ = try engine.addBody(BodyDescriptor(
            label: "ground",
            shape: Shape(kind: .plane, extents: Vec3(0, 0, 1)),
            mass: 0,
            isStatic: true
        ))
        _ = try engine.addBody(BodyDescriptor(
            label: "ball",
            shape: Shape(kind: .sphere, extents: Vec3(0.5, 0, 0)),
            mass: 1.0,
            initialTransform: Transform(position: Vec3(0, 0, 1.0))
        ))
        let report = try engine.step(seconds: 1.5)
        XCTAssertGreaterThan(report.contacts.count, 0)
    }

    func testImpulseChangesVelocity() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        let h = try engine.addBody(BodyDescriptor(
            label: "puck",
            shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0)),
            mass: 2.0
        ))
        try engine.applyImpulse(Vec3(10, 0, 0), to: h)
        let s = try engine.state(of: h)
        XCTAssertEqual(s.linearVelocity.x, 5.0, accuracy: 1e-9) // impulse/mass
    }

    func testStaticBodyIgnoresImpulse() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        let h = try engine.addBody(BodyDescriptor(
            label: "wall",
            shape: Shape(kind: .box, extents: Vec3(1, 1, 1)),
            mass: 0,
            isStatic: true
        ))
        try engine.applyImpulse(Vec3(1000, 0, 0), to: h)
        let s = try engine.state(of: h)
        XCTAssertEqual(s.linearVelocity.x, 0)
    }

    // MARK: - Raycast

    func testRaycastHitsSphere() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        _ = try engine.addBody(BodyDescriptor(
            label: "target",
            shape: Shape(kind: .sphere, extents: Vec3(1.0, 0, 0)),
            mass: 1.0,
            initialTransform: Transform(position: Vec3(5, 0, 0))
        ))
        let hit = try engine.raycast(origin: Vec3(0, 0, 0), direction: Vec3(1, 0, 0), maxDistance: 100)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.distance ?? -1, 4.0, accuracy: 1e-6)
    }

    func testRaycastMisses() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        _ = try engine.addBody(BodyDescriptor(
            label: "target",
            shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0)),
            mass: 1.0,
            initialTransform: Transform(position: Vec3(0, 100, 0))
        ))
        let hit = try engine.raycast(origin: Vec3(0, 0, 0), direction: Vec3(1, 0, 0), maxDistance: 10)
        XCTAssertNil(hit)
    }

    func testRaycastZeroDirectionRejected() {
        let engine = StubPhysicsEngine()
        XCTAssertThrowsError(try engine.raycast(origin: .zero, direction: .zero, maxDistance: 1))
    }

    // MARK: - Summarizer (Natural Language Barrier)

    func testSummarizerProducesBoundedText() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        for i in 0..<25 {
            _ = try engine.addBody(BodyDescriptor(
                label: "b\(i)",
                shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0)),
                mass: 1.0,
                initialTransform: Transform(position: Vec3(Double(i), 0, 0))
            ))
        }
        let report = try engine.step(seconds: 1.0 / 240.0)
        let snap = try engine.snapshot()
        let summarizer = PhysicsSummarizer(maxBodies: 8)
        let summary = summarizer.summarize(snapshot: snap, lastReport: report)

        XCTAssertEqual(summary.bodyCount, 25)
        XCTAssertTrue(summary.text.contains("25 bodies"))
        XCTAssertTrue(summary.text.contains("17 more bodies omitted"))
        // No raw arrays in summary.text — sanity check it's a String, not JSON of velocities.
        XCTAssertFalse(summary.text.contains("\"linearVelocity\""))
    }

    func testSummarizerFlagsMovingVsResting() throws {
        let engine = StubPhysicsEngine()
        try engine.reset(world: WorldDescriptor(gravity: Vec3.zero))
        let mover = try engine.addBody(BodyDescriptor(
            label: "mover",
            shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0)),
            mass: 1.0,
            initialLinearVelocity: Vec3(2, 0, 0)
        ))
        _ = try engine.addBody(BodyDescriptor(
            label: "rester",
            shape: Shape(kind: .sphere, extents: Vec3(0.1, 0, 0)),
            mass: 1.0
        ))
        _ = mover
        let report = try engine.step(seconds: 1.0 / 240.0)
        let snap = try engine.snapshot()
        let summary = PhysicsSummarizer().summarize(snapshot: snap, lastReport: report)
        XCTAssertEqual(summary.movingCount, 1)
        XCTAssertEqual(summary.restingCount, 1)
    }
}
