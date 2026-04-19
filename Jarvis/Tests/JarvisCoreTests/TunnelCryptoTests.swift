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
}