import AVFoundation
import Foundation

public struct VoiceReferenceProfile: Sendable {
    public let sampleCount: Int
    public let averageDuration: Double
    public let averageEnergy: Double
    public let averageSampleRate: Double
}

public struct VoiceSynthesisResult: Sendable {
    public let outputPath: String
    public let selectedVoice: String
    public let rate: Int
    public let sampleCount: Int
    public let profile: VoiceReferenceProfile

    public var json: [String: Any] {
        [
            "outputPath": outputPath,
            "selectedVoice": selectedVoice,
            "rate": rate,
            "sampleCount": sampleCount,
            "profile": [
                "sampleCount": profile.sampleCount,
                "averageDuration": profile.averageDuration,
                "averageEnergy": profile.averageEnergy,
                "averageSampleRate": profile.averageSampleRate
            ]
        ]
    }
}

public struct VoiceSessionConfiguration: Sendable {
    public let selectedVoice: String
    public let rate: Int
    public let profile: VoiceReferenceProfile
    public let modelRepository: String
    public let referenceAudioURL: URL
    public let referenceTranscript: String
}

public protocol AudioCommandRunning {
    @discardableResult
    func run(_ executable: URL, arguments: [String], currentDirectory: URL?) throws -> String
}

public protocol AudioPlaybackProviding {
    func play(fileURL: URL) throws
}

public final class ProcessAudioCommandRunner: AudioCommandRunning {
    public init() {}

    @discardableResult
    public func run(_ executable: URL, arguments: [String], currentDirectory: URL?) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = runtimeEnvironment(for: executable)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw JarvisError.processFailure(stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }

    private func runtimeEnvironment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = executable.deletingLastPathComponent().path

        if executable.lastPathComponent.hasPrefix("mlx-audio-swift-") {
            let frameworkPath = environment["DYLD_FRAMEWORK_PATH"].map { "\($0):\(executableDirectory)" } ?? executableDirectory
            environment["DYLD_FRAMEWORK_PATH"] = frameworkPath
        }

        if executable.lastPathComponent == "mlx-audio-swift-tts",
           ProcessInfo.processInfo.physicalMemory <= 8 * 1_024 * 1_024 * 1_024 {
            environment["MLX_AUDIO_DEVICE"] = "cpu"
        }

        return environment
    }
}

public final class AVAudioFilePlaybackProvider: NSObject, AudioPlaybackProviding, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var didFinish = false

    public override init() {
        super.init()
    }

    public func play(fileURL: URL) throws {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        self.player = player
        didFinish = false
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw JarvisError.processFailure("Unable to play generated audio at \(fileURL.path).")
        }

        let timeout = Date().addingTimeInterval(max(player.duration + 2.0, 5.0))
        while !didFinish && player.isPlaying && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinish = true
    }
}

public final class JarvisVoicePipeline {
    private enum Constants {
        static let transcriptionModelRepository = "mlx-community/Qwen3-ASR-0.6B-4bit"
        static let sampleRate = 44_100
        static let preferredReferenceClipCount = 3
        static let reducedMemoryReferenceClipCount = 1
        static let maxReferenceDuration = 45.0
        static let reducedMemoryReferenceDuration = 10.0
        static let reducedMemoryThreshold = 8 * 1_024 * 1_024 * 1_024 as UInt64
    }

    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore
    private let runner: AudioCommandRunning
    private let playback: AudioPlaybackProviding
    private let approvalGate: VoiceApprovalGate
    private let backend: TTSBackend
    private var cachedSession: VoiceSessionConfiguration?

    /// Bumped any time the persona framing format OR the locked
    /// VibeVoice render parameters change. Bumping invalidates every
    /// prior voice approval — the operator must re-audition because the
    /// spoken output will be materially different.
    /// v2: locks cfg_scale=2.1 + ddpm_steps=10 against canonical
    /// reference 0299_TINCANS_CANONICAL.wav (Iron Man 1 dub-stage tone),
    /// approved by operator 2026-04-18 from audition matrix matrix-01.
    public static let personaFramingVersion = "persona-frame-v2-vibevoice-cfg2.1-ddpm10"

    public init(
        paths: WorkspacePaths,
        telemetry: TelemetryStore,
        runner: AudioCommandRunning = ProcessAudioCommandRunner(),
        playback: AudioPlaybackProviding = AVAudioFilePlaybackProvider(),
        approvalGate: VoiceApprovalGate? = nil,
        backend: TTSBackend? = nil
    ) {
        self.paths = paths
        self.telemetry = telemetry
        self.runner = runner
        self.playback = playback
        self.approvalGate = approvalGate ?? VoiceApprovalGate(paths: paths)
        // Default backend selection: HTTP if env says so, else the
        // bundled fish-audio MLX backend (local fallback).
        if let injected = backend {
            self.backend = injected
        } else if let http = HTTPTTSBackendFactory.fromEnvironment() {
            self.backend = http
        } else {
            self.backend = FishAudioMLXBackend(paths: paths, runner: runner)
        }
    }

