import XCTest
@testable import JarvisCore

final class GreetingOrchestratorTests: XCTestCase {
    private func event(source: JarvisPresenceSource = .homeKitGeofence, kind: JarvisPresenceKind = .arrival, confidence: Double? = nil) -> JarvisPresenceEvent {
        JarvisPresenceEvent(source: source, kind: kind, confidence: confidence, observedAtISO8601: "2026-04-20T18:00:00Z")
    }

    private func context(timeSince: TimeInterval? = nil, hour: Int = 18) -> JarvisGreetingContext {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 20; comps.hour = hour; comps.minute = 0
        let now = Calendar(identifier: .gregorian).date(from: comps)!
        return JarvisGreetingContext(timeSinceLastGreeting: timeSince, now: now, operatorLabel: "Grizz")
    }

    func test_arrival_plans_greeting_with_all_surfaces() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(), context: context())
        XCTAssertFalse(plan.suppressed)
        XCTAssertTrue(plan.line.contains("Grizz"))
        XCTAssertTrue(plan.line.contains("Welcome home"))
        XCTAssertTrue(plan.surfaces.contains(.hostAudio))
        XCTAssertTrue(plan.surfaces.contains(.homePodIntercom))
        XCTAssertTrue(plan.surfaces.contains(.appleTVLivingRoom))
        XCTAssertTrue(plan.surfaces.contains(.fireTV))
        XCTAssertTrue(plan.surfaces.contains(.echoShowKitchen))
    }

    func test_departure_is_suppressed() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(kind: .departure), context: context())
        XCTAssertTrue(plan.suppressed)
        XCTAssertEqual(plan.suppressionReason, "event-kind:departure")
    }

    func test_cooldown_suppresses_within_window() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(), context: context(timeSince: 60))
        XCTAssertTrue(plan.suppressed)
        XCTAssertTrue(plan.suppressionReason?.hasPrefix("cooldown:") ?? false)
    }

    func test_cooldown_passes_after_window() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(), context: context(timeSince: 600))
        XCTAssertFalse(plan.suppressed)
    }

    func test_mock_source_is_always_suppressed() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(source: .mock), context: context())
        XCTAssertTrue(plan.suppressed)
        XCTAssertEqual(plan.suppressionReason, "source:mock")
    }

    func test_low_confidence_csi_is_suppressed() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(source: .wifiCSI, confidence: 0.4), context: context())
        XCTAssertTrue(plan.suppressed)
        XCTAssertTrue(plan.suppressionReason?.hasPrefix("low-confidence:") ?? false)
    }

    func test_high_confidence_csi_passes_and_tags_source() {
        let plan = JarvisGreetingOrchestrator.plan(for: event(source: .wifiCSI, confidence: 0.9), context: context())
        XCTAssertFalse(plan.suppressed)
        XCTAssertTrue(plan.line.contains("Wi-Fi CSI"))
    }

    func test_time_of_day_varies() {
        let morning = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context(hour: 8).now, source: .homeKitGeofence)
        let evening = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context(hour: 19).now, source: .homeKitGeofence)
        let night = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context(hour: 2).now, source: .homeKitGeofence)
        XCTAssertTrue(morning.contains("morning"))
        XCTAssertTrue(evening.contains("evening"))
        XCTAssertTrue(night.contains("night"))
    }
}
