import XCTest
@testable import JarvisCore

/// SPEC-008 destructive-intent guardrail. The guard's job is to refuse
/// to silence/power-down Jarvis faster than the operator can reconsider.
/// Everything here is hermetic — no clock, no runtime, no network.
final class DestructiveIntentGuardTests: XCTestCase {

    private func parsed(_ intent: JarvisIntent) -> ParsedIntent {
        ParsedIntent(
            intent: intent,
            confidence: 1.0,
            rawTranscript: "ignored",
            timestamp: "2026-04-20T12:00:00Z"
        )
    }

    // MARK: - classify

    func testSystemQueryWithDestructiveFragmentClassifiesAsDestructive() {
        let guardrail = DestructiveIntentGuard()
        let result = guardrail.classify(
            intent: parsed(.systemQuery(query: "jarvis shutdown")),
            command: "ignored-transcript"
        )
        XCTAssertTrue(result.isDestructive)
        if case .destructive(let reason) = result {
            XCTAssertEqual(reason, "shutdown")
        } else { XCTFail("expected .destructive") }
    }

    func testClassifyIsCaseInsensitiveAndMatchesMultiWordFragments() {
        let guardrail = DestructiveIntentGuard()
        let a = guardrail.classify(intent: parsed(.systemQuery(query: "JARVIS GO QUIET NOW")), command: "")
        let b = guardrail.classify(intent: parsed(.systemQuery(query: "please Stop Listening")), command: "")
        XCTAssertTrue(a.isDestructive)
        XCTAssertTrue(b.isDestructive)
        if case .destructive(let r) = a { XCTAssertEqual(r, "go quiet") }
        if case .destructive(let r) = b { XCTAssertEqual(r, "stop listening") }
    }

    func testUnknownIntentFallsBackToRawCommand() {
        let guardrail = DestructiveIntentGuard()
        let result = guardrail.classify(
            intent: parsed(.unknown(rawTranscript: "mumble")),
            command: "hey jarvis, self destruct"
        )
        XCTAssertTrue(result.isDestructive)
        if case .destructive(let r) = result { XCTAssertEqual(r, "self destruct") }
    }

    func testDisplayActionIntentIsNeverDestructive() {
        let guardrail = DestructiveIntentGuard()
        // Even if the transcript contains a destructive fragment, a parsed
        // displayAction must pass through — it's revocable via the UI.
        let result = guardrail.classify(
            intent: parsed(.displayAction(target: "left-monitor", action: "display", parameters: [:])),
            command: "shutdown the left monitor"
        )
        XCTAssertFalse(result.isDestructive)
    }

    func testHomeKitAndSkillIntentsAreNeverDestructive() {
        let guardrail = DestructiveIntentGuard()
        let hk = guardrail.classify(
            intent: parsed(.homeKitControl(accessoryName: "kitchen-lights", characteristic: "on", value: "false")),
            command: "shutdown the kitchen lights"
        )
        let skill = guardrail.classify(
            intent: parsed(.skillInvocation(skillName: "wipe-memory", payload: [:])),
            command: "wipe memory now"
        )
        XCTAssertFalse(hk.isDestructive)
        XCTAssertFalse(skill.isDestructive, "skill auth runs through its own gate, not this one")
    }

    func testNonDestructiveSystemQueryPassesThrough() {
        let guardrail = DestructiveIntentGuard()
        let result = guardrail.classify(
            intent: parsed(.systemQuery(query: "what's the weather")),
            command: ""
        )
        XCTAssertFalse(result.isDestructive)
    }

    // MARK: - allow (token bucket)

    func testAllowRefusesAfterCapacityExhausted() {
        let guardrail = DestructiveIntentGuard(capacity: 2, window: 300)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(guardrail.allow(now: t0))
        XCTAssertTrue(guardrail.allow(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(guardrail.allow(now: t0.addingTimeInterval(2)),
                       "third call within the window must be refused")
    }

    func testAllowEvictsExpiredTokensOutsideWindow() {
        let guardrail = DestructiveIntentGuard(capacity: 1, window: 60)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(guardrail.allow(now: t0))
        XCTAssertFalse(guardrail.allow(now: t0.addingTimeInterval(30)))
        // After the window expires, older timestamps drop and a slot opens.
        XCTAssertTrue(guardrail.allow(now: t0.addingTimeInterval(61)))
    }

    func testConstructorClampsInvalidCapacityAndWindow() {
        let guardrail = DestructiveIntentGuard(capacity: 0, window: -5)
        XCTAssertGreaterThanOrEqual(guardrail.capacity, 1, "capacity must clamp up to at least 1")
        XCTAssertGreaterThan(guardrail.window, 0, "window must clamp to a positive value")
    }

    // MARK: - constants

    func testRefusalResponseIsStableSpokenCopy() {
        // Downstream telemetry + snapshot tests depend on this string.
        XCTAssertTrue(DestructiveIntentGuard.refusalResponse.contains("destructive"))
        XCTAssertTrue(DestructiveIntentGuard.refusalResponse.contains("wait"))
    }

    func testDestructiveFragmentsIncludeCanonicalSet() {
        let fragments = Set(DestructiveIntentGuard.destructiveFragments)
        // Canonical baseline. Adding new fragments is fine (additive),
        // removing any of these needs a deliberate SPEC review.
        XCTAssertTrue(fragments.contains("shutdown"))
        XCTAssertTrue(fragments.contains("go quiet"))
        XCTAssertTrue(fragments.contains("stop listening"))
        XCTAssertTrue(fragments.contains("wipe memory"))
        XCTAssertTrue(fragments.contains("factory reset"))
    }
}
