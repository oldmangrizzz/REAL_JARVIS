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
}
