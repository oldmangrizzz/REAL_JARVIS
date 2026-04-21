import XCTest
import CryptoKit
@testable import JarvisCore

// MARK: - MK2-EPIC-02: TunnelRoleToken authorization tests

final class TunnelAuthTests: XCTestCase {

    private let sharedSecret = "mk2-epic-02-test-secret-alpha"
    private var crypto: JarvisTunnelCrypto { JarvisTunnelCrypto(sharedSecret: sharedSecret) }

    // MARK: - 1. Valid token passes

    func testValidTokenPassesVerification() {
        let c = crypto
        let token = c.signRoleToken(role: .mobileClient, clientPubKey: "aabbcc001122")
        XCTAssertTrue(c.verifyRoleToken(token), "A freshly signed token must verify successfully.")
        XCTAssertFalse(token.isExpired, "A freshly signed token must not be expired.")
    }

    // MARK: - 2. Missing token rejected

    func testMissingTokenThrowsMissingRoleToken() {
        let message = JarvisTunnelMessage(kind: .heartbeat, roleToken: nil)
        XCTAssertNil(message.roleToken, "Message without roleToken must have nil roleToken field.")
        // Simulates server logic: non-register frame missing roleToken → missingRoleToken
        XCTAssertThrowsError(try throwIfMissingToken(message)) { error in
            guard let te = error as? TunnelError, te == .missingRoleToken else {
                XCTFail("Expected TunnelError.missingRoleToken, got \(error)")
                return
            }
        }
    }

    // MARK: - 3. Wrong-role rejected

    func testWrongRoleInTokenRejected() {
        let c = crypto
        // Server assigns mobileClient, but token was signed as watchClient
        let token = c.signRoleToken(role: .watchClient, clientPubKey: "aabbcc001122")
        XCTAssertTrue(c.verifyRoleToken(token), "HMAC is valid")
        // Simulate server check: stored role = mobileClient, token role = watchClient
        let storedRole = TunnelRole.mobileClient
        XCTAssertNotEqual(token.role, storedRole, "Roles should differ to trigger mismatch")
        XCTAssertThrowsError(try throwIfRoleMismatch(token: token, storedRole: storedRole)) { error in
            guard let te = error as? TunnelError, te == .roleClaimMismatch else {
                XCTFail("Expected TunnelError.roleClaimMismatch, got \(error)")
                return
            }
        }
    }

    // MARK: - 4. Expired token rejected

    func testExpiredTokenRejected() {
        let c = crypto
        // Build a token with issuedAt and expiresAt in the past
        let past: Int64 = 1_000_000  // well in the past
        let message = "\(TunnelRole.mobileClient.rawValue)|\(past)|\(past + 28800)|testkey"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: SHA256.hash(data: Data(sharedSecret.utf8)))
        )
        let macHex = mac.map { String(format: "%02x", $0) }.joined()
        let expiredToken = TunnelRoleToken(
            role: .mobileClient,
            issuedAt: past,
            expiresAt: past + 28800,
            clientPubKey: "testkey",
            mac: macHex
        )
        XCTAssertTrue(expiredToken.isExpired, "Token with past expiresAt must be expired.")
        XCTAssertTrue(c.verifyRoleToken(expiredToken), "HMAC must still be valid on expired token")
        XCTAssertThrowsError(try throwIfExpired(expiredToken)) { error in
            guard let te = error as? TunnelError, te == .expiredToken else {
                XCTFail("Expected TunnelError.expiredToken, got \(error)")
                return
            }
        }
    }

    // MARK: - 5. Role demotion on secret rotation (old token fails)

    func testRoleDemotionAfterSecretRotation() {
        // Token issued with the old secret
        let oldCrypto = JarvisTunnelCrypto(sharedSecret: "old-secret-rotation-test")
        let token = oldCrypto.signRoleToken(role: .macHost, clientPubKey: "device-abc")

        // After rotation, server uses a new secret
        let newCrypto = JarvisTunnelCrypto(sharedSecret: "new-secret-rotation-test")
        XCTAssertFalse(
            newCrypto.verifyRoleToken(token),
            "Token signed with old key must fail verification with new key (role demotion on rotation)."
        )
    }

    // MARK: - 6. Tamper (flip one bit in MAC → reject)

    func testTamperedTokenMACRejected() {
        let c = crypto
        let token = c.signRoleToken(role: .mobileClient, clientPubKey: "aabbcc001122")
        XCTAssertTrue(c.verifyRoleToken(token), "Original token must verify")

        // Flip the first character of the MAC
        var tamperedMAC = token.mac
        let firstChar = tamperedMAC.removeFirst()
        let flipped: Character = firstChar == "a" ? "b" : "a"
        tamperedMAC.insert(flipped, at: tamperedMAC.startIndex)

        let tampered = TunnelRoleToken(
            role: token.role,
            issuedAt: token.issuedAt,
            expiresAt: token.expiresAt,
            clientPubKey: token.clientPubKey,
            mac: tamperedMAC
        )
        XCTAssertFalse(c.verifyRoleToken(tampered), "Tampered MAC must fail verification.")
    }

    // MARK: - Wire encoding round-trip

    func testRoleTokenWireRoundTrip() throws {
        let c = crypto
        let original = c.signRoleToken(role: .mobileClient, clientPubKey: "deadbeef1234")
        let wire = try original.wireString()
        XCTAssertFalse(wire.contains("="), "base64url must have no padding")
        let decoded = try TunnelRoleToken.from(wireString: wire)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.issuedAt, original.issuedAt)
        XCTAssertEqual(decoded.expiresAt, original.expiresAt)
        XCTAssertEqual(decoded.clientPubKey, original.clientPubKey)
        XCTAssertEqual(decoded.mac, original.mac)
    }

    // MARK: - TunnelRole enum coverage

    func testTunnelRoleAllCasesRoundTrip() throws {
        for role in TunnelRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(TunnelRole.self, from: data)
            XCTAssertEqual(decoded, role, "TunnelRole.\(role.rawValue) must round-trip through JSON.")
        }
    }

    // MARK: - Helpers (simulate server validation fragments)

    private func throwIfMissingToken(_ message: JarvisTunnelMessage) throws {
        guard message.roleToken != nil else { throw TunnelError.missingRoleToken }
    }

    private func throwIfRoleMismatch(token: TunnelRoleToken, storedRole: TunnelRole) throws {
        guard token.role == storedRole else { throw TunnelError.roleClaimMismatch }
    }

    private func throwIfExpired(_ token: TunnelRoleToken) throws {
        guard !token.isExpired else { throw TunnelError.expiredToken }
    }
}
