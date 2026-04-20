import XCTest
@testable import JarvisCore

/// SPEC-009: presence events carry a server-presumed principal that rides
/// through the evidence corpus. Router-level emission is covered via
/// TelemetryPrincipalWitnessTests (which asserts logExecutionTrace
/// propagates the principal field into jsonl rows); here we lock down
/// the shared model's Codable contract and the backward-compat story.
final class PresenceEventRouterPrincipalTests: XCTestCase {

    func testPresenceEventCodableRoundTripsOperatorPrincipal() throws {
        let event = JarvisPresenceEvent(
            source: .homeKitGeofence,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z",
            presumedPrincipal: .operatorTier
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(JarvisPresenceEvent.self, from: data)
        XCTAssertEqual(decoded.presumedPrincipal, .operatorTier)
    }

    func testPresenceEventCodableRoundTripsCompanionMember() throws {
        let event = JarvisPresenceEvent(
            source: .iOSShortcut,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z",
            presumedPrincipal: .companion(memberID: "melissa")
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(JarvisPresenceEvent.self, from: data)
        XCTAssertEqual(decoded.presumedPrincipal, .companion(memberID: "melissa"))
    }

    func testPresumedPrincipalDefaultsToNilForBareSensor() {
        // CSI can detect a body without knowing whose body. Event model
        // must allow absence — the evidence corpus must not forge identity.
        let event = JarvisPresenceEvent(
            source: .wifiCSI,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z"
        )
        XCTAssertNil(event.presumedPrincipal)
    }

    func testLegacyPresenceJSONWithoutPrincipalDecodesCleanly() throws {
        // Backward compatibility: pre-SPEC-009 webhooks / stored events
        // don't carry presumedPrincipal. They must still decode.
        let legacy = """
        {
          "id": "legacy-1",
          "source": "wifi-csi",
          "kind": "arrival",
          "subject": "operator",
          "observedAtISO8601": "2026-04-20T13:45:00Z"
        }
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(JarvisPresenceEvent.self, from: data)
        XCTAssertNil(decoded.presumedPrincipal)
        XCTAssertEqual(decoded.source, .wifiCSI)
    }

    func testPresumedPrincipalTokenRoundTripThroughJSON() throws {
        // The on-disk / on-wire form of Principal is the tierToken string.
        // Guard against a future change that would break identities.json
        // and presence webhooks simultaneously.
        let event = JarvisPresenceEvent(
            source: .manual,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z",
            presumedPrincipal: .guestTier
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["presumedPrincipal"] as? String, "guest")
    }

    func testPresenceEventCodableRoundTripsResponderRole() throws {
        let event = JarvisPresenceEvent(
            source: .iOSShortcut,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z",
            presumedPrincipal: .responder(role: .emtp)
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(JarvisPresenceEvent.self, from: data)
        XCTAssertEqual(decoded.presumedPrincipal, .responder(role: .emtp))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["presumedPrincipal"] as? String, "responder:emtp")
    }

    func testPrincipalBrandSubtitleCoversAllTiers() {
        XCTAssertEqual(Principal.operatorTier.brandSubtitle, "powered by Grizz OS")
        XCTAssertEqual(Principal.companion(memberID: "melissa").brandSubtitle, "powered by Companion OS")
        XCTAssertEqual(Principal.guestTier.brandSubtitle, "powered by Companion OS (guest)")
        XCTAssertEqual(Principal.responder(role: .emt).brandSubtitle, "powered by Responder OS")
    }

    func testFromTierTokenAcceptsOperatorSynonymAndCaseWhitespace() {
        XCTAssertEqual(Principal.fromTierToken("operator"), .operatorTier)
        XCTAssertEqual(Principal.fromTierToken("GRIZZ"), .operatorTier)
        XCTAssertEqual(Principal.fromTierToken("  guest  "), .guestTier)
        XCTAssertEqual(Principal.fromTierToken("Companion:Melissa"), .companion(memberID: "melissa"))
        XCTAssertEqual(Principal.fromTierToken("RESPONDER:EMTP"), .responder(role: .emtp))
    }

    func testFromTierTokenRejectsMalformed() {
        XCTAssertNil(Principal.fromTierToken(""))
        XCTAssertNil(Principal.fromTierToken("admin"))
        XCTAssertNil(Principal.fromTierToken("companion:"), "empty companion id must fail")
        XCTAssertNil(Principal.fromTierToken("responder:"), "empty responder role must fail")
        XCTAssertNil(Principal.fromTierToken("responder:paramedic-2"), "unknown role must fail")
    }

    func testUnknownPrincipalTokenFailsEventDecode() {
        let bad = """
        {
          "id": "bad-1",
          "source": "manual",
          "kind": "arrival",
          "subject": "operator",
          "observedAtISO8601": "2026-04-20T13:45:00Z",
          "presumedPrincipal": "admin"
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(JarvisPresenceEvent.self, from: Data(bad.utf8)))
    }

    func testEventIDIsPreservedThroughRoundTrip() throws {
        let fixedID = "presence-2026-04-20-operator-arrival"
        let event = JarvisPresenceEvent(
            id: fixedID,
            source: .homeKitGeofence,
            kind: .arrival,
            observedAtISO8601: "2026-04-20T13:45:00Z",
            presumedPrincipal: .operatorTier
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(JarvisPresenceEvent.self, from: data)
        XCTAssertEqual(decoded.id, fixedID)
    }
}

