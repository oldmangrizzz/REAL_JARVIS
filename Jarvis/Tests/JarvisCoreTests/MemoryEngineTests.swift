import XCTest
@testable import JarvisCore

final class MemoryEngineTests: XCTestCase {
    func testMemifyCreatesEpisodicMemoryAndPagesContext() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let logURL = paths.traceDirectory.appendingPathComponent("deploy.log")
        try "2026-04-16 Deployment failed because validation was skipped and the database migration dependency was missing.".write(
            to: logURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try runtime.memory.memify(logFileURLs: [logURL])
        let page = try runtime.memory.pageIn(query: "What happened during deployment?", limit: 3)

        XCTAssertEqual(result.ingestedFiles, ["deploy.log"])
        XCTAssertFalse(page.matches.isEmpty)
        XCTAssertTrue(runtime.memory.graph.edges.contains(where: { $0.relation == "episode" && $0.timestamp != nil }))
    }
}
