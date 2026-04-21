import XCTest
@testable import JarvisCore

final class ConversationEngineTests: XCTestCase {
    private var paths: WorkspacePaths!
    private var runtime: JarvisRuntime!
    private var engine: ConversationEngine!
    private var asr: FakeASR!
    private var llm: FakeLLM!
    private var tts: FakeTTS!

    override func setUpWithError() throws {
        paths = try makeTestWorkspace()
        runtime = try JarvisRuntime(paths: paths)
        asr = FakeASR()
        llm = FakeLLM()
        tts = FakeTTS()
        engine = ConversationEngine(runtime: runtime, asr: asr, llm: llm, tts: tts)
    }

    func testInitialStateIsIdle() throws {
        let session = engine.startSession(principal: .operatorTier)
        XCTAssertEqual(session.state, .idle)
    }

    func testIngestAudioStartsListening() throws {
        let session = engine.startSession(principal: .operatorTier)
        try engine.ingestAudio(frame: Data([0x01]), sessionID: session.id)
        XCTAssertEqual(session.state, .listening)
    }

    func testASRPartialsTriggerPartialUnderstanding() async throws {
        let session = engine.startSession(principal: .operatorTier)
        engine.activate(sessionID: session.id)
        
        asr.emit(text: "Hello", isFinal: false)
        try await Task.sleep(nanoseconds: 100_000_000) // Wait for task processing
        
        XCTAssertEqual(session.state, .partialUnderstanding)
    }

    func testASRFinalTriggersGenerating() async throws {
        let session = engine.startSession(principal: .operatorTier)
        engine.activate(sessionID: session.id)
        
        asr.emit(text: "Hello Jarvis", isFinal: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(session.state, .generating)
    }

    func testBargeInYieldsAndReturnsToListening() async throws {
        let session = engine.startSession(principal: .operatorTier)
        engine.activate(sessionID: session.id)
        
        // Setup state: speaking
        try session.transition(to: .listening)
        try session.transition(to: .partialUnderstanding)
        try session.transition(to: .generating)
        try session.transition(to: .speaking)
        
        try engine.handleBargeIn(sessionID: session.id)
        
        XCTAssertEqual(session.state, .listening)
        XCTAssertTrue(llm.didCancel)
        XCTAssertTrue(tts.didCancel)
    }

    func testIllegalTransitionsAreRejected() throws {
        let session = engine.startSession(principal: .operatorTier)
        XCTAssertThrowsError(try session.transition(to: .speaking))
    }
}

// MARK: - Fakes

private final class FakeASR: StreamingASRBackend, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<ASRHypothesis, Error>.Continuation?
    
    func startStreaming() throws -> AsyncThrowingStream<ASRHypothesis, Error> {
        return AsyncThrowingStream { self.continuation = $0 }
    }
    
    func emit(text: String, isFinal: Bool) {
        continuation?.yield(ASRHypothesis(text: text, isFinal: isFinal, confidence: 1.0))
    }
    
    func feed(audioFrame: Data) throws {}
    func stopStreaming() { continuation?.finish() }
}

private final class FakeLLM: StreamingLLMClient, @unchecked Sendable {
    var didCancel = false
    private var continuation: AsyncThrowingStream<LLMToken, Error>.Continuation?
    func generateStream(prompt: String, principal: Principal) throws -> AsyncThrowingStream<LLMToken, Error> {
        return AsyncThrowingStream { self.continuation = $0 }
    }
    func cancel() { didCancel = true; continuation?.finish() }
}

private final class FakeTTS: StreamingTTSBackend, @unchecked Sendable {
    var didCancel = false
    func synthesizeStream(text: String, referenceAudioURL: URL, referenceTranscript: String, parameters: TTSRenderParameters) throws -> AsyncThrowingStream<TTSAudioChunk, Error> {
        return AsyncThrowingStream { _ in }
    }
    func cancel() { didCancel = true }
}

