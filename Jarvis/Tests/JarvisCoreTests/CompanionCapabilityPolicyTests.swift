import XCTest
@testable import JarvisCore

/// SPEC-009: Companion OS tier permission policy.
///
/// These tests lock down the family-tier permission gate at both the
/// voice-router boundary and the tunnel-command boundary. A regression
/// here lets a family member (or an unknown speaker) run operator-only
/// verbs, which is a trust-boundary violation.
final class CompanionCapabilityPolicyTests: XCTestCase {

    // MARK: - Voice path

    func testOperatorTierAllowsDestructiveIntent() {
        let policy = CompanionCapabilityPolicy()
        let parsed = ParsedIntent(
            intent: .systemQuery(query: "jarvis shutdown"),
            confidence: 0.9,
            rawTranscript: "jarvis shutdown",
            timestamp: ""
        )
        let decision = policy.evaluateVoiceIntent(parsed, command: "jarvis shutdown", principal: .operatorTier)
        XCTAssertEqual(decision, .allow)
    }

    func testCompanionTierDeniesDestructiveIntent() {
        let policy = CompanionCapabilityPolicy()
        let parsed = ParsedIntent(
            intent: .systemQuery(query: "jarvis shutdown"),
            confidence: 0.9,
            rawTranscript: "jarvis shutdown",
            timestamp: ""
        )
        let decision = policy.evaluateVoiceIntent(parsed, command: "jarvis shutdown", principal: .companion(memberID: "melissa"))
        if case .deny(let reason) = decision {
            XCTAssertTrue(reason.contains("operator-only"), "expected operator-only deny, got \(reason)")
        } else {
            XCTFail("Companion must be denied shutdown, got \(decision)")
        }
    }

    func testCompanionTierAllowsLightsAndStatus() {
        let policy = CompanionCapabilityPolicy()
        let lightsIntent = ParsedIntent(
            intent: .homeKitControl(accessoryName: "kitchen lights", characteristic: "power", value: "on"),
            confidence: 0.9,
            rawTranscript: "jarvis turn on the kitchen lights",
            timestamp: ""
        )
        XCTAssertEqual(
            policy.evaluateVoiceIntent(lightsIntent, command: "jarvis turn on the kitchen lights", principal: .companion(memberID: "melissa")),
            .allow
        )
        let statusIntent = ParsedIntent(
            intent: .systemQuery(query: "status"),
            confidence: 0.9,
            rawTranscript: "jarvis status",
            timestamp: ""
        )
        XCTAssertEqual(
            policy.evaluateVoiceIntent(statusIntent, command: "jarvis status", principal: .companion(memberID: "melissa")),
            .allow
        )
    }

    func testCompanionTierDeniesSelfHealAndReseed() {
        let policy = CompanionCapabilityPolicy()
        for phrase in ["jarvis self heal", "jarvis reseed the vault", "jarvis go quiet"] {
            let parsed = ParsedIntent(
                intent: .systemQuery(query: phrase),
                confidence: 0.9,
                rawTranscript: phrase,
                timestamp: ""
            )
            let decision = policy.evaluateVoiceIntent(parsed, command: phrase, principal: .companion(memberID: "melissa"))
            if case .deny = decision {
                // expected
            } else {
                XCTFail("Companion must be denied admin verb '\(phrase)'")
            }
        }
    }

    func testGuestTierAllowsStatusOnlyDeniesCommandVerbs() {
        let policy = CompanionCapabilityPolicy()
        let statusIntent = ParsedIntent(
            intent: .systemQuery(query: "status"),
            confidence: 0.9,
            rawTranscript: "jarvis status",
            timestamp: ""
        )
        XCTAssertEqual(
            policy.evaluateVoiceIntent(statusIntent, command: "jarvis status", principal: .guestTier),
            .allow
        )

        let controlIntent = ParsedIntent(
            intent: .homeKitControl(accessoryName: "lights", characteristic: "power", value: "on"),
            confidence: 0.9,
            rawTranscript: "jarvis turn on the lights",
            timestamp: ""
        )
        let decision = policy.evaluateVoiceIntent(controlIntent, command: "jarvis turn on the lights", principal: .guestTier)
        if case .deny(let reason) = decision {
            XCTAssertTrue(reason.contains("guest"), "expected guest-tier deny, got \(reason)")
        } else {
            XCTFail("Guest must be denied HomeKit control")
        }
    }

    // MARK: - Tunnel path

    func testTunnelOperatorMayInvokeEverything() {
        let policy = CompanionCapabilityPolicy()
        for action in JarvisRemoteAction.allCases {
            XCTAssertEqual(
                policy.evaluateTunnelAction(action, principal: .operatorTier),
                .allow,
                "operator must be allowed \(action.rawValue)"
            )
        }
    }

    func testTunnelCompanionDeniedDestructiveAndSkills() {
        let policy = CompanionCapabilityPolicy()
        let denied: [JarvisRemoteAction] = [.selfHeal, .reseedObsidian, .shutdown, .runSkill]
        for action in denied {
            let decision = policy.evaluateTunnelAction(action, principal: .companion(memberID: "melissa"))
            if case .allow = decision {
                XCTFail("companion must be denied \(action.rawValue)")
            }
        }
        let allowed: [JarvisRemoteAction] = [.status, .ping, .homeKitStatus, .listSkills, .presenceArrival]
        for action in allowed {
            XCTAssertEqual(
                policy.evaluateTunnelAction(action, principal: .companion(memberID: "melissa")),
                .allow,
                "companion must be allowed \(action.rawValue)"
            )
        }
    }

    func testTunnelGuestAllowsOnlyStatusAndPing() {
        let policy = CompanionCapabilityPolicy()
        XCTAssertEqual(policy.evaluateTunnelAction(.status, principal: .guestTier), .allow)
        XCTAssertEqual(policy.evaluateTunnelAction(.ping, principal: .guestTier), .allow)
        for action in JarvisRemoteAction.allCases where action != .status && action != .ping {
            let decision = policy.evaluateTunnelAction(action, principal: .guestTier)
            if case .allow = decision {
                XCTFail("guest must be denied \(action.rawValue)")
            }
        }
    }

    // MARK: - Brand palette (tier-ui)

    func testPaletteMapsPrincipalToCorrectTier() {
        XCTAssertEqual(JarvisBrandPalette.palette(for: .operatorTier).tierLabel, "powered by Grizz OS")
        XCTAssertEqual(JarvisBrandPalette.palette(for: .companion(memberID: "melissa")).tierLabel, "powered by Companion OS")
        XCTAssertEqual(JarvisBrandPalette.palette(for: .guestTier).tierLabel, "powered by Companion OS (guest)")
    }

    func testPaletteEmeraldVsTealIsDistinct() {
        XCTAssertNotEqual(
            JarvisBrandPalette.grizzOS.accentHex,
            JarvisBrandPalette.companionOS.accentHex,
            "tier accent must differ so family can tell tiers apart at a glance"
        )
        XCTAssertEqual(
            JarvisBrandPalette.grizzOS.alertCrimsonHex,
            JarvisBrandPalette.companionOS.alertCrimsonHex,
            "crimson alert must stay identical across tiers so safety signals read the same"
        )
    }
}
