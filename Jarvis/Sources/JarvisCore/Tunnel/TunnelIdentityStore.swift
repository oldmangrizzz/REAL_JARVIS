import Foundation
import CryptoKit
import LocalAuthentication
import Security

// MARK: - Host Kind

/// Represents the type of host that participates in a tunnel connection.
public enum HostKind: String, Codable, CaseIterable {
    case phone
    case tablet
    case desktop
    case watch   // ← New case for watchOS devices
}

// MARK: - Tunnel Identity

/// A cryptographic identity used to authenticate a host within a tunnel.
public struct TunnelIdentity: Codable {
    /// The kind of host this identity belongs to.
    public let hostKind: HostKind
    
    /// A stable identifier derived from the public key (SHA‑256 of the raw public key bytes).
    public let identifier: Data
    
    /// A signed registration proof that binds the identifier to a role.
    /// The proof is a CBOR‑encoded map containing the role and identifier, signed with the private key.
    public let registrationProof: Data
    
    /// The underlying private key used for signing. Stored in the Secure Enclave when possible.
    /// This property is **not** encoded/decoded; it is re‑loaded from the keychain on demand.
    public var privateKey: SecureEnclave.P256.Signing.PrivateKey? {
        get {
            guard let tag = TunnelIdentityStore.keyTag(for: identifier) else { return nil }
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: tag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecReturnRef as String: true,
                kSecUseOperationPrompt as String: "Authenticate to access tunnel credentials"
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let secKey = item as! SecKey? else { return nil }
            return try? SecureEnclave.P256.Signing.PrivateKey(secKey: secKey)
        }
    }
}

// MARK: - Tunnel Identity Store

/// Persists and retrieves `TunnelIdentity` objects. Handles creation of Secure‑Enclave‑backed keys
/// and generation of registration proofs for each host kind.
public final class TunnelIdentityStore {
    
    // MARK: Persistence
    
    private let storageURL: URL
    
    public init(storageURL: URL) {
        self.storageURL = storageURL
    }
    
    /// Loads a stored identity, if any.
    public func loadIdentity() throws -> TunnelIdentity? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode(TunnelIdentity.self, from: data)
    }
    
    /// Persists an identity to disk.
    private func persist(_ identity: TunnelIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        try data.write(to: storageURL, options: .atomic)
    }
    
    // MARK: Identity Creation
    
    /// Returns an existing identity or creates a new one for the given host kind.
    public func identity(for kind: HostKind) throws -> TunnelIdentity {
        if let existing = try loadIdentity(), existing.hostKind == kind {
            return existing
        }
        let newIdentity = try createIdentity(for: kind)
        try persist(newIdentity)
        return newIdentity
    }
    
    /// Core creation routine. Generates a Secure Enclave key (when supported) and a registration proof.
    private func createIdentity(for kind: HostKind) throws -> TunnelIdentity {
        // 1️⃣ Generate or retrieve a Secure‑Enclave‑backed private key.
        let privateKey = try generateSecureEnclaveKey(for: kind)
        
        // 2️⃣ Derive the identifier from the public key.
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let identifier = SHA256.hash(data: publicKeyData).data
        
        // 3️⃣ Build the registration proof payload.
        let proofPayload = RegistrationProofPayload(role: roleString(for: kind), identifier: identifier)
        let proofData = try CBOR.encode(proofPayload)
        
        // 4️⃣ Sign the payload with the private key.
        let signature = try privateKey.signature(for: proofData).derRepresentation
        let signedProof = SignedProof(payload: proofData, signature: signature)
        let signedProofData = try CBOR.encode(signedProof)
        
        // 5️⃣ Assemble the identity.
        return TunnelIdentity(
            hostKind: kind,
            identifier: identifier,
            registrationProof: signedProofData
        )
    }
    
    // MARK: Secure Enclave Helpers
    
    /// Generates a Secure Enclave key for the supplied host kind.
    /// The key is stored in the keychain with a deterministic tag derived from the host kind.
    private func generateSecureEnclaveKey(for kind: HostKind) throws -> SecureEnclave.P256.Signing.PrivateKey {
        let tag = keyTag(for: kind)
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        )!
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:     256,
            kSecAttrTokenID as String:           kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:   true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access
            ]
        ]
        
        // Attempt to retrieve an existing key first.
        if let existingKey = try retrieveKey(withTag: tag) {
            return existingKey
        }
        
        // Create a new key if none exists.
        return try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: true, accessControl: access, authenticationContext: nil)
    }
    
    /// Retrieves a Secure Enclave key from the keychain using the supplied tag.
    private func retrieveKey(withTag tag: Data) throws -> SecureEnclave.P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassKey,
            kSecAttrApplicationTag as String:  tag,
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String:           true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let secKey = item as! SecKey? else { return nil }
        return try SecureEnclave.P256.Signing.PrivateKey(secKey: secKey)
    }
    
    /// Derives a deterministic keychain tag for a given identifier.
    static func keyTag(for identifier: Data) -> Data? {
        // Use a SHA‑256 hash of the identifier prefixed with a namespace.
        let namespace = "com.example.jarvis.tunnel.identity".data(using: .utf8)!
        return SHA256.hash(data: namespace + identifier).data
    }
    
    /// Derives a deterministic keychain tag for a host kind (used when the key does not yet exist).
    private func keyTag(for kind: HostKind) -> Data {
        // The tag is simply the UTF‑8 bytes of the enum raw value, prefixed to avoid collisions.
        let namespace = "com.example.jarvis.tunnel.identity".data(using: .utf8)!
        return SHA256.hash(data: namespace + kind.rawValue.data(using: .utf8)!).data
    }
    
    // MARK: Helper Types
    
    /// The payload that is signed to prove registration.
    private struct RegistrationProofPayload: Codable {
        let role: String          // e.g. "phone", "tablet", "watch"
        let identifier: Data
    }
    
    /// The signed proof consisting of the payload and its signature.
    private struct SignedProof: Codable {
        let payload: Data
        let signature: Data
    }
    
    /// Maps a `HostKind` to the role string used inside the registration proof.
    private func roleString(for kind: HostKind) -> String {
        switch kind {
        case .phone:   return "phone"
        case .tablet:  return "tablet"
        case .desktop: return "desktop"
        case .watch:   return "watch"   // ← New role mapping for watchOS
        }
    }
}

// MARK: - Extensions

private extension Digest {
    var data: Data {
        return withUnsafeBytes { Data($0) }
    }
}

// MARK: - CBOR Helper (Simple Stub)

/// Minimal CBOR encoder/decoder used for the registration proof.
/// In production this would be replaced by a full‑featured library such as `SwiftCBOR`.
enum CBOR {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        // For the purpose of this implementation we fall back to JSON as a placeholder.
        // Replace with real CBOR encoding in the final product.
        return try JSONEncoder().encode(value)
    }
    
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Placeholder using JSON decoding.
        return try JSONDecoder().decode(T.self, from: data)
    }
}