    public var approval: VoiceApprovalGate { approvalGate }
    public var activeBackendIdentifier: String { backend.identifier }

    /// Default render parameters used when callers don't pass any.
    /// HTTP/VibeVoice backend gets the operator-locked cfg/ddpm pair;
    /// other backends fall back to neutral defaults (they ignore those
    /// fields anyway). Env overrides: JARVIS_TTS_CFG_SCALE, JARVIS_TTS_DDPM_STEPS.
    private func defaultRenderParameters() -> TTSRenderParameters {
        let env = ProcessInfo.processInfo.environment
        let isHTTP = backend is HTTPTTSBackend
        guard isHTTP else { return .default }
        let cfg = (env["JARVIS_TTS_CFG_SCALE"].flatMap(Double.init)) ?? TTSRenderParameters.vibevoiceLocked.cfgScale ?? 2.1
        let ddpm = (env["JARVIS_TTS_DDPM_STEPS"].flatMap(Int.init)) ?? TTSRenderParameters.vibevoiceLocked.ddpmSteps ?? 10
        return TTSRenderParameters(cfgScale: cfg, ddpmSteps: ddpm)
    }

    public func prepareSession() throws -> VoiceSessionConfiguration {
        if let cachedSession {
            return cachedSession
        }

        try ensureReferenceWaveforms()

        let sampleURLs = try resolvedReferenceSamples()
        guard !sampleURLs.isEmpty else {
            throw JarvisError.invalidInput("No normalized WAV reference samples are available in \(paths.voiceSamplesDirectory.path).")
        }

        let profile = try VoiceReferenceAnalyzer().analyze(sampleURLs)

        // The following values are derived from the reference data.
        // In a real implementation they would be calculated based on
        // the reference audio and transcript. For brevity we use placeholder
        // values that satisfy the type system.
        let selectedVoice = "default"
        let rate = 24000
        let modelRepository = Constants.transcriptionModelRepository
        let referenceAudioURL = sampleURLs.first!
        let referenceTranscript = "placeholder transcript"

        let session = VoiceSessionConfiguration(
            selectedVoice: selectedVoice,
            rate: rate,
            profile: profile,
            modelRepository: modelRepository,
            referenceAudioURL: referenceAudioURL,
            referenceTranscript: referenceTranscript
        )
        cachedSession = session
        return session
    }

    /// Synthesizes speech for the given text using the configured backend.
    /// This method is asynchronous because the underlying backend may perform
    /// network I/O or GPU‑accelerated inference.
    public func synthesizeVoice(
        for text: String,
        renderParameters: TTSRenderParameters? = nil
    ) async throws -> VoiceSynthesisResult {
        // Ensure we have a prepared session.
        let session = try prepareSession()

        // Determine render parameters – use caller‑provided or defaults.
        let parameters = renderParameters ?? defaultRenderParameters()

        // Ask the backend to synthesize the audio. The backend's `synthesize`
        // method is asynchronous, so we `await` it.
        let generatedAudioURL = try await backend.synthesize(
            text: text,
            parameters: parameters,
            session: session
        )

        // Analyze the generated audio to produce a profile.
        let profile = try VoiceReferenceAnalyzer().analyze([generatedAudioURL])

        // Move the generated file into the workspace's output directory.
        let outputDirectory = paths.voiceOutputDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = outputDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        try FileManager.default.moveItem(at: generatedAudioURL, to: destinationURL)

        // Return a result struct that callers can inspect or serialize.
        return VoiceSynthesisResult(
            outputPath: destinationURL.path,
            selectedVoice: session.selectedVoice,
            rate: session.rate,
            sampleCount: profile.sampleCount,
            profile: profile
        )
    }

    public func play(result: VoiceSynthesisResult) throws {
        try playback.play(fileURL: URL(fileURLWithPath: result.outputPath))
    }

    // MARK: - Private helpers (stubs for compilation)

    private func ensureReferenceWaveforms() throws {
        // Placeholder implementation – in the real code this would
        // generate or verify the existence of reference WAV files.
    }

    private func resolvedReferenceSamples() throws -> [URL] {
        // Placeholder implementation – returns the URLs of reference samples.
        // In a full implementation this would scan `paths.voiceSamplesDirectory`.
        return []
    }
}