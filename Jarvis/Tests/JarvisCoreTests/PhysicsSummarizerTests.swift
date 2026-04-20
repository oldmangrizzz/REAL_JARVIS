import XCTest
@testable import JarvisCore

final class PhysicsSummarizerTests: XCTestCase {
    private func body(
        _ label: String,
        pos: Vec3 = .zero,
        vel: Vec3 = .zero,
        id: UInt64 = 1
    ) -> BodyState {
        BodyState(
            handle: BodyHandle(id: id),
            label: label,
            transform: Transform(position: pos),
            linearVelocity: vel,
            angularVelocity: .zero,
            isSleeping: false
        )
    }

    private func report(t: Double, contacts: Int) -> StepReport {
        let handle = BodyHandle(id: 0)
        let c = ContactSummary(bodyA: handle, bodyB: handle, point: .zero, normal: .zero, impulse: 1)
        return StepReport(
            simulatedTime: t,
            stepCount: 0,
            contacts: Array(repeating: c, count: contacts),
            wallClockSeconds: 0
        )
    }

    // MARK: - Constructor clamps

    func testConstructorClampsLowerBounds() {
        let s = PhysicsSummarizer(
            maxBodies: -5,
            movingSpeedThreshold: -1,
            positionPrecision: -2,
            speedPrecision: -3
        )
        XCTAssertEqual(s.maxBodies, 1, "maxBodies clamps to >= 1")
        XCTAssertEqual(s.movingSpeedThreshold, 0)
        XCTAssertEqual(s.positionPrecision, 0)
        XCTAssertEqual(s.speedPrecision, 0)
    }

    func testConstructorDefaults() {
        let s = PhysicsSummarizer()
        XCTAssertEqual(s.maxBodies, 8)
        XCTAssertEqual(s.movingSpeedThreshold, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s.positionPrecision, 2)
        XCTAssertEqual(s.speedPrecision, 2)
    }

    // MARK: - Empty / nil report

    func testEmptySnapshotNilReport() {
        let s = PhysicsSummarizer()
        let sum = s.summarize(snapshot: [], lastReport: nil)
        XCTAssertEqual(sum.bodyCount, 0)
        XCTAssertEqual(sum.movingCount, 0)
        XCTAssertEqual(sum.restingCount, 0)
        XCTAssertEqual(sum.recentContactCount, 0)
        XCTAssertEqual(sum.simulatedTime, 0)
        XCTAssertTrue(sum.text.contains("0 bodies"))
        XCTAssertTrue(sum.text.contains("t=0.000s"))
    }

    // MARK: - Moving vs resting threshold

    func testMovingVsRestingAtThreshold() {
        let s = PhysicsSummarizer(movingSpeedThreshold: 0.5)
        let moving = body("fast", vel: Vec3(0.5, 0, 0), id: 1)  // exactly threshold → moving (>=)
        let resting = body("slow", vel: Vec3(0.4, 0, 0), id: 2)
        let sum = s.summarize(snapshot: [moving, resting], lastReport: nil)
        XCTAssertEqual(sum.movingCount, 1)
        XCTAssertEqual(sum.restingCount, 1)
        XCTAssertTrue(sum.text.contains("fast"))
        XCTAssertTrue(sum.text.contains("slow"))
        XCTAssertTrue(sum.text.contains("moving"))
        XCTAssertTrue(sum.text.contains("at rest"))
    }

    // MARK: - maxBodies truncation

    func testTruncatesPastMaxBodiesWithOmissionMarker() {
        let s = PhysicsSummarizer(maxBodies: 2)
        let bs: [BodyState] = (0..<5).map { body("b\($0)", id: UInt64($0)) }
        let sum = s.summarize(snapshot: bs, lastReport: nil)
        XCTAssertEqual(sum.bodyCount, 5)
        XCTAssertTrue(sum.text.contains("(3 more bodies omitted)"))
        XCTAssertTrue(sum.text.contains("b0"))
        XCTAssertTrue(sum.text.contains("b1"))
        XCTAssertFalse(sum.text.contains("- b2 at "))  // truncated (use prefix to avoid matching "(3 more" line)
    }

    func testNoOmissionMarkerWhenWithinCap() {
        let s = PhysicsSummarizer(maxBodies: 8)
        let bs = [body("solo")]
        let sum = s.summarize(snapshot: bs, lastReport: nil)
        XCTAssertFalse(sum.text.contains("omitted"))
    }

    // MARK: - Precision formatting

    func testPositionAndSpeedPrecision() {
        let s = PhysicsSummarizer(positionPrecision: 1, speedPrecision: 3)
        let b = body("p", pos: Vec3(1.23456, 2.0, 3.0), vel: Vec3(0.123456, 0, 0))
        let sum = s.summarize(snapshot: [b], lastReport: nil)
        // position precision 1: "1.2"
        XCTAssertTrue(sum.text.contains("(1.2/2.0/3.0)"), "got: \(sum.text)")
        // speed precision 3: "0.123"
        XCTAssertTrue(sum.text.contains("speed 0.123m/s"), "got: \(sum.text)")
    }

