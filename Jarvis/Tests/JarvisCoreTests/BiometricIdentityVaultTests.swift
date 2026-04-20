import XCTest
import CryptoKit
@testable import JarvisCore

final class BiometricIdentityVaultTests: XCTestCase {
    actor MockAuthenticator: BiometricAuthenticator {
        private var result: Result<Void, BiometricVaultError>
        private(set) var prompts: [String] = []

        init(result: Result<Void, BiometricVaultError> = .success(())) {
            self.result = result
        }

        func setResult(_ result: Result<Void, BiometricVaultError>) {
            self.result = result
        }

        nonisolated func authenticate(reason: String) async throws {
            await recordPrompt(reason)
            try await currentResult()
        }

        private func recordPrompt(_ reason: String) { prompts.append(reason) }
        private func currentResult() throws {
            switch result {
            case .success: return
            case .failure(let err): throw err
            }
        }
    }

    final class InMemoryIdentityKeyStore: IdentityKeyStore, @unchecked Sendable {
        private var keys: [String: SymmetricKey] = [:]
        private let lock = NSLock()

        func storeKey(_ key: SymmetricKey, for deviceID: String) throws {
            lock.lock(); defer { lock.unlock() }
            if keys[deviceID] != nil {
                throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID)
            }
            keys[deviceID] = key
        }

        func loadKey(for deviceID: String) throws -> SymmetricKey {
            lock.lock(); defer { lock.unlock() }
            guard let key = keys[deviceID] else {
                throw BiometricVaultError.keyNotProvisioned(deviceID: deviceID)
            }
            return key
        }

        func hasKey(for deviceID: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return keys[deviceID] != nil
        }

