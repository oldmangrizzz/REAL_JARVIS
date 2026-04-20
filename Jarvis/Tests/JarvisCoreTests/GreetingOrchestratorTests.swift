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

    // MARK: - Additional coverage

    func test_afternoon_hour_uses_afternoon_word() {
        let line = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context(hour: 14).now, source: .manual)
        XCTAssertTrue(line.contains("afternoon"))
        XCTAssertFalse(line.contains("morning"))
        XCTAssertFalse(line.contains("evening"))
    }

    func test_cooldown_boundary_is_strict_less_than() {
        // cooldownSeconds = 300. 299 should suppress, 300 should pass.
        let justUnder = JarvisGreetingOrchestrator.plan(
            for: event(),
            context: context(timeSince: JarvisGreetingOrchestrator.cooldownSeconds - 1)
        )
        let exact = JarvisGreetingOrchestrator.plan(
            for: event(),
            context: context(timeSince: JarvisGreetingOrchestrator.cooldownSeconds)
        )
        XCTAssertTrue(justUnder.suppressed)
        XCTAssertFalse(exact.suppressed)
    }

    func test_csi_confidence_exactly_at_threshold_passes() {
        // Guard is `c < 0.6` (strict). 0.6 should pass.
        let plan = JarvisGreetingOrchestrator.plan(
            for: event(source: .wifiCSI, confidence: 0.6),
            context: context()
        )
        XCTAssertFalse(plan.suppressed)
        XCTAssertTrue(plan.line.contains("Wi-Fi CSI"))
    }

    func test_csi_with_nil_confidence_passes() {
        // No confidence reported → cannot suppress on low-confidence.
        let plan = JarvisGreetingOrchestrator.plan(
            for: event(source: .wifiCSI, confidence: nil),
            context: context()
        )
        XCTAssertFalse(plan.suppressed)
    }

    func test_source_tag_is_emitted_for_each_non_mock_source() {
        let homeKit = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context().now, source: .homeKitGeofence)
        let shortcut = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context().now, source: .iOSShortcut)
        let manual = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context().now, source: .manual)
        let csi = JarvisGreetingOrchestrator.greetingLine(operator: "Grizz", at: context().now, source: .wifiCSI)
        XCTAssertTrue(homeKit.contains("via HomeKit arrival"))
        XCTAssertTrue(shortcut.contains("via your Shortcut"))
        XCTAssertTrue(manual.contains("on manual cue"))
        XCTAssertTrue(csi.contains("via Wi-Fi CSI"))
    }

    func test_operator_label_is_never_hardcoded() {
        let ctx = JarvisGreetingContext(
            timeSinceLastGreeting: nil,
            now: context().now,
            operatorLabel: "Tony"
        )
        let plan = JarvisGreetingOrchestrator.plan(for: event(), context: ctx)
        XCTAssertFalse(plan.suppressed)
        XCTAssertTrue(plan.line.contains("Tony"), "line should address custom operator label: \(plan.line)")
        XCTAssertFalse(plan.line.contains("Grizz"))
    }

    func test_suppress_factory_invariants() {
        let sup = JarvisGreetingPlan.suppress("test-reason")
        XCTAssertTrue(sup.suppressed)
        XCTAssertEqual(sup.suppressionReason, "test-reason")
        XCTAssertEqual(sup.line, "")
        XCTAssertEqual(sup.surfaces, [])
    }

    func test_plan_is_equatable() {
        let a = JarvisGreetingOrchestrator.plan(for: event(), context: context())
        let b = JarvisGreetingOrchestrator.plan(for: event(), context: context())
        let differentCtx = JarvisGreetingOrchestrator.plan(for: event(), context: context(hour: 8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, differentCtx)
    }

    func test_presence_kind_presence_and_absence_are_both_suppressed() {
        let presence = JarvisGreetingOrchestrator.plan(for: event(kind: .presence), context: context())
        let absence = JarvisGreetingOrchestrator.plan(for: event(kind: .absence), context: context())
        XCTAssertTrue(presence.suppressed)
        XCTAssertEqual(presence.suppressionReason, "event-kind:presence")
        XCTAssertTrue(absence.suppressed)
        XCTAssertEqual(absence.suppressionReason, "event-kind:absence")
    }
}
