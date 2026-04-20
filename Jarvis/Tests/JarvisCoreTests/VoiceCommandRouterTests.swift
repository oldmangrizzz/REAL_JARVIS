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

    // MARK: - SPEC-008: guardrails

    func testBlockedPatternReturnsUnknownWithZeroConfidence() throws {
        let paths = try makeTestWorkspace()
        let capabilityRegistry = try CapabilityRegistry(configURL: paths.capabilityConfigURL)
        let parser = IntentParser(capabilityRegistry: capabilityRegistry)

        for phrase in ["Jarvis burn everything", "jarvis delete all files", "jarvis disable safety"] {
            let parsed = parser.parse(transcript: phrase)
            XCTAssertEqual(parsed.confidence, 0.0, "SPEC-008: blocked phrase '\(phrase)' must be zero confidence")
            if case .unknown = parsed.intent {} else {
                XCTFail("SPEC-008: blocked phrase '\(phrase)' must map to .unknown")
            }
        }
    }

    func testRateLimiterRefusesBurstOverCapacity() throws {
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
        let limiter = CommandRateLimiter(capacity: 2, window: 60)
        let router = VoiceCommandRouter(
            runtime: runtime,
            registry: skillRegistry,
            intentParser: intentParser,
            displayExecutor: executor,
            capabilityRegistry: capabilityRegistry,
            rateLimiter: limiter
        )

        _ = try router.route(transcript: "Jarvis turn on the kitchen lights")
        _ = try router.route(transcript: "Jarvis turn on the kitchen lights")
        let refused = try XCTUnwrap(router.route(transcript: "Jarvis turn on the kitchen lights"))
        XCTAssertEqual(refused.spokenText, CommandRateLimiter.limitExceededResponse)
        XCTAssertEqual(refused.details["refused"] as? String, "rate_limited")
    }

    // MARK: - SPEC-004: every verb flows through IntentParser → handler chain

    func testRouterHandlesListSkillsViaIntentChain() throws {
        let router = try makeFullyWiredRouter()
        let response = try XCTUnwrap(router.route(transcript: "Jarvis list skills"))
        XCTAssertEqual(response.details["command"] as? String, "list-skills")
        XCTAssertFalse(response.shouldShutdown)
    }

    func testRouterHandlesSelfHealViaIntentChain() throws {
        let router = try makeFullyWiredRouter()
        let response = try XCTUnwrap(router.route(transcript: "Jarvis self heal"))
        // Handler either reports a mutation or a stable-harness line; both
        // are acceptable outcomes — we just need it to route cleanly.
        XCTAssertFalse(response.shouldShutdown)
        XCTAssertFalse(response.spokenText.isEmpty)
    }

    func testRouterHandlesShutdownViaIntentChain() throws {
        let router = try makeFullyWiredRouter()
        let response = try XCTUnwrap(router.route(transcript: "Jarvis go quiet"))
        XCTAssertTrue(response.shouldShutdown)
        XCTAssertEqual(response.details["command"] as? String, "shutdown")
    }

    func testBlockedPatternIsRefusedAtRouter() throws {
        let router = try makeFullyWiredRouter()
        let response = try XCTUnwrap(router.route(transcript: "Jarvis delete all files"))
        XCTAssertEqual(response.details["command"] as? String, "blocked")
        XCTAssertFalse(response.shouldShutdown)
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