        func deleteKey(for deviceID: String) throws {
            lock.lock(); defer { lock.unlock() }
            keys.removeValue(forKey: deviceID)
        }
    }

    private func makeVault(auth: MockAuthenticator = MockAuthenticator()) -> (BiometricIdentityVault, MockAuthenticator, InMemoryIdentityKeyStore) {
        let store = InMemoryIdentityKeyStore()
        let vault = BiometricIdentityVault(authenticator: auth, store: store)
        return (vault, auth, store)
    }

    func testProvisionDeviceStoresKeyAndReturnsHex() async throws {
        let (vault, _, store) = makeVault()
        let hex = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")
        XCTAssertEqual(hex.count, 64) // 32 bytes × 2 hex chars
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit })
        XCTAssertTrue(store.hasKey(for: "iphone-1"))
    }

    func testProvisionDeviceFailsIfBiometricDenied() async throws {
        let auth = MockAuthenticator(result: .failure(.biometryUserCancelled))
        let (vault, _, store) = makeVault(auth: auth)

        do {
            _ = try await vault.provisionDevice(deviceID: "watch-1", reason: "enroll")
            XCTFail("expected throw")
        } catch BiometricVaultError.biometryUserCancelled {
            // expected
        }
        XCTAssertFalse(store.hasKey(for: "watch-1"))
    }

    func testProvisionDeviceRejectsReProvisioning() async throws {
        let (vault, _, _) = makeVault()
        _ = try await vault.provisionDevice(deviceID: "mac-1", reason: "enroll")

        do {
            _ = try await vault.provisionDevice(deviceID: "mac-1", reason: "enroll")
            XCTFail("expected throw")
        } catch BiometricVaultError.keyAlreadyProvisioned(let id) {
            XCTAssertEqual(id, "mac-1")
        }
    }

    func testSignRegistrationMatchesTunnelIdentityStoreHMAC() async throws {
        let (vault, _, _) = makeVault()
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")

        let nonce = "2026-04-20T16:00:00Z"
        let proof = try await vault.signRegistration(
            deviceID: "iphone-1", role: "voice-operator",
            nonceISO: nonce, reason: "tunnel connect"
        )
        XCTAssertEqual(proof.count, 64) // HMAC-SHA256 hex
        XCTAssertTrue(proof.allSatisfy { $0.isHexDigit })

        // Deterministic: same inputs → same proof.
        let proof2 = try await vault.signRegistration(
            deviceID: "iphone-1", role: "voice-operator",
            nonceISO: nonce, reason: "tunnel connect"
        )
        XCTAssertEqual(proof, proof2)
    }

    func testSignRegistrationDifferentNonceDifferentProof() async throws {
        let (vault, _, _) = makeVault()
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")

        let a = try await vault.signRegistration(deviceID: "iphone-1", role: "r", nonceISO: "n1", reason: "x")
        let b = try await vault.signRegistration(deviceID: "iphone-1", role: "r", nonceISO: "n2", reason: "x")
        XCTAssertNotEqual(a, b)
    }

    func testSignRegistrationFailsWithoutProvisioning() async throws {
        let (vault, _, _) = makeVault()
        do {
            _ = try await vault.signRegistration(
                deviceID: "ghost", role: "r",
                nonceISO: "n", reason: "x"
            )
            XCTFail("expected throw")
        } catch BiometricVaultError.keyNotProvisioned(let id) {
            XCTAssertEqual(id, "ghost")
        }
    }

    func testSignRegistrationFailsOnEmptyNonce() async throws {
        let (vault, _, _) = makeVault()
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")
        do {
            _ = try await vault.signRegistration(
                deviceID: "iphone-1", role: "r",
                nonceISO: "", reason: "x"
            )
            XCTFail("expected throw")
        } catch BiometricVaultError.malformedNonce {
            // expected
        }
    }

    func testSignRegistrationFailsIfBiometricDeniedEvenIfKeyExists() async throws {
        let auth = MockAuthenticator()
        let (vault, _, _) = makeVault(auth: auth)
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")

        await auth.setResult(.failure(.biometryUnavailable))

        do {
            _ = try await vault.signRegistration(
                deviceID: "iphone-1", role: "r",
                nonceISO: "n", reason: "x"
            )
            XCTFail("expected throw")
        } catch BiometricVaultError.biometryUnavailable {
            // expected
        }
    }

    func testRevokeDeviceDeletesKeyAfterBiometric() async throws {
        let (vault, _, store) = makeVault()
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll")
        XCTAssertTrue(store.hasKey(for: "iphone-1"))

        try await vault.revokeDevice(deviceID: "iphone-1", reason: "revoke")
        XCTAssertFalse(store.hasKey(for: "iphone-1"))
    }

    func testSignedProofMatchesIndependentHMACComputation() async throws {
        // Cross-check: the proof Jarvis emits must be byte-equal to the
        // HMAC a reference implementation would produce from the raw key.
        let fixedKey = SymmetricKey(data: Data(repeating: 0xAB, count: 32))
        let store = InMemoryIdentityKeyStore()
        try store.storeKey(fixedKey, for: "iphone-1")
        let vault = BiometricIdentityVault(
            authenticator: MockAuthenticator(),
            store: store
        )

        let nonce = "2026-04-20T17:00:00Z"
        let proof = try await vault.signRegistration(
            deviceID: "iphone-1", role: "voice-operator",
            nonceISO: nonce, reason: "x"
        )

        let message = Data("iphone-1:voice-operator:\(nonce)".utf8)
        let expected = HMAC<SHA256>
            .authenticationCode(for: message, using: fixedKey)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(proof, expected)
    }

    func testPromptsRecordedForAudit() async throws {
        let auth = MockAuthenticator()
        let (vault, _, _) = makeVault(auth: auth)
        _ = try await vault.provisionDevice(deviceID: "iphone-1", reason: "enroll-iphone")
        _ = try await vault.signRegistration(
            deviceID: "iphone-1", role: "r",
            nonceISO: "n", reason: "connect-iphone"
        )
        let prompts = await auth.prompts
        XCTAssertEqual(prompts, ["enroll-iphone", "connect-iphone"])
    }
}
