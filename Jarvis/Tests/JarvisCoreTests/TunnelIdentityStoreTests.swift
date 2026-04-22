import XCTest
@testable import JarvisCore

final class TunnelIdentityStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeWorkspaceWithIdentities(
        _ document: TunnelIdentityStore.Document
    ) throws -> (URL, JarvisRuntime, JarvisSkillRegistry) {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnel-identities-\(UUID().uuidString).json")
        try JSONEncoder().encode(document).write(to: tmp)
        return (tmp, runtime, registry)
    }

    private func sampleDocument(
        deviceID: String = "iphone-grizz",
        allowedRoles: [String] = ["voice-operator", "mobile-cockpit"],
        allowUnregisteredNonPrivileged: Bool? = nil
    ) -> (TunnelIdentityStore.Document, String) {
        let keyBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let keyHex = keyBytes.map { String(format: "%02x", $0) }.joined()
        let doc = TunnelIdentityStore.Document(
            identities: [
                TunnelIdentityStore.DeviceIdentity(
                    deviceID: deviceID,
                    allowedRoles: allowedRoles,
                    identityKeyHex: keyHex
                )
            ],
            allowUnregisteredNonPrivileged: allowUnregisteredNonPrivileged
        )
        return (doc, keyHex)
    }

    // MARK: - Bootstrap mode

    func testBootstrapModeRejectsPrivilegedRoleWithoutIdentityProof() throws {
        let store = TunnelIdentityStore(
            fileURL: URL(fileURLWithPath: "/does/not/exist/\(UUID().uuidString).json")
        )
        store.reload()
        XCTAssertTrue(store.isBootstrapMode)

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0"
        )
        XCTAssertEqual(store.validate(reg), .privilegedRoleRequiresIdentityProof)
    }

    func testBootstrapModeAllowsNonPrivilegedRole() throws {
        let store = TunnelIdentityStore(
            fileURL: URL(fileURLWithPath: "/does/not/exist/\(UUID().uuidString).json")
        )
        store.reload()
        let reg = JarvisClientRegistration(
            deviceID: "terminal-host",
            deviceName: "Mac",
            platform: "macOS",
            role: "terminal",
            appVersion: "1.0.0"
        )
        XCTAssertNil(store.validate(reg))
    }

    // MARK: - Strict mode (identities.json present)

    func testStrictModeAcceptsValidProof() throws {
        let (doc, keyHex) = sampleDocument()
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "voice-operator",
            identityKeyHex: keyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertNil(store.validate(reg))
    }

    func testStrictModeRejectsWrongRoleForDevice() throws {
        let (doc, keyHex) = sampleDocument(allowedRoles: ["mobile-cockpit"])
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "voice-operator",
            identityKeyHex: keyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertEqual(store.validate(reg), .roleNotAllowedForDevice)
    }

    func testStrictModeRejectsProofMismatch() throws {
        let (doc, _) = sampleDocument()
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        let wrongKey = String(repeating: "ab", count: 32)
        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "voice-operator",
            identityKeyHex: wrongKey
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertEqual(store.validate(reg), .proofMismatch)
    }

    func testStrictModeRejectsStaleNonce() throws {
        let (doc, keyHex) = sampleDocument()
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        let formatter = ISO8601DateFormatter()
        let stale = formatter.string(from: Date(timeIntervalSinceNow: -500))
        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "voice-operator",
            identityKeyHex: keyHex,
            nonce: stale
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        guard case .nonceStale = store.validate(reg) else {
            return XCTFail("expected .nonceStale")
        }
    }

    func testStrictModeRejectsReplay() throws {
        let (doc, keyHex) = sampleDocument()
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "voice-operator",
            identityKeyHex: keyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertNil(store.validate(reg), "first use should succeed")
        XCTAssertEqual(store.validate(reg), .nonceReplay, "second use of same nonce must be rejected")
    }

    func testStrictModeRejectsUnknownDevicePrivilegedRole() throws {
        let (doc, _) = sampleDocument()
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        let reg = JarvisClientRegistration(
            deviceID: "intruder",
            deviceName: "Mystery",
            platform: "iOS",
            role: "voice-operator",
            appVersion: "1.0.0"
        )
        XCTAssertEqual(store.validate(reg), .unknownDevice)
    }

    func testAllowUnregisteredNonPrivilegedFlag() throws {
        let (baseDoc, _) = sampleDocument()
        let doc = TunnelIdentityStore.Document(
            identities: baseDoc.identities,
            allowUnregisteredNonPrivileged: true
        )
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        let reg = JarvisClientRegistration(
            deviceID: "terminal-host",
            deviceName: "Mac",
            platform: "macOS",
            role: "terminal",
            appVersion: "1.0.0"
        )
        XCTAssertNil(store.validate(reg), "terminal role should be allowed when flag is true")
    }

    func testServerAuthorizeRegistrationIntegration() throws {
        let (doc, keyHex) = sampleDocument()
        let (url, runtime, registry) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()
        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19880,
            sharedSecret: "spec-007-integration",
            identityStore: store
        )

        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "iphone-grizz",
            role: "mobile-cockpit",
            identityKeyHex: keyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "iphone-grizz",
            deviceName: "iPhone",
            platform: "iOS",
            role: "mobile-cockpit",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        let result = server.authorizeRegistration(reg)
        XCTAssertEqual(result.role, "mobile-cockpit")
        XCTAssertNil(result.error)
    }

    // MARK: - §3.2 watch round-trip

    func testStrictModeAcceptsWatchSignedProof() throws {
        let (doc, keyHex) = sampleDocument(
            deviceID: "watch-grizz",
            allowedRoles: ["watch"]
        )
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "watch-grizz",
            role: "watch",
            identityKeyHex: keyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "watch-grizz",
            deviceName: "Apple Watch",
            platform: "watch",
            role: "watch",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertNil(store.validate(reg),
                     "signed watch registration must validate when watch is an allowed role")
    }

    func testBootstrapModeRejectsUnsignedWatchRole() throws {
        // §3.4b hardens: watch is privileged, so bootstrap (no identities.json)
        // must reject unsigned watch registrations just like voice-operator.
        let store = TunnelIdentityStore(
            fileURL: URL(fileURLWithPath: "/does/not/exist/\(UUID().uuidString).json")
        )
        store.reload()
        XCTAssertTrue(store.isBootstrapMode)

        let reg = JarvisClientRegistration(
            deviceID: "watch-grizz",
            deviceName: "Apple Watch",
            platform: "watch",
            role: "watch",
            appVersion: "1.0.0"
        )
        XCTAssertEqual(store.validate(reg), .privilegedRoleRequiresIdentityProof,
                       "unsigned watch registration must be rejected in bootstrap mode")
    }

    func testStrictModeRejectsWatchWithWrongKey() throws {
        let (doc, _) = sampleDocument(
            deviceID: "watch-grizz",
            allowedRoles: ["watch"]
        )
        let (url, _, _) = try makeWorkspaceWithIdentities(doc)
        let store = TunnelIdentityStore(fileURL: url)
        store.reload()

        // Sign with a key that doesn't match identities.json.
        let wrongKeyHex = Data(repeating: 0xBB, count: 32)
            .map { String(format: "%02x", $0) }.joined()
        guard let signed = JarvisTunnelCrypto.signRegistration(
            deviceID: "watch-grizz",
            role: "watch",
            identityKeyHex: wrongKeyHex
        ) else { return XCTFail("sign failed") }

        let reg = JarvisClientRegistration(
            deviceID: "watch-grizz",
            deviceName: "Apple Watch",
            platform: "watch",
            role: "watch",
            appVersion: "1.0.0",
            nonce: signed.nonce,
            identityProof: signed.proof
        )
        XCTAssertEqual(store.validate(reg), .proofMismatch)
    }
}
