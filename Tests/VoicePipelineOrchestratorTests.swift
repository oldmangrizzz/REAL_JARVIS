import XCTest
@testable import VoicePipeline

// MARK: - Mock Implementations

final class MockSTT: SpeechToText {
    var shouldFail = false
    var receivedAudio: Data?
    var onTranscribe: ((Data) -> Void)?
    
    func transcribe(_ audio: Data, completion: @escaping (Result<String, Error>) -> Void) {
        receivedAudio = audio
        if shouldFail {
            completion(.failure(NSError(domain: "STTError", code: -1, userInfo: nil)))
        } else {
            completion(.success("transcribed text"))
        }
    }
}

final class MockTTS: TextToSpeech {
    var shouldFail = false
    var receivedText: String?
    var onSynthesize: ((String) -> Void)?
    
    func synthesize(_ text: String, completion: @escaping (Result<Data, Error>) -> Void) {
        receivedText = text
        if shouldFail {
            completion(.failure(NSError(domain: "TTSError", code: -1, userInfo: nil)))
        } else {
            completion(.success(Data(text.utf8)))
        }
    }
}

final class MockGate: VoiceGate {
    var shouldAllow = true
    var deniedReason: String?
    
    func authorize(request: VoiceRequest) -> Bool {
        return shouldAllow
    }
    
    func denialReason() -> String? {
        return deniedReason
    }
}

final class MockTelemetry: Telemetry {
    var events: [String] = []
    var expectations: [String: XCTestExpectation] = [:]
    
    func record(event: String) {
        events.append(event)
        expectations[event]?.fulfill()
    }
    
    func expect(event: String, testCase: XCTestCase) -> XCTestExpectation {
        let exp = testCase.expectation(description: "Telemetry event: \(event)")
        expectations[event] = exp
        return exp
    }
}

final class MockWatchGateway: WatchGateway {
    var receivedFrames: [AmbientAudioFrame] = []
    var onSend: ((AmbientAudioFrame) -> Void)?
    
    func send(frame: AmbientAudioFrame) {
        receivedFrames.append(frame)
        onSend?(frame)
    }
}

// MARK: - Test Suite

final class VoicePipelineOrchestratorTests: XCTestCase {
    
    var orchestrator: VoicePipelineOrchestrator!
    var primarySTT: MockSTT!
    var fallbackSTT: MockSTT!
    var primaryTTS: MockTTS!
    var fallbackTTS: MockTTS!
    var gate: MockGate!
    var telemetry: MockTelemetry!
    var watchGateway: MockWatchGateway!
    
    override func setUp() {
        super.setUp()
        primarySTT = MockSTT()
        fallbackSTT = MockSTT()
        primaryTTS = MockTTS()
        fallbackTTS = MockTTS()
        gate = MockGate()
        telemetry = MockTelemetry()
        watchGateway = MockWatchGateway()
        
        orchestrator = VoicePipelineOrchestrator(
            primarySTT: primarySTT,
            fallbackSTT: fallbackSTT,
            primaryTTS: primaryTTS,
            fallbackTTS: fallbackTTS,
            gate: gate,
            telemetry: telemetry,
            watchGateway: watchGateway
        )
    }
    
    // MARK: - Stage Ordering
    
    func testStageOrdering() {
        let orderExpectation = expectation(description: "Stages executed in correct order")
        orderExpectation.expectedFulfillmentCount = 4 // auth, stt, tts, watch
        
        // Spy on telemetry to capture stage events
        let authExp = telemetry.expect(event: "GateAuthorized", testCase: self)
        let sttExp = telemetry.expect(event: "STTCompleted", testCase: self)
        let ttsExp = telemetry.expect(event: "TTSCompleted", testCase: self)
        let watchExp = telemetry.expect(event: "WatchSent", testCase: self)
        
        // Run pipeline
        orchestrator.process(request: VoiceRequest(audio: Data([0x00, 0x01]))) { _ in
            orderExpectation.fulfill()
        }
        
        wait(for: [authExp, sttExp, ttsExp, watchExp, orderExpectation], timeout: 2.0, enforceOrder: true)
    }
    
    // MARK: - STT Failover
    
