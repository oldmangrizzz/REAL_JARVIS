import XCTest
@testable import JarvisCore

final class TTSBackendDriftTests: XCTestCase {
    private var paths: WorkspacePaths!
    private var telemetry: TelemetryStore!
    private var runner: MockAudioCommandRunner!
    private var playback: MockAudioPlaybackProvider!
    
    override func setUpWithError() throws {
        paths = try makeTestWorkspace()
        telemetry = try TelemetryStore(paths: paths)
        runner = MockAudioCommandRunner()
        playback = MockAudioPlaybackProvider()
    }
    
    private func makeSession(modelRepo: String = "test-model") throws -> VoiceSessionConfiguration {
        let audioURL = paths.voiceSamplesDirectory.appendingPathComponent("ref.wav")
        try FileManager.default.createDirectory(at: paths.voiceSamplesDirectory, withIntermediateDirectories: true)
        try Data("audio-data".utf8).write(to: audioURL)
        let profile = VoiceReferenceProfile(sampleCount: 1, averageDuration: 1.0, averageEnergy: 0.1, averageSampleRate: 44_100)
        return VoiceSessionConfiguration(
            selectedVoice: "test-voice",
            rate: 44_100,
            profile: profile,
            modelRepository: modelRepo,
            referenceAudioURL: audioURL,
            referenceTranscript: "test transcript"
        )
    }
    
    func testPipelineRefusesWhenGateIsAbsent() throws {
        let backend = MockTTSBackend(id: "backend-A")
        let pipeline = JarvisVoicePipeline(paths: paths, telemetry: telemetry, runner: runner, playback: playback, backend: backend)
        let session = try makeSession(modelRepo: "backend-A")
        
        XCTAssertThrowsError(try pipeline.speak(text: "Hello", configuration: session)) { error in
            guard case VoiceApprovalError.notApproved = error else {
                return XCTFail("Expected .notApproved, got \(error)")
            }
        }
    }
    
    func testPipelineDetectsDriftOnModelMismatch() throws {
        let backend = MockTTSBackend(id: "backend-A")
        let gate = VoiceApprovalGate(paths: paths)
        let pipeline = JarvisVoicePipeline(paths: paths, telemetry: telemetry, runner: runner, playback: playback, approvalGate: gate, backend: backend)
        
        // Approve for "model-ORIGINAL"
        let sessionApproved = try makeSession(modelRepo: "model-ORIGINAL")
        try gate.approve(session: sessionApproved, personaFramingVersion: JarvisVoicePipeline.personaFramingVersion, operatorLabel: "grizzly")
        
        // Try to speak with a session that has "model-DRIFTED"
        let sessionDrifted = try makeSession(modelRepo: "model-DRIFTED")
        
        XCTAssertThrowsError(try pipeline.speak(text: "Hello", configuration: sessionDrifted)) { error in
            guard case VoiceApprovalError.drift = error else {
                return XCTFail("Expected .drift, got \(error)")
            }
        }
    }
    
    func testGateRevocationBlocksPipeline() throws {
        let backend = MockTTSBackend(id: "backend-A")
        let session = try makeSession(modelRepo: "backend-A")
        let gate = VoiceApprovalGate(paths: paths)
        try gate.approve(session: session, personaFramingVersion: JarvisVoicePipeline.personaFramingVersion, operatorLabel: "grizzly")
        
        let pipeline = JarvisVoicePipeline(paths: paths, telemetry: telemetry, runner: runner, playback: playback, approvalGate: gate, backend: backend)
        
        // Revoke
        try gate.revoke()
        
        XCTAssertThrowsError(try pipeline.speak(text: "Hello", configuration: session)) { error in
            guard case VoiceApprovalError.notApproved = error else {
                return XCTFail("Expected .notApproved, got \(error)")
            }
        }
    }
}

// MARK: - Mocks

private final class MockTTSBackend: TTSBackend {
    let identifier: String
    let selectedVoiceLabel = "mock-voice"
    let sampleRate = 44_100
    
    init(id: String) {
        self.identifier = id
    }
    
    func synthesize(text: String, referenceAudioURL: URL, referenceTranscript: String, parameters: TTSRenderParameters, outputURL: URL) throws {
        try Data("mock-audio".utf8).write(to: outputURL)
    }
}

private final class MockAudioCommandRunner: AudioCommandRunning {
    func run(_ executable: URL, arguments: [String], currentDirectory: URL?) throws -> String {
        return ""
    }
}

private final class MockAudioPlaybackProvider: AudioPlaybackProviding {
    func play(fileURL: URL) throws {}
}
