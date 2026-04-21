import XCTest
@testable import JarvisCore

/// NAV-001 §11 tests: priority ordering, barge-in preemption, TTL drop.
///
/// Per cross-lane UPDATE: one test per priority level covering enqueue + TTL
/// drop is sufficient. Full preemption coverage lives in VOICE-002.
final class NavUtteranceTests: XCTestCase {

    // MARK: - Priority ordering

    func testPriorityOrdering() {
        // advisory < turnByTurn < hazard < emergency
        XCTAssertTrue(NavUtterancePriority.advisory < .turnByTurn)
        XCTAssertTrue(NavUtterancePriority.turnByTurn < .hazard)
        XCTAssertTrue(NavUtterancePriority.hazard < .emergency)
    }

    // MARK: - Enqueue + dequeue per priority

    func testAdvisoryEnqueueDequeue() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "Route recalculating",
            priority: .advisory,
            ttlSeconds: 30
        )
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .advisory)
        XCTAssertEqual(dequeued?.text, "Route recalculating")
        let remaining = await queue.count
        XCTAssertEqual(remaining, 0, "Queue should be empty after dequeue")
    }

    func testTurnByTurnEnqueueDequeue() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "In 200 meters, turn left",
            priority: .turnByTurn,
            ttlSeconds: 15
        )
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .turnByTurn)
        XCTAssertEqual(dequeued?.text, "In 200 meters, turn left")
    }

    func testHazardEnqueueDequeue() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "Accident ahead, slow down",
            priority: .hazard,
            ttlSeconds: 60
        )
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .hazard)
        XCTAssertEqual(dequeued?.text, "Accident ahead, slow down")
    }

    func testEmergencyEnqueueDequeue() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "MCI dispatch, nearest ER 2.3 km north",
            priority: .emergency,
            ttlSeconds: 120
        )
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .emergency)
        XCTAssertEqual(dequeued?.text, "MCI dispatch, nearest ER 2.3 km north")
    }

    // MARK: - Barge-in preemption

    func testHazardPreemptsAdvisoryAndTurnByTurn() async {
        let queue = NavUtteranceQueue()
        await queue.enqueue(NavUtterance(text: "Recalculating", priority: .advisory, ttlSeconds: 30))
        await queue.enqueue(NavUtterance(text: "Turn left in 100m", priority: .turnByTurn, ttlSeconds: 15))
        let c1 = await queue.count
        XCTAssertEqual(c1, 2)
        // Hazard clears advisory + turnByTurn from queue
        await queue.enqueue(NavUtterance(text: "Accident ahead", priority: .hazard, ttlSeconds: 60))
        let count = await queue.count
        XCTAssertEqual(count, 1, "Hazard should clear advisory and turnByTurn")
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .hazard)
    }

    func testEmergencyPreemptsAllPriorities() async {
        let queue = NavUtteranceQueue()
        await queue.enqueue(NavUtterance(text: "A", priority: .advisory, ttlSeconds: 30))
        await queue.enqueue(NavUtterance(text: "B", priority: .turnByTurn, ttlSeconds: 15))
        await queue.enqueue(NavUtterance(text: "C", priority: .hazard, ttlSeconds: 60))
        await queue.enqueue(NavUtterance(text: "Code 3", priority: .emergency, ttlSeconds: 120))
        let count = await queue.count
        XCTAssertEqual(count, 1, "Emergency should clear all lower-priority utterances")
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.priority, .emergency)
    }

    // MARK: - TTL drop

    func testTTLDropsExpiredUtterances() async {
        let queue = NavUtteranceQueue()
        // Enqueue with very short TTL (already expired)
        let expired = NavUtterance(
            text: "Old message",
            priority: .advisory,
            issuedAt: Date().addingTimeInterval(-1), // created 1 second ago
            ttlSeconds: 0.001
        )
        await queue.enqueue(expired)
        // Dequeue should skip the expired utterance
        let dequeued = await queue.dequeue()
        XCTAssertNil(dequeued, "Expired utterance should be silently dropped")
        let c0 = await queue.count
        XCTAssertEqual(c0, 0)
    }

    // MARK: - NavContextSnapshot

    func testNavContextSnapshotDefaults() {
        let snapshot = NavContextSnapshot()
        XCTAssertNil(snapshot.activeRouteID)
        XCTAssertNil(snapshot.currentStep)
        XCTAssertNil(snapshot.nextStep)
        XCTAssertNil(snapshot.etaSecondsRemaining)
        XCTAssertNil(snapshot.distanceMetersRemaining)
        XCTAssertEqual(snapshot.currentHazards.count, 0)
    }

    func testNavContextSnapshotFullConstruction() {
        let step = RouteStepSummary(
            distanceMeters: 450.0,
            bearing: 90.0,
            instruction: "Turn right onto Elm St"
        )
        let nextStep = RouteStepSummary(
            distanceMeters: 1200.0,
            bearing: 180.0,
            instruction: "Continue on Main St"
        )
        let snapshot = NavContextSnapshot(
            activeRouteID: "route-abc123",
            currentStep: step,
            nextStep: nextStep,
            etaSecondsRemaining: 600,
            distanceMetersRemaining: 8500.0,
            currentHazards: [],
            capturedAt: Date()
        )
        XCTAssertEqual(snapshot.activeRouteID, "route-abc123")
        XCTAssertEqual(snapshot.currentStep?.instruction, "Turn right onto Elm St")
        XCTAssertEqual(snapshot.nextStep?.instruction, "Continue on Main St")
        XCTAssertEqual(snapshot.etaSecondsRemaining, 600)
        XCTAssertEqual(snapshot.distanceMetersRemaining, 8500.0)
    }

    // MARK: - RouteStepSummary

    func testRouteStepSummaryCreation() {
        let step = RouteStepSummary(
            distanceMeters: 500.0,
            bearing: 270.0,
            instruction: "Turn left onto Oak Ave"
        )
        XCTAssertEqual(step.distanceMeters, 500.0)
        XCTAssertEqual(step.bearing, 270.0)
        XCTAssertEqual(step.instruction, "Turn left onto Oak Ave")
    }

    // MARK: - NavUtterance field alignment with §11.1

    func testNavUtteranceRouteStepID() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "Turn left in 500 feet",
            priority: .turnByTurn,
            routeStepID: "edge-42",
            ttlSeconds: 15
        )
        XCTAssertEqual(utterance.routeStepID, "edge-42")
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertEqual(dequeued?.routeStepID, "edge-42")
    }

    func testNavUtteranceNilRouteStepIDForHazard() async {
        let queue = NavUtteranceQueue()
        let utterance = NavUtterance(
            text: "Debris ahead, slow down",
            priority: .hazard,
            ttlSeconds: 60
        )
        XCTAssertNil(utterance.routeStepID, "Hazard utterances should have nil routeStepID")
        await queue.enqueue(utterance)
        let dequeued = await queue.dequeue()
        XCTAssertNil(dequeued?.routeStepID)
    }

    // MARK: - NavUtterancePriority Codable round-trip

    func testPriorityCodableRoundTrip() throws {
        let priorities: [NavUtterancePriority] = [.advisory, .turnByTurn, .hazard, .emergency]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for priority in priorities {
            let data = try encoder.encode(priority)
            let decoded = try decoder.decode(NavUtterancePriority.self, from: data)
            XCTAssertEqual(decoded, priority)
        }
    }
}