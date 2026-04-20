import XCTest
import Network
@testable import JarvisCore

final class JarvisHostTunnelServerTests: XCTestCase {

    // MARK: - Server lifecycle

    func testServerStartsAndStopsWithoutError() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19443,
            sharedSecret: "test-tunnel-secret"
        )

        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    func testServerGeneratesRandomSecretWhenNoneProvided() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        // No sharedSecret provided → should auto-generate with SecRandomCopyBytes
        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19444
        )

        // If we can start/stop without issue, the crypto was initialized properly
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    func testServerDoubleStartIsNoOp() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19445,
            sharedSecret: "test-double-start"
        )

        try server.start()
        // Second start should be a no-op (guard listener == nil)
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    func testServerStopCleansUp() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19446,
            sharedSecret: "test-stop-cleanup"
        )

        try server.start()
        server.stop()

        // After stop, should be able to start again on same port
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    // MARK: - SPEC-011: unauthenticated idle timeout

    func testUnauthenticatedClientIsDisconnectedAfterIdleTimeout() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19450,
            sharedSecret: "test-idle-timeout",
            idleTimeout: 0.75
        )
        try server.start()
        defer { server.stop() }

        // Slow-loris client: open TCP, never send registration bytes.
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 19450)!)
        let client = NWConnection(to: endpoint, using: .tcp)
        let readyExp = expectation(description: "client-ready")
        client.stateUpdateHandler = { state in
            if case .ready = state { readyExp.fulfill() }
        }
        client.start(queue: .global())
        wait(for: [readyExp], timeout: 5.0)

        // Wait past idle timeout + jitter; server must fire the idle kick.
        let kickDeadline = Date().addingTimeInterval(5.0)
        while server.idleDisconnectCount < 1 && Date() < kickDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertGreaterThanOrEqual(server.idleDisconnectCount, 1, "SPEC-011: unauthenticated client was not kicked by idle timer")
        XCTAssertEqual(server.activeConnectionCount, 0, "SPEC-011: server should have no active clients after idle kick")

        client.cancel()
    }

    func testAuthenticatedClientSurvivesIdleTimeout() throws {
        // SPEC-011: idle timer must NOT fire for clients that registered with an authorized source.
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19452,
            sharedSecret: "test-idle-auth-survives",
            idleTimeout: 0.5
        )
        try server.start()
        defer { server.stop() }

        let crypto = JarvisTunnelCrypto(sharedSecret: "test-idle-auth-survives")
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 19452)!)
        let client = NWConnection(to: endpoint, using: .tcp)
        let readyExp = expectation(description: "client-ready")
        client.stateUpdateHandler = { state in
            if case .ready = state { readyExp.fulfill() }
        }
        client.start(queue: .global())
        wait(for: [readyExp], timeout: 5.0)

        // Register as an authorized source BEFORE idle timeout fires.
        let registration = JarvisClientRegistration(
            deviceID: "dev-1",
            deviceName: "Test",
            platform: "macOS",
            role: "terminal",
            appVersion: "test"
        )
        let message = JarvisTunnelMessage(kind: .register, registration: registration)
        let sealed = try crypto.seal(message)
        let packet = JarvisTransportPacket(origin: "test-client", timestamp: ISO8601DateFormatter().string(from: Date()), payload: sealed)
        let line = try JSONEncoder().encode(packet) + Data([0x0A])
        client.send(content: line, completion: .contentProcessed { _ in })

        // Wait past idle timeout — registered clients must NOT be kicked.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(server.idleDisconnectCount, 0, "SPEC-011: registered client must not be kicked by idle timer")

        client.cancel()
    }

    func testIdleTimeoutIsClampedAboveZero() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)

        // Passing zero or negative must not crash nor fire the timer instantly on a background queue.
        let server = JarvisHostTunnelServer(
            runtime: runtime,
            registry: registry,
            port: 19451,
            sharedSecret: "test-idle-clamp",
            idleTimeout: -5.0
        )
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    // MARK: - SPEC-007: voice-operator requires green voice gate

    func testVoiceOperatorRegistrationRejectedWhenGateNotGreen() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)
        let server = JarvisHostTunnelServer(runtime: runtime, registry: registry, port: 19470, sharedSecret: "spec-007-a")

        let result = server.authorizeRegistrationRole("voice-operator")
        XCTAssertNil(result.role, "SPEC-007: voice-operator must not be granted when gate is not green")
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error?.contains("Voice gate is not green") ?? false)
    }

    func testMobileCockpitRegistrationAcceptedWithoutGateCheck() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)
        let server = JarvisHostTunnelServer(runtime: runtime, registry: registry, port: 19471, sharedSecret: "spec-007-b")

        let result = server.authorizeRegistrationRole("mobile-cockpit")
        XCTAssertEqual(result.role, "mobile-cockpit")
        XCTAssertNil(result.error)
    }

    func testUnknownRoleSilentlyDropped() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)
        let server = JarvisHostTunnelServer(runtime: runtime, registry: registry, port: 19472, sharedSecret: "spec-007-c")

        let result = server.authorizeRegistrationRole("rogue-role")
        XCTAssertNil(result.role)
        XCTAssertNil(result.error, "Unknown roles drop silently without error response")
    }

    // MARK: - Transport packet encoding

    func testTransportPacketEncodesOriginAndTimestamp() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let packet = JarvisTransportPacket(
            origin: "jarvis-host",
            timestamp: timestamp,
            payload: "dGVzdA=="  // "test" in base64
        )

        let encoded = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(JarvisTransportPacket.self, from: encoded)

        XCTAssertEqual(decoded.origin, "jarvis-host")
        XCTAssertEqual(decoded.timestamp, timestamp)
        XCTAssertEqual(decoded.payload, "dGVzdA==")
    }

    // MARK: - Message types encode/decode

    func testTunnelMessageKindAllCasesDecode() throws {
        let allKinds: [JarvisTunnelMessageKind] = [.register, .command, .snapshot, .response, .push, .error, .heartbeat]

        for kind in allKinds {
            let message = JarvisTunnelMessage(kind: kind)
            let encoded = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(JarvisTunnelMessage.self, from: encoded)
            XCTAssertEqual(decoded.kind, kind, "Failed to round-trip message kind: \(kind.rawValue)")
        }
    }

    func testRemoteActionAllCasesDecode() throws {
        let allActions = JarvisRemoteAction.allCases

        for action in allActions {
            let command = JarvisRemoteCommand(action: action, text: "test-\(action.rawValue)")
            let message = JarvisTunnelMessage(kind: .command, command: command)
            let encoded = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(JarvisTunnelMessage.self, from: encoded)
            XCTAssertEqual(decoded.command?.action, action, "Failed to round-trip action: \(action.rawValue)")
            XCTAssertEqual(decoded.command?.text, "test-\(action.rawValue)")
        }
    }

    // MARK: - Connection state

    func testConnectionStateAllCasesDecode() throws {
        let allStates: [JarvisConnectionState] = [.disconnected, .connecting, .online, .degraded, .failed]

        for state in allStates {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(JarvisConnectionState.self, from: encoded)
            XCTAssertEqual(decoded, state, "Failed to round-trip connection state: \(state.rawValue)")
        }
    }

    // MARK: - Client registration

    func testClientRegistrationRoundTrip() throws {
        let registration = JarvisClientRegistration(
            deviceID: "device-abc123",
            deviceName: "Grizz's iPhone",
            platform: "iOS",
            role: "terminal",
            appVersion: "2.0.1"
        )

        let message = JarvisTunnelMessage(kind: .register, registration: registration)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(JarvisTunnelMessage.self, from: encoded)

        XCTAssertEqual(decoded.registration?.deviceID, "device-abc123")
        XCTAssertEqual(decoded.registration?.deviceName, "Grizz's iPhone")
        XCTAssertEqual(decoded.registration?.platform, "iOS")
        XCTAssertEqual(decoded.registration?.role, "terminal")
        XCTAssertEqual(decoded.registration?.appVersion, "2.0.1")
    }

    // MARK: - Push directive

    func testPushDirectiveRoundTrip() throws {
        let push = JarvisPushDirective(
            id: "push-001",
            title: "Alert",
            body: "Something happened",
            startupLine: "Good morning.",
            requiresSpeech: true,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let message = JarvisTunnelMessage(kind: .push, push: push)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(JarvisTunnelMessage.self, from: encoded)

        XCTAssertEqual(decoded.push?.id, "push-001")
        XCTAssertEqual(decoded.push?.title, "Alert")
        XCTAssertTrue(decoded.push?.requiresSpeech ?? false)
    }

    // MARK: - Spatial HUD element

    func testSpatialHUDElementRoundTrip() throws {
        let element = JarvisSpatialHUDElement(
            id: "hud-001",
            kind: "voice_gate",
            label: "Voice Gate",
            state: .green,
            anchor: .headLocked,
            glyph: "🟢",
            detail: "Approved — emerald green",
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(element)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JarvisSpatialHUDElement.self, from: data)

        XCTAssertEqual(decoded.id, "hud-001")
        XCTAssertEqual(decoded.kind, "voice_gate")
        XCTAssertEqual(decoded.state, .green)
        XCTAssertEqual(decoded.anchor, .headLocked)
        XCTAssertEqual(decoded.glyph, "🟢")
        XCTAssertEqual(decoded.detail, "Approved — emerald green")
    }

    // MARK: - GMRI palette

    func testGMRIPaletteHexValues() {
        XCTAssertEqual(JarvisGMRIPalette.emeraldGreenHex, "#00A86B")
        XCTAssertEqual(JarvisGMRIPalette.silverHex, "#C0C0C0")
        XCTAssertEqual(JarvisGMRIPalette.blackHex, "#0A0A0A")
        XCTAssertEqual(JarvisGMRIPalette.crimsonHex, "#DC143C")
    }

    func testSpatialIndicatorStateMapsToPaletteColors() {
        XCTAssertEqual(JarvisSpatialIndicatorState.green.paletteHex, JarvisGMRIPalette.emeraldGreenHex)
        XCTAssertEqual(JarvisSpatialIndicatorState.yellow.paletteHex, JarvisGMRIPalette.silverHex)
        XCTAssertEqual(JarvisSpatialIndicatorState.orange.paletteHex, JarvisGMRIPalette.silverHex)
        XCTAssertEqual(JarvisSpatialIndicatorState.red.paletteHex, JarvisGMRIPalette.crimsonHex)
        XCTAssertEqual(JarvisSpatialIndicatorState.grey.paletteHex, JarvisGMRIPalette.blackHex)
    }
}