import CryptoKit
import Foundation

public enum JarvisTunnelCryptoError: Error, LocalizedError {
    case sealingFailed
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .sealingFailed:
            return "Unable to seal tunnel payload."
        case .invalidPayload:
            return "Tunnel payload is not valid base64."
        }
    }
}

public struct JarvisTunnelCrypto: Sendable {
    private let key: SymmetricKey
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(sharedSecret: String) {
        let digest = SHA256.hash(data: Data(sharedSecret.utf8))
        self.key = SymmetricKey(data: Data(digest))
    }

    /// SPEC-007: produce an identity proof for a registration.
    /// - Parameters:
    ///   - deviceID: stable device identifier
    ///   - role: tunnel role being claimed
    ///   - identityKeyHex: per-device 32-byte identity key, hex-encoded
    ///   - nonce: ISO-8601 nonce; defaults to `Date()` now
    /// - Returns: `(nonce, proofHex)` for attaching to `JarvisClientRegistration`.
    public static func signRegistration(
        deviceID: String,
        role: String,
        identityKeyHex: String,
        nonce: String? = nil
    ) -> (nonce: String, proof: String)? {
        let formatter = ISO8601DateFormatter()
        let nonceValue = nonce ?? formatter.string(from: Date())
        guard let keyData = Data(jarvisHexString: identityKeyHex) else { return nil }
        let key = SymmetricKey(data: keyData)
        let message = "\(deviceID):\(role.lowercased()):\(nonceValue)".data(using: .utf8) ?? Data()
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        let proof = mac.map { String(format: "%02x", $0) }.joined()
        return (nonceValue, proof)
    }

    public func seal<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        let sealed = try ChaChaPoly.seal(data, using: key)
        let combined = sealed.combined
        return combined.base64EncodedString()
    }

    public func open<T: Decodable>(_ type: T.Type, from payload: String) throws -> T {
        guard let data = Data(base64Encoded: payload) else {
            throw JarvisTunnelCryptoError.invalidPayload
        }
        let box = try ChaChaPoly.SealedBox(combined: data)
        let opened = try ChaChaPoly.open(box, using: key)
        return try decoder.decode(type, from: opened)
    }

    // MARK: - MK2-EPIC-02: Role Token signing (HMAC-SHA256, 8h TTL)

    /// Issue a signed TunnelRoleToken for the given role and client public key.
    /// MAC covers "role|issuedAtUnix|expiresAtUnix|clientPubKeyHex".
    public func signRoleToken(role: TunnelRole, clientPubKey: String) -> TunnelRoleToken {
        let now = Int64(Date().timeIntervalSince1970)
        let expiresAt = now + 8 * 3600
        let message = "\(role.rawValue)|\(now)|\(expiresAt)|\(clientPubKey)"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let macHex = mac.map { String(format: "%02x", $0) }.joined()
        return TunnelRoleToken(role: role, issuedAt: now, expiresAt: expiresAt, clientPubKey: clientPubKey, mac: macHex)
    }

    /// Returns true iff the token's MAC is valid for the current host key.
    /// Does NOT check TTL — caller is responsible for `token.isExpired`.
    public func verifyRoleToken(_ token: TunnelRoleToken) -> Bool {
        let message = "\(token.role.rawValue)|\(token.issuedAt)|\(token.expiresAt)|\(token.clientPubKey)"
        let expected = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let expectedHex = expected.map { String(format: "%02x", $0) }.joined()
        return expectedHex == token.mac
    }
}

internal extension Data {
    init?(jarvisHexString: String) {
        let trimmed = jarvisHexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count % 2 == 0 else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex {
            let next = trimmed.index(idx, offsetBy: 2)
            guard let byte = UInt8(trimmed[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
