import XCTest
import CryptoKit
@testable import JarvisCore

final class BiometricTunnelRegistrarTests: XCTestCase {
    final class TickBox: @unchecked Sendable {
        private var current: Date
        private let lock = NSLock()
        init(start: Date) { self.current = start }
        func next() -> Date {
            lock.lock(); defer { lock.unlock() }
            let v = current
            current = current.addingTimeInterval(1.0)
            return v
        }
    }

    actor AlwaysApprove: BiometricAuthenticator {
        nonisolated func authenticate(reason: String) async throws {}
    }

    final class FixedIdentityKeyStore: IdentityKeyStore, @unchecked Sendable {
        private var keys: [String: SymmetricKey] = [:]
        private let lock = NSLock()

        func seed(_ key: SymmetricKey, for deviceID: String) {
            lock.lock(); defer { lock.unlock() }
            keys[deviceID] = key
        }
        func storeKey(_ key: SymmetricKey, for deviceID: String) throws {
            lock.lock(); defer { lock.unlock() }
            if keys[deviceID] != nil { throw BiometricVaultError.keyAlreadyProvisioned(deviceID: deviceID) }
            keys[deviceID] = key
        }
        func loadKey(for deviceID: String) throws -> SymmetricKey {
            lock.lock(); defer { lock.unlock() }
            guard let k = keys[deviceID] else { throw BiometricVaultError.keyNotProvisioned(deviceID: deviceID) }
            return k
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

    private func writeIdentitiesJSON(
        identities: [TunnelIdentityStore.DeviceIdentity],
        allowUnregisteredNonPrivileged: Bool = false
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-registrar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let fileURL = tmp.appendingPathComponent("identities.json")
        let doc = TunnelIdentityStore.Document(
            identities: identities,
            allowUnregisteredNonPrivileged: allowUnregisteredNonPrivileged
        )
        let data = try JSONEncoder().encode(doc)
        try data.write(to: fileURL)
        return fileURL
    }

    private func makeRegistrar(deviceID: String, key: SymmetricKey) -> BiometricTunnelRegistrar {
        let store = FixedIdentityKeyStore()
        store.seed(key, for: deviceID)
        let vault = BiometricIdentityVault(authenticator: AlwaysApprove(), store: store)
        return BiometricTunnelRegistrar(vault: vault)
    }

    func testRegistrationRoundTripsThroughTunnelIdentityStoreValidate() async throws {
        let deviceID = "iphone-operator-1"
        let keyBytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined(),
            principal: "grizz"
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeRegistrar(deviceID: deviceID, key: key)
        let registration = try await registrar.makeRegistration(
            deviceID: deviceID,
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            reason: "connect tunnel"
        )

        XCTAssertNil(store.validate(registration), "server must accept registrar-built proof")
    }

    func testRoleIsLowercasedBeforeSigningSoServerHMACMatches() async throws {
        let deviceID = "watch-1"
        let keyBytes = Data(repeating: 0x42, count: 32)
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeRegistrar(deviceID: deviceID, key: key)
        // Caller passes uppercase; registrar normalizes.
        let reg = try await registrar.makeRegistration(
            deviceID: deviceID,
            deviceName: "Watch", platform: "watchOS",
            role: "VOICE-OPERATOR",
            appVersion: "1.0.0", reason: "r"
        )
        XCTAssertEqual(reg.role, "voice-operator")
        XCTAssertNil(store.validate(reg))
    }

    func testNonceIsFreshISO8601MatchingServerParser() async throws {
        let deviceID = "dev-1"
        let key = SymmetricKey(data: Data(repeating: 0x01, count: 32))
        let registrar = makeRegistrar(deviceID: deviceID, key: key)

        let reg = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n",
            platform: "p", role: "voice-operator",
            appVersion: "v", reason: "r"
        )

        guard let nonce = reg.nonce else { return XCTFail("nonce nil") }
        XCTAssertTrue(nonce.contains("T"))
        // Server uses default ISO8601DateFormatter — MUST parse with default options.
        let serverFormatter = ISO8601DateFormatter()
        XCTAssertNotNil(serverFormatter.date(from: nonce),
                        "server-side formatter must parse the client-emitted nonce")
    }

