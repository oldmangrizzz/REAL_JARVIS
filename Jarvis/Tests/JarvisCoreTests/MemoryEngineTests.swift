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

    // MARK: - Additional coverage

    func testMemifyIngestsMultipleFilesInOneCall() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let a = paths.traceDirectory.appendingPathComponent("a.log")
        let b = paths.traceDirectory.appendingPathComponent("b.log")
        try "Deployment Alpha succeeded with validation_pipeline intact.".write(to: a, atomically: true, encoding: .utf8)
        try "Oscillator Beta reported phase-lock on responder_channel.".write(to: b, atomically: true, encoding: .utf8)

        let result = try runtime.memory.memify(logFileURLs: [a, b])
        XCTAssertEqual(Set(result.ingestedFiles), Set(["a.log", "b.log"]),
                       "both real files must land in ingestedFiles")
        XCTAssertGreaterThanOrEqual(result.episodicEdgeCount, 2,
                                    "each document must emit ≥1 episodic chunk edge")
        XCTAssertEqual(result.nodeCount, runtime.memory.graph.nodes.count)
        XCTAssertEqual(result.edgeCount, runtime.memory.graph.edges.count)
    }

    func testMemifyIsIdempotentOnUnchangedContent() throws {
        // Upsert uses content-hashed doc IDs — the same file memified twice
        // must not grow the graph, otherwise daily memify runs would
        // silently accumulate duplicate nodes.
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let log = paths.traceDirectory.appendingPathComponent("idem.log")
        try "Stable deployment note for idempotency test.".write(to: log, atomically: true, encoding: .utf8)

        _ = try runtime.memory.memify(logFileURLs: [log])
        let nodesAfterFirst = runtime.memory.graph.nodes.count
        let edgesAfterFirst = runtime.memory.graph.edges.count
        XCTAssertGreaterThan(nodesAfterFirst, 0)

        _ = try runtime.memory.memify(logFileURLs: [log])
        XCTAssertEqual(runtime.memory.graph.nodes.count, nodesAfterFirst,
                       "re-memifying identical content must not grow node count")
        XCTAssertEqual(runtime.memory.graph.edges.count, edgesAfterFirst,
                       "re-memifying identical content must not grow edge count")
    }

    func testMemifyCreatesMentionsEdgesForExtractedEntities() throws {
        // The entity extractor picks up CamelCase tokens and *.swift names;
        // every hit must become a "mentions" edge from the document node.
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let log = paths.traceDirectory.appendingPathComponent("mentions.log")
        try "VoiceSynthesis edited in SkillSystem.swift to call OpenAIBackend.".write(
            to: log, atomically: true, encoding: .utf8
        )

        _ = try runtime.memory.memify(logFileURLs: [log])
        let mentions = runtime.memory.graph.edges.filter { $0.relation == "mentions" }
        XCTAssertFalse(mentions.isEmpty, "entity extraction must emit ≥1 mentions edge")
        XCTAssertTrue(mentions.allSatisfy { $0.source.hasPrefix("doc-") },
                      "mentions edges must originate at the document node")
        let entityTexts = mentions
            .compactMap { edge in runtime.memory.graph.nodes.first(where: { $0.id == edge.target })?.text }
        XCTAssertTrue(entityTexts.contains(where: { $0.contains("SkillSystem.swift") }),
                      "*.swift tokens must be extracted as entities")
    }

    func testPageInRespectsLimitBound() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let log = paths.traceDirectory.appendingPathComponent("bounded.log")
        let lines = (0..<10).map { "Entry number \($0) describing the oscillator phase event." }.joined(separator: "\n")
        try lines.write(to: log, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [log])

        let result = try runtime.memory.pageIn(query: "oscillator phase", limit: 3)
        XCTAssertLessThanOrEqual(result.matches.count, 3, "pageIn must not exceed the caller's limit")
        XCTAssertEqual(runtime.memory.mainContext.workingContext["lastPagedMatchCount"],
                       String(result.matches.count),
                       "working-context match count must mirror the returned match count")
        XCTAssertTrue(result.pageFaultTriggered, "pageIn always triggers a page fault")
    }

    func testPageInWritesRecursiveThoughtTelemetry() throws {
        // Telemetry is the witness of record for memory activity — every
        // pageIn call must leave a row in recursive_thoughts with
        // memoryPageFault=true so the evidence corpus can correlate
        // retrieval against downstream responses.
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let log = paths.traceDirectory.appendingPathComponent("witness.log")
        try "Witness entry for telemetry audit.".write(to: log, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [log])

        _ = try runtime.memory.pageIn(query: "witness entry", limit: 2)

        let tableURL = runtime.telemetry.tableURL("recursive_thoughts")
        let data = try Data(contentsOf: tableURL)
        let rows = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            }
        XCTAssertFalse(rows.isEmpty, "pageIn must append at least one recursive_thoughts row")
        XCTAssertTrue(rows.contains(where: { ($0["memoryPageFault"] as? Bool) == true }),
                      "the pageIn row must have memoryPageFault=true")
    }

    func testRetrieveRankedRespectsLimit() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let log = paths.traceDirectory.appendingPathComponent("rank.log")
        let lines = (0..<6).map { "Ranked entry \($0) about the phase oscillator telemetry." }.joined(separator: "\n")
        try lines.write(to: log, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [log])

        let two = runtime.memory.retrieveRanked(query: "phase oscillator", limit: 2)
        XCTAssertLessThanOrEqual(two.count, 2, "limit 2 must cap the result set")
        let huge = runtime.memory.retrieveRanked(query: "phase oscillator", limit: 10_000)
        XCTAssertGreaterThanOrEqual(huge.count, two.count,
                                    "larger limit must not return fewer results")
    }

    func testRecordSomaticPathUpsertsRatherThanDuplicates() throws {
        // Same (source,target,relation) triple must collapse into one edge.
        // Weight follows the upsert(edge:) max-rule — 0.4 must not regress
        // an existing 0.7, and a fresh 0.9 must raise it.
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let edge = EdgeKey(source: "node-x", target: "node-y")

        try runtime.memory.recordSomaticPath(edge: edge, weight: 0.7)
        try runtime.memory.recordSomaticPath(edge: edge, weight: 0.4)
        try runtime.memory.recordSomaticPath(edge: edge, weight: 0.9)

        let somatic = runtime.memory.graph.edges.filter {
            $0.source == "node-x" && $0.target == "node-y" && $0.relation == "somatic"
        }
        XCTAssertEqual(somatic.count, 1, "repeated recordSomaticPath must upsert, not duplicate")
        XCTAssertEqual(try XCTUnwrap(somatic.first).weight, 0.9, accuracy: 1e-9,
                       "upsert must retain the max observed weight (0.9 > 0.7 > 0.4)")
    }
}

