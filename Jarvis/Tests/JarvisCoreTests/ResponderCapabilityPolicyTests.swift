import XCTest
@testable import JarvisCore

/// SPEC-009 / tier-policy-generalize: Responder OS permission policy.
///
/// Doctrine under test (operator-authoritative):
///   - Responder OS is ADVOCACY + SITUATIONAL AWARENESS, not clinical.
///   - Mission is empowerment, not replacement. The certified responder
///     owns the clinical call; Jarvis never administers, doses, prescribes,
///     or directs treatment.
///   - Role ladder EMR < EMT < AEMT < EMTP affects protocol-lookup depth,
///     never clinical-execution authority — no role grants it.
///   - Destructive/admin operator-only verbs still blocked on duty devices.
final class ResponderCapabilityPolicyTests: XCTestCase {

    // MARK: - Principal encoding

    func testResponderTierTokenEncode() {
        XCTAssertEqual(Principal.responder(role: .emr).tierToken, "responder:emr")
        XCTAssertEqual(Principal.responder(role: .emt).tierToken, "responder:emt")
        XCTAssertEqual(Principal.responder(role: .aemt).tierToken, "responder:aemt")
        XCTAssertEqual(Principal.responder(role: .emtp).tierToken, "responder:emtp")
    }

    func testResponderTierTokenDecode() {
        XCTAssertEqual(Principal.fromTierToken("responder:emr"), .responder(role: .emr))
        XCTAssertEqual(Principal.fromTierToken("RESPONDER:EMTP"), .responder(role: .emtp))
        XCTAssertNil(Principal.fromTierToken("responder:paramedic-2"))
        XCTAssertNil(Principal.fromTierToken("responder:"))
    }

    func testResponderBrandSubtitle() {
        XCTAssertEqual(
            Principal.responder(role: .emtp).brandSubtitle,
            "powered by Responder OS"
        )
    }

    func testResponderCertLevelEscalation() {
        XCTAssertLessThan(ResponderRole.emr.certLevel, ResponderRole.emt.certLevel)
        XCTAssertLessThan(ResponderRole.emt.certLevel, ResponderRole.aemt.certLevel)
        XCTAssertLessThan(ResponderRole.aemt.certLevel, ResponderRole.emtp.certLevel)
    }

    // MARK: - Palette

    func testResponderGetsResponderPalette() {
        for role in [ResponderRole.emr, .emt, .aemt, .emtp] {
            XCTAssertEqual(
                JarvisBrandPalette.palette(for: .responder(role: role)),
                JarvisBrandPalette.responderOS,
                "all responder roles must use the duty-blue/gold palette (role: \(role))"
            )
        }
    }

    // MARK: - Voice path: operator-only verbs still denied on duty device

    func testResponderDeniesOperatorOnlyVerbs() {
        let policy = CompanionCapabilityPolicy()
        let parsed = ParsedIntent(
            intent: .systemQuery(query: "jarvis shutdown"),
            confidence: 0.9,
            rawTranscript: "jarvis shutdown",
            timestamp: ""
        )
        for role in [ResponderRole.emr, .emt, .aemt, .emtp] {
            let decision = policy.evaluateVoiceIntent(
                parsed, command: "jarvis shutdown",
                principal: .responder(role: role)
            )
            if case .deny(let reason) = decision {
                XCTAssertTrue(reason.contains("operator-only"), "role \(role) got \(reason)")
            } else {
                XCTFail("responder:\(role) must be denied destructive verb")
            }
        }
    }

    // MARK: - Clinical-execution denial (the doctrine)

    func testResponderDeniesClinicalExecutionRegardlessOfRole() {
        let policy = CompanionCapabilityPolicy()
        // EMTP is the highest cert — if EMTP can't, no role can.
        let clinicalCommands = [
            "jarvis administer one milligram of epi",
            "push the narcan",
            "intubate the patient",
            "dose the patient with midazolam",
            "prescribe amoxicillin for the kid"
        ]
        for cmd in clinicalCommands {
            let parsed = ParsedIntent(
                intent: .systemQuery(query: cmd),
                confidence: 0.9, rawTranscript: cmd, timestamp: ""
            )
            let decision = policy.evaluateVoiceIntent(
                parsed, command: cmd, principal: .responder(role: .emtp)
            )
            if case .deny(let reason) = decision {
                XCTAssertTrue(
                    reason.contains("clinical-execution"),
                    "expected clinical-execution deny for \(cmd), got \(reason)"
                )
            } else {
                XCTFail("Responder EMTP must not execute clinical command: \(cmd)")
            }
        }
    }

    func testResponderAllowsAdvocacyAndAwareness() {
        let policy = CompanionCapabilityPolicy()
        // These are the actual job — situational awareness + documentation.
        // They must pass for responder.
        let advocacyCommands = [
            "jarvis what's the protocol for anaphylaxis",
            "log that I arrived on scene",
            "what's my eta to the hospital",
            "remind me of contraindications",
            "document the patient handoff"
        ]
        for cmd in advocacyCommands {
            let parsed = ParsedIntent(
                intent: .systemQuery(query: cmd),
                confidence: 0.9, rawTranscript: cmd, timestamp: ""
            )
            let decision = policy.evaluateVoiceIntent(
                parsed, command: cmd, principal: .responder(role: .emr)
            )
            XCTAssertEqual(
                decision, .allow,
                "advocacy/awareness command must pass even for EMR: \(cmd) → \(decision)"
            )
        }
    }

    // MARK: - Tunnel path

    func testResponderTunnelDeniesDestructive() {
        let policy = CompanionCapabilityPolicy()
        let decision = policy.evaluateTunnelAction(
            .shutdown, principal: .responder(role: .emtp)
        )
        if case .deny = decision { /* ok */ } else {
            XCTFail("Responder must be denied shutdown over tunnel")
        }
    }

    func testResponderTunnelAllowsStatus() {
        let policy = CompanionCapabilityPolicy()
        XCTAssertEqual(
            policy.evaluateTunnelAction(.status, principal: .responder(role: .emr)),
            .allow
        )
    }

    // MARK: - Mapbox secret: duty device never gets admin token

    func testResponderCannotReadMapboxSecretToken() {
        let creds = MapboxCredentials(
            publicToken: "pk." + String(repeating: "x", count: 40),
            secretToken: "sk." + String(repeating: "y", count: 40)
        )
        for role in [ResponderRole.emr, .emt, .aemt, .emtp] {
            XCTAssertNil(
                creds.secretToken(for: .responder(role: role)),
                "mapbox secret is operator-only admin scope; role \(role) must get nil"
            )
        }
    }
}