    func testInjectedClockDrivesNonceUniqueness() async throws {
        // Production: back-to-back calls inside the same wall-clock second
        // produce the same nonce (acceptable — server rejects replay).
        // Tests: drive uniqueness via the injected clock.
        let deviceID = "dev-clock"
        let keyBytes = Data(repeating: 0x0C, count: 32)
        let key = SymmetricKey(data: keyBytes)
        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID, allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let vaultStore = FixedIdentityKeyStore()
        vaultStore.seed(key, for: deviceID)
        let vault = BiometricIdentityVault(authenticator: AlwaysApprove(), store: vaultStore)

        let tickBox = TickBox(start: Date())
        let registrar = BiometricTunnelRegistrar(vault: vault, clock: { tickBox.next() })

        let a = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n", platform: "p",
            role: "voice-operator", appVersion: "v", reason: "r"
        )
        let b = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n", platform: "p",
            role: "voice-operator", appVersion: "v", reason: "r"
        )
        XCTAssertNotEqual(a.nonce, b.nonce)
        XCTAssertNotEqual(a.identityProof, b.identityProof)
        XCTAssertNil(store.validate(a))
        XCTAssertNil(store.validate(b))
    }

    func testStaleClockIsRejectedByServer() async throws {
        let deviceID = "dev-stale"
        let keyBytes = Data(repeating: 0x07, count: 32)
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        // 10 minutes in the past — outside ±120s window.
        let stale = Date().addingTimeInterval(-600)
        let vaultStore = FixedIdentityKeyStore()
        vaultStore.seed(key, for: deviceID)
        let vault = BiometricIdentityVault(authenticator: AlwaysApprove(), store: vaultStore)
        let registrar = BiometricTunnelRegistrar(vault: vault, clock: { stale })

        let reg = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n", platform: "p",
            role: "voice-operator", appVersion: "v", reason: "r"
        )

        guard case .nonceStale = store.validate(reg) else {
            return XCTFail("expected nonceStale, got \(String(describing: store.validate(reg)))")
        }
    }

    func testReplayRejectedBySecondValidate() async throws {
        let deviceID = "dev-replay"
        let keyBytes = Data(repeating: 0x08, count: 32)
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID, allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeRegistrar(deviceID: deviceID, key: key)
        let reg = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n", platform: "p",
            role: "voice-operator", appVersion: "v", reason: "r"
        )

        XCTAssertNil(store.validate(reg))
        XCTAssertEqual(store.validate(reg), .nonceReplay)
    }

    func testWrongKeyFailsProofMismatch() async throws {
        let deviceID = "dev-wrongkey"
        let serverKeyBytes = Data(repeating: 0xAA, count: 32)
        let clientKey = SymmetricKey(data: Data(repeating: 0xBB, count: 32))

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID, allowedRoles: ["voice-operator"],
            identityKeyHex: serverKeyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeRegistrar(deviceID: deviceID, key: clientKey)
        let reg = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "n", platform: "p",
            role: "voice-operator", appVersion: "v", reason: "r"
        )
        XCTAssertEqual(store.validate(reg), .proofMismatch)
    }

    // MARK: - §3.3 registerWatch

    private func makeWatchRegistrar(deviceID: String, key: SymmetricKey) -> BiometricTunnelRegistrar {
        let iphoneStore = FixedIdentityKeyStore()
        iphoneStore.seed(SymmetricKey(data: Data(repeating: 0xEE, count: 32)), for: "iphone-placeholder")
        let iphoneVault = BiometricIdentityVault(authenticator: AlwaysApprove(), store: iphoneStore)

        let watchStore = FixedIdentityKeyStore()
        watchStore.seed(key, for: deviceID)
        let watchVault = BiometricIdentityVault(authenticator: AlwaysApprove(), store: watchStore)
        return BiometricTunnelRegistrar(vault: iphoneVault, watchVault: watchVault)
    }

    func testRegisterWatchWithoutWatchVaultThrowsBiometryUnavailable() async {
        let registrar = makeRegistrar(deviceID: "watch-novault", key: SymmetricKey(data: Data(repeating: 0x01, count: 32)))
        do {
            _ = try await registrar.registerWatch(
                deviceID: "watch-novault", deviceName: "Apple Watch",
                role: "watch", appVersion: "1.0.0", reason: "bootstrap"
            )
            XCTFail("expected biometryUnavailable; watchVault is nil")
        } catch BiometricVaultError.biometryUnavailable {
            // expected
        } catch {
            XCTFail("expected biometryUnavailable, got \(error)")
        }
    }

    func testRegisterWatchRoundTripsThroughTunnelIdentityStore() async throws {
        let deviceID = "watch-round-trip"
        let keyBytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["watch"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined(),
            principal: "grizz"
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeWatchRegistrar(deviceID: deviceID, key: key)
        let reg = try await registrar.registerWatch(
            deviceID: deviceID,
            deviceName: "Apple Watch",
            role: "watch",
            appVersion: "1.0.0",
            reason: "bootstrap watch tunnel"
        )

        XCTAssertEqual(reg.platform, "watch", "registerWatch must pin platform to 'watch'")
        XCTAssertEqual(reg.role, "watch")
        XCTAssertNil(store.validate(reg), "server must accept registerWatch-built proof")
    }

    func testRegisterWatchLowercasesRoleBeforeSigning() async throws {
        let deviceID = "watch-uppercase-role"
        let keyBytes = Data(repeating: 0x5A, count: 32)
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["watch"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeWatchRegistrar(deviceID: deviceID, key: key)
        let reg = try await registrar.registerWatch(
            deviceID: deviceID, deviceName: "Apple Watch",
            role: "WATCH", appVersion: "1.0.0", reason: "r"
        )
        XCTAssertEqual(reg.role, "watch")
        XCTAssertEqual(reg.platform, "watch")
        XCTAssertNil(store.validate(reg))
    }

    func testRegisterWatchRejectedWhenWatchNotInAllowedRoles() async throws {
        // Privileged role hardening: watch tunnel cannot borrow voice-operator's
        // identity file slot.
        let deviceID = "watch-unauth"
        let keyBytes = Data(repeating: 0x77, count: 32)
        let key = SymmetricKey(data: keyBytes)

        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined()
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeWatchRegistrar(deviceID: deviceID, key: key)
        let reg = try await registrar.registerWatch(
            deviceID: deviceID, deviceName: "Apple Watch",
            role: "watch", appVersion: "1.0.0", reason: "r"
        )
        // With role="watch" but allowedRoles=["voice-operator"], validate must reject.
        XCTAssertEqual(store.validate(reg), .roleNotAllowedForDevice)
    }
}
