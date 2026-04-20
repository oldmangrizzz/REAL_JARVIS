import XCTest
@testable import JarvisCore

final class VoiceCommandRouterTests: XCTestCase {
    func testRouterHandlesStatusAndShutdownCommands() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)
        let router = VoiceCommandRouter(runtime: runtime, registry: registry)

        let status = try XCTUnwrap(router.route(transcript: "Jarvis status"))
        XCTAssertTrue(status.spokenText.lowercased().contains("systems are online"))
        XCTAssertFalse(status.shouldShutdown)

        let shutdown = try XCTUnwrap(router.route(transcript: "Jarvis shutdown"))
        XCTAssertTrue(shutdown.shouldShutdown)
    }

    func testStartupLineIncludesOperationalSummary() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let registry = try JarvisSkillRegistry(paths: paths)
        let interface = RealJarvisInterface(runtime: runtime)

        let line = try interface.startupLine(registry: registry)

        XCTAssertTrue(line.contains("J.A.R.V.I.S. is online"))
        XCTAssertTrue(line.contains("native runtime skills"))
    }

    // MARK: - SPEC-004: IntentParser → CapabilityRegistry → DisplayCommandExecutor wiring

    func testRouterDispatchesDisplayIntentViaExecutor() throws {
        let router = try makeFullyWiredRouter()

        let response = try XCTUnwrap(
            router.route(transcript: "Jarvis put the HUD on the left monitor")
        )

        XCTAssertFalse(response.shouldShutdown)
        XCTAssertEqual(response.details["command"] as? String, "display-action")
        XCTAssertEqual(response.details["display"] as? String, "left-monitor")
        XCTAssertEqual(response.details["action"] as? String, "display-dashboard")
        XCTAssertTrue(response.details["success"] as? Bool ?? false)
    }

    func testRouterDispatchesHomeKitIntentViaExecutor() throws {
        let router = try makeFullyWiredRouter()

        let response = try XCTUnwrap(
            router.route(transcript: "Jarvis turn on the kitchen lights")
        )

        XCTAssertEqual(response.details["command"] as? String, "homekit-control")
        XCTAssertEqual(response.details["accessory"] as? String, "kitchen-lights")
        XCTAssertTrue(response.details["success"] as? Bool ?? false)
    }

    func testRouterFallsBackToLegacyForUnmappedIntent() throws {
        let router = try makeFullyWiredRouter()

        let response = try XCTUnwrap(router.route(transcript: "Jarvis status"))

        XCTAssertTrue(response.spokenText.lowercased().contains("systems are online"))
        XCTAssertEqual(response.details["command"] as? String, "status")
    }

    // MARK: - Helpers

    private func makeFullyWiredRouter() throws -> VoiceCommandRouter {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let skillRegistry = try JarvisSkillRegistry(paths: paths)
        let capabilityRegistry = try CapabilityRegistry(configURL: paths.capabilityConfigURL)
        let intentParser = IntentParser(capabilityRegistry: capabilityRegistry)
        let executor = DisplayCommandExecutor(
            registry: capabilityRegistry,
            controlPlane: runtime.controlPlane,
            telemetry: runtime.telemetry
        )
        return VoiceCommandRouter(
            runtime: runtime,
            registry: skillRegistry,
            intentParser: intentParser,
            displayExecutor: executor,
            capabilityRegistry: capabilityRegistry
        )
    }
}
