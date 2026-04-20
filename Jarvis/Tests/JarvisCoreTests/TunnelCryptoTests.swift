import XCTest
@testable import JarvisCore

final class TunnelCryptoTests: XCTestCase {

    // MARK: - Round-trip seal/open

    func testSealAndOpenRoundTripsForMessage() throws {
        let crypto = JarvisTunnelCrypto(sharedSecret: "test-secret-12345")

        let message = JarvisTunnelMessage(
            kind: .command,
            command: JarvisRemoteCommand(action: .ping, source: "terminal")
        )

        let sealed = try crypto.seal(message)
        let opened = try crypto.open(JarvisTunnelMessage.self, from: sealed)

        XCTAssertEqual(opened.kind, .command)
        XCTAssertEqual(opened.command?.action, .ping)
        XCTAssertEqual(opened.command?.source, "terminal")
    }

    func testSealAndOpenRoundTripsForRegistration() throws {
        let crypto = JarvisTunnelCrypto(sharedSecret: "shared-key-for-test")

        let registration = JarvisClientRegistration(
            deviceID: "device-001",
            deviceName: "Test iPhone",
            platform: "iOS",
            role: "terminal",
            appVersion: "1.0.0"
        )
        let message = JarvisTunnelMessage(kind: .register, registration: registration)

        let sealed = try crypto.seal(message)
        let opened = try crypto.open(JarvisTunnelMessage.self, from: sealed)

        XCTAssertEqual(opened.kind, .register)
        XCTAssertEqual(opened.registration?.deviceID, "device-001")
        XCTAssertEqual(opened.registration?.role, "terminal")
    }

    func testSealAndOpenRoundTripsForSnapshot() throws {
        let crypto = JarvisTunnelCrypto(sharedSecret: "snap-test-key")
        let message = JarvisTunnelMessage(kind: .heartbeat)

        let sealed = try crypto.seal(message)
        let opened = try crypto.open(JarvisTunnelMessage.self, from: sealed)

        XCTAssertEqual(opened.kind, .heartbeat)
    }

    // MARK: - Wrong key fails

    func testOpenWithWrongKeyFails() throws {
        let encryptCrypto = JarvisTunnelCrypto(sharedSecret: "correct-key")
        let decryptCrypto = JarvisTunnelCrypto(sharedSecret: "wrong-key")

        let message = JarvisTunnelMessage(kind: .command, command: JarvisRemoteCommand(action: .status))
        let sealed = try encryptCrypto.seal(message)

        XCTAssertThrowsError(try decryptCrypto.open(JarvisTunnelMessage.self, from: sealed))
    }

    // MARK: - Invalid payload fails

    func testOpenWithInvalidBase64Fails() {
        let crypto = JarvisTunnelCrypto(sharedSecret: "any-key")

        XCTAssertThrowsError(try crypto.open(JarvisTunnelMessage.self, from: "not-valid-base64!!!"))
    }

    func testOpenWithValidBase64ButGarbageFails() {
        let crypto = JarvisTunnelCrypto(sharedSecret: "any-key")

        // valid base64 but not a valid sealed box
        let garbage = Data("this is not a sealed box".utf8).base64EncodedString()
        XCTAssertThrowsError(try crypto.open(JarvisTunnelMessage.self, from: garbage))
    }

    // MARK: - Different secrets produce different ciphertexts

    func testDifferentSecretsProduceDifferentCiphertexts() throws {
        let crypto1 = JarvisTunnelCrypto(sharedSecret: "secret-alpha")
        let crypto2 = JarvisTunnelCrypto(sharedSecret: "secret-beta")

        let message = JarvisTunnelMessage(kind: .command, command: JarvisRemoteCommand(action: .ping))

        let sealed1 = try crypto1.seal(message)
        let sealed2 = try crypto2.seal(message)

        XCTAssertNotEqual(sealed1, sealed2)
    }

    // MARK: - Same secret same payload produces different ciphertexts (nonce)

    func testSameSecretSamePayloadProducesDifferentCiphertexts() throws {
        let crypto = JarvisTunnelCrypto(sharedSecret: "nonce-test-key")

        let message = JarvisTunnelMessage(kind: .command, command: JarvisRemoteCommand(action: .ping))

        let sealed1 = try crypto.seal(message)
        let sealed2 = try crypto.seal(message)

        // ChaChaPoly uses random nonces, so same plaintext should produce different ciphertexts
        XCTAssertNotEqual(sealed1, sealed2)

        // But both should decrypt correctly
        let opened1 = try crypto.open(JarvisTunnelMessage.self, from: sealed1)
        let opened2 = try crypto.open(JarvisTunnelMessage.self, from: sealed2)
        XCTAssertEqual(opened1.kind, opened2.kind)
        XCTAssertEqual(opened1.command?.action, opened2.command?.action)
    }

    // MARK: - Transport packet round trip

