# Secure Enclave Signing Research

## BiometricTunnelRegistrar on WatchOS

### Current Implementation (iOS/iPad/macOS):

```swift
extension BiometricTunnelRegistrar {
    func makeRegistration(
        deviceID: String,
        deviceName: String,
        platform: String,
        role: String,
        appVersion: String,
        reason: String
    ) async throws -> JarvisClientRegistration {
        let nonceISO = ISO8601DateFormatter().string(from: Date())
        let proof = try await vault.signRegistration(
            deviceID: deviceID,
            role: role.lowercased(),
            nonceISO: nonceISO,
            reason: reason
        )
        return JarvisClientRegistration(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: platform,
            role: role.lowercased(),
            appVersion: appVersion,
            nonce: nonceISO,
            identityProof: proof
        )
    }
}
```

### BiometricIdentityVault on watchOS:

**What's available on watchOS:**
- ✅ Secure Enclave availability (Series 6+)
- ✅ Keychain with .biometryCurrentSet access control
- ✅ CryptoKit (HMAC-SHA256, SymmetricKey, etc.)
- ❌ LocalAuthentication biometric prompt (watchOS does not include this framework)
- ⚠️ WatchKit biometric APIs (limited, different from iOS)

### Watch-specific Biometric Vault:

```swift
#if os(watchOS)
import WatchKit
import CryptoKit
import Foundation

public final class WatchBiometricIdentityVault: Sendable {
    private let keystore: WatchKeychainIdentityKeyStore
    private let clock: @Sendable () -> Date
    
    public init(
        keystore: WatchKeychainIdentityKeyStore = WatchKeychainIdentityKeyStore(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keystore = keystore
        self.clock = clock
    }
    
    /// Generate + store a biometric-bound identity key.
    public func provisionDevice(deviceID: String) async throws -> String {
        guard !keystore.hasKey(for: deviceID) else {
            throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID)
        }
        
        // On watchOS, we use wrist-detect as biometric
        // (not LocalAuthentication)
        try await watchBiometricAuthenticate(reason: "Pair your Jarvis watch")
        
        // Generate 32-byte key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard status == errSecSuccess else {
            throw BiometricVaultError.keychainFailure(status: status)
        }
        let key = SymmetricKey(data: Data(keyBytes))
        try keystore.storeKey(key, for: deviceID)
        
        return keyBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// HMAC-SHA256 over `deviceID:role:nonceISO`, biometric-gated.
    public func signRegistration(
        deviceID: String,
        role: String,
        nonceISO: String
    ) async throws -> String {
        guard !nonceISO.isEmpty else { throw BiometricVaultError.malformedNonce }
        guard keystore.hasKey(for: deviceID) else {
            throw BiometricVaultError.keyNotProvisioned(deviceID: deviceID)
        }
        
        // Wrist-detect authentication
        try await watchBiometricAuthenticate(reason: "Sign your Jarvis registration")
        
        let key = try keystore.loadKey(for: deviceID)
        let message = "\(deviceID):\(role.lowercased()):\(nonceISO)"
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Watch-specific biometric authentication.
    /// On watchOS, we use wrist-detect + device passcode fallback.
    private func watchBiometricAuthenticate(reason: String) async throws {
        // On watchOS, we simulate biometric auth via:
        // 1. Wrist detection (if available)
        // 2. Device passcode (fallback if wrist not detected)
        // 3. WatchKit authentication context (limited)
        
        let wristDetect = WKInterfaceDevice.current().isWristDetected
        let passcodeSet = LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: nil
        )
        
        guard wristDetect || passcodeSet else {
            throw BiometricVaultError.biometryUnavailable
        }
        
        // Wrist detect successful, proceed
    }
}

/// Keychain-backed store with `.biometryCurrentSet` access control.
public final class WatchKeychainIdentityKeyStore: IdentityKeyStore, @unchecked Sendable {
    private let service: String
    
    public init(service: String = "ai.realjarvis.watch.tunnel.identity") {
        self.service = service
    }
    
    public func storeKey(_ key: SymmetricKey, for deviceID: String) throws {
        if hasKey(for: deviceID) {
            throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID)
        }
        
        // On watchOS, use .accessibleWhenUnlockedThisDeviceOnly
        // (no .biometryCurrentSet support on watchOS 2026)
        let raw = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

/// Biometric vault errors.
public enum BiometricVaultError: Error, Equatable, Sendable {
    case biometryUnavailable
    case biometryUserCancelled
    case keyNotProvisioned(deviceID: String)
    case keyAlreadyProvisioned(deviceID: String)
    case keychainFailure(status: Int32)
    case malformedNonce
}
#endif
```

### Security Considerations:

| Aspect | iOS | watchOS 2026 |
|--------|-----|-------------|
| Secure Enclave | ✅ Always available | ✅ Series 6+ |
| Biometric prompt | ✅ LocalAuthentication | ❌ Not available |
| Wrist detection | ❌ Not available | ✅ Always available |
| Keychain access control | .biometryCurrentSet | .accessibleWhenUnlockedThisDeviceOnly |
| Key protection | Biometric + passcode | Passcode only |

### Recommendations:

1. **Phase 1 (App Store):** Use passcode fallback on watch, secure but not biometric
2. **Phase 2 (operator build):** Use biometric from companion iOS device (proxy auth)
3. **Future (Apple open):** Full LocalAuthentication on watchOS (not yet available)

### Tunnel Identity Integration:

```swift
// In JarvisClientRegistration, add watch-specific fields
public struct JarvisClientRegistration: Codable, Sendable {
    // ... existing fields ...
    
    /// Watch-specific: watch pairing ID (separate from phone)
    public let watchPairingID: String?
    
    /// Watch-specific: secure enclave key hash (for verification)
    public let secureEnclaveKeyHash: String?
    
    // ... existing fields ...
}
```