    // MARK: - Contacts + simulated time wiring

    func testContactsAndSimulatedTimeFromReport() {
        let s = PhysicsSummarizer()
        let sum = s.summarize(snapshot: [body("x")], lastReport: report(t: 1.5, contacts: 4))
        XCTAssertEqual(sum.recentContactCount, 4)
        XCTAssertEqual(sum.simulatedTime, 1.5, accuracy: 1e-9)
        XCTAssertTrue(sum.text.contains("4 recent contacts"))
        XCTAssertTrue(sum.text.contains("t=1.500s"))
    }

    // MARK: - Summary struct arithmetic invariant

    func testRestingPlusMovingEqualsTotal() {
        let s = PhysicsSummarizer(movingSpeedThreshold: 0.1)
        let bs = [
            body("a", vel: Vec3(1, 0, 0), id: 1),
            body("b", vel: Vec3(0.05, 0, 0), id: 2),
            body("c", vel: .zero, id: 3)
        ]
        let sum = s.summarize(snapshot: bs, lastReport: nil)
        XCTAssertEqual(sum.movingCount + sum.restingCount, sum.bodyCount)
        XCTAssertEqual(sum.movingCount, 1)
        XCTAssertEqual(sum.restingCount, 2)
    }

    // MARK: - Additional coverage

    func testMaxBodiesOneShowsSingleBodyAndOmitsRest() {
        let s = PhysicsSummarizer(maxBodies: 1)
        let bs: [BodyState] = (0..<3).map { body("b\($0)", id: UInt64($0)) }
        let sum = s.summarize(snapshot: bs, lastReport: nil)
        XCTAssertEqual(sum.bodyCount, 3)
        XCTAssertTrue(sum.text.contains("- b0 at "), "first body must appear: \(sum.text)")
        XCTAssertFalse(sum.text.contains("- b1 at "))
        XCTAssertTrue(sum.text.contains("(2 more bodies omitted)"))
    }

    func testNegativeVelocityComponentsContributeToMagnitude() {
        // Velocity magnitude must be computed via length(), so a body with purely
        // negative components still counts as moving when |v| >= threshold.
        let s = PhysicsSummarizer(movingSpeedThreshold: 0.1)
        let b = body("back", vel: Vec3(-0.3, 0, -0.4), id: 1) // |v| = 0.5
        let sum = s.summarize(snapshot: [b], lastReport: nil)
        XCTAssertEqual(sum.movingCount, 1)
        XCTAssertEqual(sum.restingCount, 0)
        XCTAssertTrue(sum.text.contains("speed 0.50m/s"))
        XCTAssertTrue(sum.text.contains("moving"))
    }

    func testHeaderIsFirstLineAndBodyLinesFollow() {
        let s = PhysicsSummarizer(maxBodies: 2)
        let bs = [body("a", id: 1), body("b", id: 2)]
        let sum = s.summarize(snapshot: bs, lastReport: nil)
        let lines = sum.text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Physics state at t="))
        XCTAssertTrue(lines[1].hasPrefix("- a at "))
        XCTAssertTrue(lines[2].hasPrefix("- b at "))
    }

    func testReportWithZeroContactsRendersLiteralZero() {
        let s = PhysicsSummarizer()
        let sum = s.summarize(snapshot: [body("x")], lastReport: report(t: 0.25, contacts: 0))
        XCTAssertEqual(sum.recentContactCount, 0)
        XCTAssertTrue(sum.text.contains("0 recent contacts"))
        XCTAssertTrue(sum.text.contains("t=0.250s"))
    }

    func testSingleContactIsNotGrammaticallyPluralised() {
        // Regression lock: the summarizer does not attempt plural/singular forms,
        // so "1 recent contacts" is the expected literal output.
        let s = PhysicsSummarizer()
        let sum = s.summarize(snapshot: [body("x")], lastReport: report(t: 1, contacts: 1))
        XCTAssertTrue(sum.text.contains("1 recent contacts"))
    }

    func testPhysicsSummaryEquatable() {
        let a = PhysicsSummary(text: "hello", simulatedTime: 1, bodyCount: 2,
                               restingCount: 1, movingCount: 1, recentContactCount: 3)
        let b = PhysicsSummary(text: "hello", simulatedTime: 1, bodyCount: 2,
                               restingCount: 1, movingCount: 1, recentContactCount: 3)
        let c = PhysicsSummary(text: "hello", simulatedTime: 1, bodyCount: 2,
                               restingCount: 1, movingCount: 1, recentContactCount: 99)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testPhysicsSummaryCodableRoundTrip() throws {
        let original = PhysicsSummary(text: "line1\nline2", simulatedTime: 2.75,
                                      bodyCount: 4, restingCount: 1, movingCount: 3,
                                      recentContactCount: 2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhysicsSummary.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
