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
}
