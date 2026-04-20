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

    // MARK: - memify edge cases

    func testMemifySkipsNonexistentFiles() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let missing = paths.traceDirectory.appendingPathComponent("does-not-exist.log")
        let result = try runtime.memory.memify(logFileURLs: [missing])
        XCTAssertEqual(result.ingestedFiles, [])
        XCTAssertEqual(result.episodicEdgeCount, 0)
    }

    func testMemifySkipsEmptyWhitespaceOnlyFiles() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let empty = paths.traceDirectory.appendingPathComponent("blank.log")
        try "   \n\n\t  \n".write(to: empty, atomically: true, encoding: .utf8)
        let result = try runtime.memory.memify(logFileURLs: [empty])
        XCTAssertEqual(result.ingestedFiles, [])
    }

    func testMemifyPersistsAcrossReopen() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let logURL = paths.traceDirectory.appendingPathComponent("persist.log")
        try "Jarvis observed a regression in the embedding routine during the nightly replay.".write(
            to: logURL, atomically: true, encoding: .utf8
        )
        _ = try runtime.memory.memify(logFileURLs: [logURL])
        let nodesBefore = runtime.memory.graph.nodes.count
        XCTAssertGreaterThan(nodesBefore, 0)

        // New runtime points at same workspace → should decode persisted graph.
        let runtime2 = try JarvisRuntime(paths: paths)
        XCTAssertEqual(runtime2.memory.graph.nodes.count, nodesBefore,
                       "graph must round-trip through persist/loadPersistedState")
    }

    // MARK: - retrieveRanked (pure-read path)

    func testRetrieveRankedIsPureReadAndReturnsScoresDescending() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let logURL = paths.traceDirectory.appendingPathComponent("tick.log")
        try "Oscillator ticked; phase-lock monitor reported healthy PLV for the responder channel.".write(
            to: logURL, atomically: true, encoding: .utf8
        )
        _ = try runtime.memory.memify(logFileURLs: [logURL])

        // Snapshot working context BEFORE retrieval.
        let contextBefore = runtime.memory.mainContext.workingContext
        let fifoBefore = runtime.memory.mainContext.fifoQueue

        let ranked = runtime.memory.retrieveRanked(query: "phase-lock healthy", limit: 5)
        XCTAssertFalse(ranked.isEmpty)
        let scores = ranked.map(\.score)
        XCTAssertEqual(scores, scores.sorted(by: >),
                       "retrieveRanked must return descending scores")
        XCTAssertTrue(scores.allSatisfy { $0 > 0 },
                      "filter { > 0 } must exclude zero-similarity nodes")

        // NOT mutate state — unlike pageIn.
        XCTAssertEqual(runtime.memory.mainContext.workingContext, contextBefore)
        XCTAssertEqual(runtime.memory.mainContext.fifoQueue, fifoBefore)
    }

    func testRetrieveRankedWithZeroLimitReturnsEmpty() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        XCTAssertEqual(runtime.memory.retrieveRanked(query: "anything", limit: 0).count, 0)
    }

    // MARK: - pageIn mutates working context + FIFO

    func testPageInMutatesWorkingContextAndFIFO() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let logURL = paths.traceDirectory.appendingPathComponent("seed.log")
        try "Memify seed entry for FIFO page-in test.".write(to: logURL, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [logURL])

        _ = try runtime.memory.pageIn(query: "seed entry", limit: 2)
        XCTAssertEqual(runtime.memory.mainContext.workingContext["lastPagedQuery"], "seed entry")
        XCTAssertTrue(runtime.memory.mainContext.fifoQueue.contains("seed entry"))
    }

    func testPageInFIFOBoundedAt8Entries() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let logURL = paths.traceDirectory.appendingPathComponent("seed.log")
        try "Seed text for bound test.".write(to: logURL, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [logURL])

        for i in 0..<12 {
            _ = try runtime.memory.pageIn(query: "q-\(i)", limit: 1)
        }
        XCTAssertLessThanOrEqual(runtime.memory.mainContext.fifoQueue.count, 8,
                                 "FIFO must be bounded at 8 entries")
        XCTAssertEqual(runtime.memory.mainContext.fifoQueue.last, "q-11")
    }

    // MARK: - recordSomaticPath

    func testRecordSomaticPathCreatesSomaticEdge() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let edge = EdgeKey(source: "alpha", target: "beta")
        try runtime.memory.recordSomaticPath(edge: edge, weight: 0.77)
        let match = runtime.memory.graph.edges.first {
            $0.source == "alpha" && $0.target == "beta" && $0.relation == "somatic"
        }
        XCTAssertEqual(match?.weight, 0.77)
        XCTAssertNotNil(match?.timestamp)
    }
}

