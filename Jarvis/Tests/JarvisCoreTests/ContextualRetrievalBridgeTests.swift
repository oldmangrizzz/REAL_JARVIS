import XCTest
@testable import JarvisCore

final class ContextualRetrievalBridgeTests: XCTestCase {
    private func makeBridge(_ runtime: JarvisRuntime) -> ContextualRetrievalBridge {
        ContextualRetrievalBridge(memory: runtime.memory, pheromind: runtime.pheromind)
    }

    func testRuntimeExposesSharedBridge() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let url = paths.traceDirectory.appendingPathComponent("wired.log")
        try "Runtime wires retrieval across memory and pheromone.".write(to: url, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [url])

        let ctx = runtime.retrievalBridge.retrieve(query: "retrieval memory pheromone", limit: 3)
        XCTAssertFalse(ctx.semanticMatches.isEmpty)
    }

    func testQueryWithContextEnrichesPromptViaBridge() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let url = paths.traceDirectory.appendingPathComponent("enrich.log")
        try """
        Planning phase defines the architecture.
        Validation phase proves the build is sound.
        """.write(to: url, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [url])

        let result = try runtime.pythonRLM.queryWithContext(
            basePrompt: "Select the phase that proves build soundness.",
            query: "validation phase",
            retrieval: runtime.retrievalBridge,
            limit: 3
        )
        XCTAssertFalse(result.trace.isEmpty)
        XCTAssertFalse(result.response.isEmpty)
    }

    private func memifyFixture(_ runtime: JarvisRuntime, paths: WorkspacePaths, name: String, content: String) throws {
        let url = paths.traceDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        _ = try runtime.memory.memify(logFileURLs: [url])
    }

    func testRetrieveOnEmptyMemoryReturnsEmptyContext() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let bridge = makeBridge(runtime)

        let ctx = bridge.retrieve(query: "anything", limit: 4)

        XCTAssertEqual(ctx.query, "anything")
        XCTAssertTrue(ctx.semanticMatches.isEmpty)
        XCTAssertTrue(ctx.pheromonePaths.isEmpty)
        XCTAssertTrue(ctx.isEmpty)
    }

    func testRetrieveReturnsSemanticMatchesAfterMemify() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "deploy.log",
                          content: "Deployment failed because the database migration was skipped.")
        let bridge = makeBridge(runtime)

        let ctx = bridge.retrieve(query: "database migration", limit: 3)

        XCTAssertFalse(ctx.semanticMatches.isEmpty)
        XCTAssertTrue(ctx.semanticMatches.allSatisfy { $0.score > 0.0 })
        XCTAssertTrue(ctx.semanticMatches.first?.text.lowercased().contains("migration") ?? false)
    }

    func testRetrieveRespectsLimit() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "multi.log",
                          content: """
                          Alpha deployed the kernel pipeline.
                          Beta ran validation against the kernel pipeline.
                          Gamma archived kernel pipeline traces.
                          """)
        let bridge = makeBridge(runtime)

        let ctx = bridge.retrieve(query: "kernel pipeline", limit: 2)

        XCTAssertLessThanOrEqual(ctx.semanticMatches.count, 2)
    }

    func testRetrieveZeroLimitReturnsEmpty() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "log.log", content: "populated memory graph.")
        let bridge = makeBridge(runtime)

        let ctx = bridge.retrieve(query: "populated", limit: 0)

        XCTAssertTrue(ctx.isEmpty)
    }

    func testRetrieveIncludesPheromonePathsSeededFromSemanticMatches() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "notes.log",
                          content: "Stigmergic regulation stabilizes pheromone decay through feedback.")
        let bridge = makeBridge(runtime)

        let seed = runtime.memory.retrieveRanked(query: "stigmergic regulation", limit: 1).first
        let seedID = try XCTUnwrap(seed?.node.id)

        let edge = EdgeKey(source: seedID, target: "next-action-validate")
        runtime.pheromind.register(edge: edge)
        _ = try runtime.pheromind.applyGlobalUpdate(deposits: [
            PheromoneDeposit(edge: edge, signal: .reinforce, magnitude: 1.0,
                             agentID: "test-agent", timestamp: Date())
        ])

        let ctx = bridge.retrieve(query: "stigmergic regulation", limit: 3)

        XCTAssertFalse(ctx.pheromonePaths.isEmpty)
        let path = try XCTUnwrap(ctx.pheromonePaths.first)
        XCTAssertEqual(path.source, seedID)
        XCTAssertEqual(path.target, "next-action-validate")
        XCTAssertGreaterThan(path.pheromone, 0.0)
    }

    func testPheromonePathsSortedByCombinedWeight() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "two.log",
                          content: """
                          Alpha block discusses the planning phase of orchestration.
                          Beta block discusses the validation phase of orchestration.
                          """)
        let bridge = makeBridge(runtime)

        let ranked = runtime.memory.retrieveRanked(query: "orchestration phase", limit: 2)
        XCTAssertEqual(ranked.count, 2)
        let seedA = ranked[0].node.id
        let seedB = ranked[1].node.id

        let weak = EdgeKey(source: seedA, target: "follow-a")
        let strong = EdgeKey(source: seedB, target: "follow-b")
        runtime.pheromind.register(edge: weak)
        runtime.pheromind.register(edge: strong)
        _ = try runtime.pheromind.applyGlobalUpdate(deposits: [
            PheromoneDeposit(edge: weak, signal: .reinforce, magnitude: 0.2,
                             agentID: "t", timestamp: Date()),
            PheromoneDeposit(edge: strong, signal: .reinforce, magnitude: 1.5,
                             agentID: "t", timestamp: Date())
        ])

        let ctx = bridge.retrieve(query: "orchestration phase", limit: 4)

        XCTAssertEqual(ctx.pheromonePaths.count, 2)
        XCTAssertGreaterThanOrEqual(
            ctx.pheromonePaths[0].combinedWeight,
            ctx.pheromonePaths[1].combinedWeight
        )
        XCTAssertEqual(ctx.pheromonePaths[0].target, "follow-b")
    }

    func testEnrichedPromptFallsBackToBasePromptOnColdMemory() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        let bridge = makeBridge(runtime)

        let enriched = bridge.enrichedPrompt(basePrompt: "Plan the next step.", query: "any")

        XCTAssertEqual(enriched, "Plan the next step.")
    }

    func testEnrichedPromptIncludesStructuredHeader() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "hdr.log",
                          content: "Validation phase confirms the deployment is healthy.")
        let bridge = makeBridge(runtime)

        let enriched = bridge.enrichedPrompt(basePrompt: "Decide next action.", query: "validation")

        XCTAssertTrue(enriched.contains("## Retrieved Context"))
        XCTAssertTrue(enriched.contains("Query: validation"))
        XCTAssertTrue(enriched.contains("### Semantic memories"))
        XCTAssertTrue(enriched.contains("## Prompt"))
        XCTAssertTrue(enriched.contains("Decide next action."))
    }

    func testRetrieveHasNoSideEffectsOnMainContext() throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        try memifyFixture(runtime, paths: paths, name: "side.log",
                          content: "Side-effect free retrieval must not mutate FIFO.")
        let bridge = makeBridge(runtime)

        let baselineFIFO = runtime.memory.mainContext.fifoQueue
        _ = bridge.retrieve(query: "side-effect", limit: 3)
        _ = bridge.enrichedPrompt(basePrompt: "x", query: "side-effect")

        XCTAssertEqual(runtime.memory.mainContext.fifoQueue, baselineFIFO)
        XCTAssertNil(runtime.memory.mainContext.workingContext["lastPagedQuery"])
    }
}