    func testTransportPacketRoundTrip() throws {
        let crypto = JarvisTunnelCrypto(sharedSecret: "transport-test-key")

        let message = JarvisTunnelMessage(
            kind: .response,
            response: JarvisTunnelResponse(
                action: .status,
                spokenText: "JARVIS online."
            )
        )
        let sealed = try crypto.seal(message)

        let packet = JarvisTransportPacket(
            origin: "jarvis-host",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            payload: sealed
        )

        let encoded = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(JarvisTransportPacket.self, from: encoded)

        XCTAssertEqual(decoded.origin, "jarvis-host")
        XCTAssertEqual(decoded.payload, sealed)

        let opened = try crypto.open(JarvisTunnelMessage.self, from: decoded.payload)
        XCTAssertEqual(opened.kind, .response)
        XCTAssertEqual(opened.response?.action, .status)
        XCTAssertEqual(opened.response?.spokenText, "JARVIS online.")
    }

    // MARK: - signRegistration: deterministic with fixed nonce

    func testSignRegistrationIsDeterministicWithFixedNonce() {
        let key = String(repeating: "ab", count: 32) // 32-byte hex
        let a = JarvisTunnelCrypto.signRegistration(
            deviceID: "device-xyz",
            role: "terminal",
            identityKeyHex: key,
            nonce: "2026-04-20T12:00:00Z"
        )
        let b = JarvisTunnelCrypto.signRegistration(
            deviceID: "device-xyz",
            role: "terminal",
            identityKeyHex: key,
            nonce: "2026-04-20T12:00:00Z"
        )
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(a?.nonce, "2026-04-20T12:00:00Z")
        XCTAssertEqual(a?.proof, b?.proof)
        // HMAC-SHA256 hex length is 64
        XCTAssertEqual(a?.proof.count, 64)
    }

    // MARK: - signRegistration: role is normalized case-insensitively

    func testSignRegistrationRoleIsCaseInsensitive() {
        let key = String(repeating: "cd", count: 32)
        let lower = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: key,
            nonce: "fixed-nonce"
        )
        let mixed = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "Terminal",
            identityKeyHex: key,
            nonce: "fixed-nonce"
        )
        let upper = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "TERMINAL",
            identityKeyHex: key,
            nonce: "fixed-nonce"
        )
        XCTAssertEqual(lower?.proof, mixed?.proof)
        XCTAssertEqual(lower?.proof, upper?.proof)
    }

    // MARK: - signRegistration: rejects invalid hex

    func testSignRegistrationRejectsInvalidHex() {
        // Odd length hex string
        XCTAssertNil(JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: "abc",
            nonce: "n"
        ))
        // Non-hex characters
        XCTAssertNil(JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: "zzzzzzzz",
            nonce: "n"
        ))
    }

    // MARK: - signRegistration: different deviceIDs produce different proofs

    func testSignRegistrationVariesByDeviceID() {
        let key = String(repeating: "ef", count: 32)
        let a = JarvisTunnelCrypto.signRegistration(
            deviceID: "device-A",
            role: "terminal",
            identityKeyHex: key,
            nonce: "same-nonce"
        )
        let b = JarvisTunnelCrypto.signRegistration(
            deviceID: "device-B",
            role: "terminal",
            identityKeyHex: key,
            nonce: "same-nonce"
        )
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a?.proof, b?.proof)
    }

    // MARK: - signRegistration: different nonces produce different proofs

    func testSignRegistrationVariesByNonce() {
        let key = String(repeating: "12", count: 32)
        let a = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: key,
            nonce: "nonce-alpha"
        )
        let b = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: key,
            nonce: "nonce-beta"
        )
        XCTAssertNotEqual(a?.proof, b?.proof)
    }

    // MARK: - signRegistration: auto-generated nonce is ISO-8601

    func testSignRegistrationAutoGeneratesISO8601Nonce() throws {
        let key = String(repeating: "34", count: 32)
        let result = JarvisTunnelCrypto.signRegistration(
            deviceID: "d1",
            role: "terminal",
            identityKeyHex: key
        )
        let nonce = try XCTUnwrap(result?.nonce)
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: nonce), "nonce \(nonce) should parse as ISO-8601")
    }

    // MARK: - Error descriptions are user-facing

    func testCryptoErrorDescriptionsAreNonEmpty() {
        let invalid = JarvisTunnelCryptoError.invalidPayload
        let sealing = JarvisTunnelCryptoError.sealingFailed
        XCTAssertEqual(invalid.errorDescription, "Tunnel payload is not valid base64.")
        XCTAssertEqual(sealing.errorDescription, "Unable to seal tunnel payload.")
    }

    // MARK: - Open throws typed invalidPayload for non-base64 input

    func testOpenThrowsInvalidPayloadErrorForNonBase64() {
        let crypto = JarvisTunnelCrypto(sharedSecret: "err-typed")
        XCTAssertThrowsError(try crypto.open(JarvisTunnelMessage.self, from: "!!!not-base64!!!")) { error in
            guard let typed = error as? JarvisTunnelCryptoError else {
                XCTFail("expected JarvisTunnelCryptoError, got \(error)")
                return
            }
            switch typed {
            case .invalidPayload:
                break
            case .sealingFailed:
                XCTFail("expected .invalidPayload, got .sealingFailed")
            }
        }
    }
}