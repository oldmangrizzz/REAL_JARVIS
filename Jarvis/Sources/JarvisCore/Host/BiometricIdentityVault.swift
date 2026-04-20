import CryptoKit
import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Biometric-bound per-device identity vault.
///
/// SPEC-007-BIO: companion primitive to `TunnelIdentityStore`. The
/// server side of the tunnel keeps each device's identity key in
/// `.jarvis/storage/tunnel/identities.json`; the **client** side keeps
/// the same key in the platform Keychain, guarded by
/// `.biometryCurrentSet` so that enrolling a new fingerprint / face
/// invalidates the stored reference (and therefore the device's
/// privileged-role access). A fresh enrollment is a new human under the
/// hood — fail closed.
///
/// Shape is protocol-based so hermetic tests can inject a
/// `MockBiometricAuthenticator` + `InMemoryIdentityKeyStore`. Hardware
/// access is isolated in `LocalAuthenticationBiometricAuthenticator`
/// and `KeychainIdentityKeyStore` and only compiled where
/// `LocalAuthentication` is available.
///
/// ## Flow
///
/// 1. `provisionDevice(deviceID:reason:)` — one-time on enrollment:
///    prompts biometric, generates a fresh 32-byte key, stores it
///    biometric-bound, returns the hex form so the operator can paste
///    it into the server-side `identities.json`.
/// 2. `signRegistration(deviceID:role:nonceISO:reason:)` — on every
///    tunnel connect: prompts biometric, reads the key out, HMAC-SHA256
///    over `"deviceID:role:nonceISO"`, returns lowercase hex — the exact
///    shape `TunnelIdentityStore.validate()` expects for
///    `registration.identityProof`.
///
/// No biometric = no key = no registration. Fail-closed.

public enum BiometricVaultError: Error, Equatable, Sendable {
    case biometryUnavailable
    case biometryUserCancelled
    case biometryFailed(code: Int)
    case keyNotProvisioned(deviceID: String)
    case keyAlreadyProvisioned(deviceID: String)
    case keychainFailure(status: Int32)
    case malformedNonce
}

public protocol BiometricAuthenticator: Sendable {
    /// Prompt the operator for a biometric and return on success.
    /// Implementations must throw a `BiometricVaultError` for any
    /// non-success outcome so callers cannot mistake a nil-free path
    /// for approval.
    func authenticate(reason: String) async throws
}

public protocol IdentityKeyStore: Sendable {
    /// Persist a freshly-generated identity key against a deviceID.
    /// Implementations must reject re-provisioning (`keyAlreadyProvisioned`)
    /// so a silent key-swap is impossible.
    func storeKey(_ key: SymmetricKey, for deviceID: String) throws
    func loadKey(for deviceID: String) throws -> SymmetricKey
    func hasKey(for deviceID: String) -> Bool
    func deleteKey(for deviceID: String) throws
}

public final class BiometricIdentityVault: Sendable {
    private let authenticator: BiometricAuthenticator
    private let store: IdentityKeyStore
    private let keyByteCount: Int

    public init(authenticator: BiometricAuthenticator, store: IdentityKeyStore, keyByteCount: Int = 32) {
        self.authenticator = authenticator
        self.store = store
        self.keyByteCount = keyByteCount
    }

    /// Generate + store a biometric-bound identity key. Returns the key
    /// in the `lowercase hex` form the server identities.json consumes.
    public func provisionDevice(deviceID: String, reason: String) async throws -> String {
        guard !store.hasKey(for: deviceID) else {
            throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID)
        }
        try await authenticator.authenticate(reason: reason)

        var keyBytes = [UInt8](repeating: 0, count: keyByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyByteCount, &keyBytes)
        guard status == errSecSuccess else {
            throw BiometricVaultError.keychainFailure(status: status)
        }
        let key = SymmetricKey(data: Data(keyBytes))
        try store.storeKey(key, for: deviceID)

        return keyBytes.map { String(format: "%02x", $0) }.joined()
    }

    /// HMAC-SHA256 over `"deviceID:role:nonceISO"`, biometric-gated.
    /// Returns lowercase hex to match `TunnelIdentityStore` validation.
    public func signRegistration(deviceID: String, role: String, nonceISO: String, reason: String) async throws -> String {
        guard !nonceISO.isEmpty else { throw BiometricVaultError.malformedNonce }
        guard store.hasKey(for: deviceID) else {
            throw BiometricVaultError.keyNotProvisioned(deviceID: deviceID)
        }
        try await authenticator.authenticate(reason: reason)

        let key = try store.loadKey(for: deviceID)
        let message = "\(deviceID):\(role):\(nonceISO)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Tear down a device's credentials. Biometric-gated so a thief
    /// with physical access cannot silently erase-and-rebind.
    public func revokeDevice(deviceID: String, reason: String) async throws {
        try await authenticator.authenticate(reason: reason)
        try store.deleteKey(for: deviceID)
    }
}

// MARK: - Hardware-backed implementations

#if canImport(LocalAuthentication)

public final class LocalAuthenticationBiometricAuthenticator: BiometricAuthenticator, @unchecked Sendable {
    private let policy: LAPolicy

    public init(policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics) {
        self.policy = policy
    }

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            throw BiometricVaultError.biometryUnavailable
        }
        do {
            try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                throw BiometricVaultError.biometryUserCancelled
            default:
                throw BiometricVaultError.biometryFailed(code: laError.code.rawValue)
            }
        }
    }
}

/// Keychain-backed store with `.biometryCurrentSet` access control so
/// enrolling a new finger / face invalidates the stored key (and thus
/// the device's privileged-role access). Account scoping uses
/// `kSecAttrAccount = deviceID`.
public final class KeychainIdentityKeyStore: IdentityKeyStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "ai.realjarvis.tunnel.identity") {
        self.service = service
    }

    public func storeKey(_ key: SymmetricKey, for deviceID: String) throws {
        if hasKey(for: deviceID) {
            throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID)
        }
        var accessControlError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            throw BiometricVaultError.keychainFailure(status: errSecParam)
        }
        let raw = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecValueData as String: raw,
            kSecAttrAccessControl as String: access
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricVaultError.keychainFailure(status: status)
        }
    }

    public func loadKey(for deviceID: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound {
                throw BiometricVaultError.keyNotProvisioned(deviceID: deviceID)
            }
            throw BiometricVaultError.keychainFailure(status: status)
        }
        return SymmetricKey(data: data)
    }

    public func hasKey(for deviceID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public func deleteKey(for deviceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiometricVaultError.keychainFailure(status: status)
        }
    }
}

#endif