    func testSTTFailover() {
        primarySTT.shouldFail = true
        fallbackSTT.shouldFail = false
        
        let fallbackUsedExp = expectation(description: "Fallback STT used")
        fallbackSTT.onTranscribe = { _ in fallbackUsedExp.fulfill() }
        
        orchestrator.process(request: VoiceRequest(audio: Data([0xAA, 0xBB]))) { result in
            // success expected via fallback
            if case .success(let text) = result, text == "transcribed text" {
                // ok
            } else {
                XCTFail("Expected successful transcription via fallback")
            }
        }
        
        wait(for: [fallbackUsedExp], timeout: 2.0)
    }
    
    // MARK: - TTS Failover
    
    func testTTSFailover() {
        primaryTTS.shouldFail = true
        fallbackTTS.shouldFail = false
        
        let fallbackUsedExp = expectation(description: "Fallback TTS used")
        fallbackTTS.onSynthesize = { _ in fallbackUsedExp.fulfill() }
        
        orchestrator.process(request: VoiceRequest(audio: Data([0x11, 0x22]))) { result in
            // success expected via fallback
            if case .success(let data) = result, data == Data("transcribed text".utf8) {
                // ok
            } else {
                XCTFail("Expected successful synthesis via fallback")
            }
        }
        
        wait(for: [fallbackUsedExp], timeout: 2.0)
    }
    
    // MARK: - Gate Denial
    
    func testGateDenialStopsPipeline() {
        gate.shouldAllow = false
        gate.deniedReason = "User not authorized"
        
        let denialExp = expectation(description: "Pipeline aborted due to gate denial")
        orchestrator.process(request: VoiceRequest(audio: Data())) { result in
            if case .failure(let error as VoicePipelineError) = result,
               case .gateDenied(let reason) = error,
               reason == "User not authorized" {
                denialExp.fulfill()
            } else {
                XCTFail("Expected gate denial error")
            }
        }
        
        wait(for: [denialExp], timeout: 2.0)
    }
    
    // MARK: - Ambient Frame Authentication
    
    func testAmbientFrameAuthentication() {
        // Simulate an ambient frame that requires authentication
        let frame = AmbientAudioFrame(payload: Data([0x33, 0x44]), requiresAuth: true)
        watchGateway.onSend = { received in
            XCTAssertTrue(received.requiresAuth, "Ambient frame should retain auth requirement")
        }
        
        let sendExp = expectation(description: "Ambient frame sent")
        watchGateway.onSend = { _ in sendExp.fulfill() }
        
        orchestrator.process(request: VoiceRequest(audio: Data())) { _ in }
        
        wait(for: [sendExp], timeout: 2.0)
    }
    
    // MARK: - Telemetry Sequence
    
    func testTelemetrySequence() {
        let authExp = telemetry.expect(event: "GateAuthorized", testCase: self)
        let sttExp = telemetry.expect(event: "STTCompleted", testCase: self)
        let ttsExp = telemetry.expect(event: "TTSCompleted", testCase: self)
        let watchExp = telemetry.expect(event: "WatchSent", testCase: self)
        let completeExp = telemetry.expect(event: "PipelineCompleted", testCase: self)
        
        orchestrator.process(request: VoiceRequest(audio: Data())) { _ in }
        
        wait(for: [authExp, sttExp, ttsExp, watchExp, completeExp], timeout: 2.0, enforceOrder: true)
    }
    
    // MARK: - Model Fingerprint Re‑approval
    
    func testModelFingerprintReapproval() {
        // Initial fingerprint accepted
        orchestrator.currentModelFingerprint = "fingerprint-123"
        orchestrator.approvedFingerprints = ["fingerprint-123"]
        
        // Change model fingerprint during processing
        orchestrator.modelFingerprintProvider = { "fingerprint-999" }
        
        let reapprovalExp = expectation(description: "Re‑approval triggered for new fingerprint")
        orchestrator.onReapprovalNeeded = {
            reapprovalExp.fulfill()
        }
        
        orchestrator.process(request: VoiceRequest(audio: Data())) { _ in }
        
        wait(for: [reapprovalExp], timeout: 2.0)
    }
}