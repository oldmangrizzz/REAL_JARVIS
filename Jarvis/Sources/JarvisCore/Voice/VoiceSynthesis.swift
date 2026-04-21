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

    /// Bumped any time the persona framing format OR the locked TTS
    /// render parameters change. Bumping invalidates every prior voice
    /// approval — the operator must re-audition because the spoken
    /// output will be materially different.
    /// v3: CANON LAW locked 2026-04-21 — Coqui XTTS v2 only (Delta:8787).
    /// Reference 0299_TINCANS_CANONICAL.wav (Derek/Harvard Iron Man dub-stage tone).
    /// Supersedes v2 VibeVoice (sunset per PRINCIPLES.md CANON LAW — VOICE).
    public static let personaFramingVersion = "persona-frame-v3-xtts-v2-delta-8787"

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
    /// HTTP backend gets the operator-locked XTTS v2 canon parameters
    /// (CANON LAW 2026-04-21, PRINCIPLES.md §"CANON LAW — VOICE").
    /// Other backends fall back to neutral defaults. Env overrides:
    /// JARVIS_TTS_CFG_SCALE, JARVIS_TTS_DDPM_STEPS (legacy; XTTS ignores).
    private func defaultRenderParameters() -> TTSRenderParameters {
        let env = ProcessInfo.processInfo.environment
        let isHTTP = backend is HTTPTTSBackend
        guard isHTTP else { return .default }
        let base = TTSRenderParameters.xttsLocked
        let cfg = env["JARVIS_TTS_CFG_SCALE"].flatMap(Double.init) ?? base.cfgScale
        let ddpm = env["JARVIS_TTS_DDPM_STEPS"].flatMap(Int.init) ?? base.ddpmSteps
        return TTSRenderParameters(
            temperature: base.temperature,
            topP: base.topP,
            maxNewTokens: base.maxNewTokens,
            cfgScale: cfg,
            ddpmSteps: ddpm
        )
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

        let profile = try VoiceReferenceAnalyzer().analyze(samples: sampleURLs)
        let selectedSamples = try selectReferenceSamples(from: sampleURLs)
        let mergedReferenceURL = try buildMergedReferenceAudio(from: selectedSamples)

        // Skip the heavy mlx-audio-swift-stt build if the transcript is
        // already cached for this exact reference. This is the common
        // case once the canonical voice is locked.
        let transcriptURL = paths.voiceCacheDirectory
            .appendingPathComponent(mergedReferenceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("txt")
        if !FileManager.default.fileExists(atPath: transcriptURL.path) {
            try buildExecutable(named: "mlx-audio-swift-stt")
        }
        let referenceTranscript = try prepareReferenceTranscript(for: mergedReferenceURL)

        let session = VoiceSessionConfiguration(
            selectedVoice: backend.selectedVoiceLabel,
            rate: backend.sampleRate,
            profile: profile,
            modelRepository: backend.identifier,
            referenceAudioURL: mergedReferenceURL,
            referenceTranscript: referenceTranscript
        )
        cachedSession = session
        return session
    }

    public func synthesize(
        text: String,
        outputURL: URL,
        parameters: TTSRenderParameters? = nil,
        configuration: VoiceSessionConfiguration? = nil
    ) throws -> VoiceSynthesisResult {
        let session = try configuration ?? prepareSession()
        let renderedText = personaFrame(text)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let effectiveParameters = parameters ?? defaultRenderParameters()

        try backend.synthesize(
            text: renderedText,
            referenceAudioURL: session.referenceAudioURL,
            referenceTranscript: session.referenceTranscript,
            parameters: effectiveParameters,
            outputURL: outputURL
        )

        try telemetry.logExecutionTrace(
            workflowID: "voice-synthesis",
            stepID: "render-\(backend.identifier)",
            inputContext: renderedText,
            outputResult: outputURL.path,
            status: "success"
        )

        return VoiceSynthesisResult(
            outputPath: outputURL.path,
            selectedVoice: session.selectedVoice,
            rate: session.rate,
            sampleCount: session.profile.sampleCount,
            profile: session.profile
        )
    }

    @discardableResult
    public func speak(text: String, configuration: VoiceSessionConfiguration? = nil, persistAs outputURL: URL? = nil, workflowID: String = "voice-interface") throws -> VoiceSynthesisResult {
        let session = try configuration ?? prepareSession()
        // HARD GATE: refuse playback unless the operator has auditioned
        // and approved this exact voice-identity fingerprint. Any drift
        // in reference samples, model, transcript, or persona framing
        // invalidates approval. See VoiceApprovalGate and SOUL_ANCHOR.md.
        try approvalGate.requireApproved(
            for: session,
            personaFramingVersion: Self.personaFramingVersion
        )
        let targetURL = outputURL ?? paths.storageDirectory.appendingPathComponent("spoken-\(Int(Date().timeIntervalSince1970)).wav")
        let result = try synthesize(text: text, outputURL: targetURL, configuration: session)
        try playback.play(fileURL: targetURL)
        try telemetry.logExecutionTrace(
            workflowID: workflowID,
            stepID: "mlx-spoken-response",
            inputContext: text,
            outputResult: targetURL.path,
            status: "success"
        )

        return VoiceSynthesisResult(
            outputPath: result.outputPath,
            selectedVoice: session.selectedVoice,
            rate: session.rate,
            sampleCount: session.profile.sampleCount,
            profile: session.profile
        )
    }

    /// Same gate semantics as `speak`, but renders to disk only and
    /// never calls local playback. Used by JarvisVoiceHTTPBridge so
    /// remote clients (Obsidian, etc.) get the WAV without the host Mac
    /// also echoing the audio out its speakers.
    @discardableResult
    public func renderApproved(text: String, configuration: VoiceSessionConfiguration? = nil, persistAs outputURL: URL? = nil, workflowID: String = "voice-interface") throws -> VoiceSynthesisResult {
        let session = try configuration ?? prepareSession()
        try approvalGate.requireApproved(
            for: session,
            personaFramingVersion: Self.personaFramingVersion
        )
        let targetURL = outputURL ?? paths.storageDirectory.appendingPathComponent("spoken-\(Int(Date().timeIntervalSince1970)).wav")
        let result = try synthesize(text: text, outputURL: targetURL, configuration: session)
        try telemetry.logExecutionTrace(
            workflowID: workflowID,
            stepID: "mlx-spoken-response-silent",
            inputContext: text,
            outputResult: targetURL.path,
            status: "success"
        )
        return VoiceSynthesisResult(
            outputPath: result.outputPath,
            selectedVoice: session.selectedVoice,
            rate: session.rate,
            sampleCount: session.profile.sampleCount,
            profile: session.profile
        )
    }

    /// Render an audition clip to disk WITHOUT playing it. Grizz opens
    /// the file himself, on his terms, and decides whether to approve
    /// the voice identity. This is the only legitimate way to introduce
    /// a new voice fingerprint to the gate.
    public struct AuditionToken: Sendable {
        public let outputURL: URL
        public let fingerprint: VoiceIdentityFingerprint
        public let session: VoiceSessionConfiguration
    }

    public func audition(
        text: String,
        outputURL: URL? = nil,
        parameters: TTSRenderParameters? = nil
    ) throws -> AuditionToken {
        let session = try prepareSession()
        let dir = approvalGate.auditionDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = outputURL ?? dir.appendingPathComponent("audition-\(Int(Date().timeIntervalSince1970)).wav")
        let effective = parameters ?? defaultRenderParameters()
        _ = try synthesize(text: text, outputURL: target, parameters: effective)
        let fp = try approvalGate.fingerprint(
            for: session,
            personaFramingVersion: Self.personaFramingVersion
        )
        try telemetry.logExecutionTrace(
            workflowID: "voice-audition",
            stepID: "render-only",
            inputContext: text,
            outputResult: target.path,
            status: "awaiting-operator-approval"
        )
        return AuditionToken(outputURL: target, fingerprint: fp, session: session)
    }

    /// Operator-driven approval. Only call after you (Grizz) have
    /// actually listened to an audition clip off-line and confirmed the
    /// voice is correct. Writes the gate file.
    @discardableResult
    public func approveAudition(operatorLabel: String, notes: String? = nil) throws -> VoiceApprovalRecord {
        let session = try prepareSession()
        return try approvalGate.approve(
            session: session,
            personaFramingVersion: Self.personaFramingVersion,
            operatorLabel: operatorLabel,
            notes: notes
        )
    }

    public func revokeApproval() throws {
        try approvalGate.revoke()
    }

    private func ensureReferenceWaveforms() throws {
        let currentSamples = try paths.audioSampleURLs().filter { $0.pathExtension.lowercased() == "wav" }
        if !currentSamples.isEmpty,
           currentSamples.allSatisfy({ $0.deletingLastPathComponent() == paths.voiceSamplesDirectory }),
           try currentSamples.allSatisfy({ try sampleRate(of: $0) == Constants.sampleRate })
        {
            return
        }

        let fileManager = FileManager.default
        let rootAudio = try fileManager.contentsOfDirectory(at: paths.root, includingPropertiesForKeys: nil)
            .filter { ["mp3", "wav", "m4a", "aiff", "aif"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !rootAudio.isEmpty else {
            throw JarvisError.invalidInput("No local reference audio files were found in the workspace root.")
        }

        for source in rootAudio {
            let destination = paths.voiceSamplesDirectory.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("wav")
            if fileManager.fileExists(atPath: destination.path) {
                continue
            }
            try convertToWaveform(sourceURL: source, destinationURL: destination)
        }
    }

    private func resolvedReferenceSamples() throws -> [URL] {
        return try paths.audioSampleURLs().filter { $0.pathExtension.lowercased() == "wav" }
    }

    private func convertToWaveform(sourceURL: URL, destinationURL: URL) throws {
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        if FileManager.default.isExecutableFile(atPath: ffmpeg.path) {
            _ = try runner.run(
                ffmpeg,
                arguments: ["-y", "-loglevel", "error", "-i", sourceURL.path, "-ac", "1", "-ar", "\(Constants.sampleRate)", destinationURL.path],
                currentDirectory: nil
            )
            return
        }

        let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")
        _ = try runner.run(
            afconvert,
            arguments: ["-f", "WAVE", "-d", "LEI16@\(Constants.sampleRate)", sourceURL.path, destinationURL.path],
            currentDirectory: nil
        )
    }

    private func sampleRate(of url: URL) throws -> Int {
        Int(try AVAudioFile(forReading: url).processingFormat.sampleRate.rounded())
    }

    private func buildExecutable(named name: String) throws {
        if executableURLIfBuilt(named: name) != nil {
            try ensureMetalResourcesAvailable(forExecutableNamed: name)
            return
        }

        let swift = URL(fileURLWithPath: "/usr/bin/env")
        _ = try runner.run(
            swift,
            arguments: ["swift", "build", "-c", "release", "--product", name],
            currentDirectory: paths.mlxAudioPackageDirectory
        )
        try ensureMetalResourcesAvailable(forExecutableNamed: name)
    }

    private func executableURL(named name: String) throws -> URL {
        if let built = executableURLIfBuilt(named: name) {
            return built
        }
        throw JarvisError.processFailure("MLX executable '\(name)' was not found after build.")
    }

    private func executableURLIfBuilt(named name: String) -> URL? {
        let buildRoot = paths.mlxAudioPackageDirectory.appendingPathComponent(".build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: buildRoot.path) else { return nil }

        let fileManager = FileManager.default
        let enumerator = FileManager.default.enumerator(at: buildRoot, includingPropertiesForKeys: [.isRegularFileKey])
        while let item = enumerator?.nextObject() as? URL {
            guard item.lastPathComponent == name else { continue }
            guard item.path.contains("/release/") else { continue }
            guard !item.path.contains(".dSYM/") else { continue }
            guard fileManager.isExecutableFile(atPath: item.path) else { continue }
            return item
        }
        return nil
    }

    private func ensureMetalResourcesAvailable(forExecutableNamed name: String) throws {
        guard let executableURL = executableURLIfBuilt(named: name) else { return }

        let executableDirectory = executableURL.deletingLastPathComponent()
        let expectedBundleURL = executableDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
        let expectedMetallibURL = expectedBundleURL.appendingPathComponent("default.metallib")
        if FileManager.default.fileExists(atPath: expectedMetallibURL.path) {
            return
        }

        guard let sourceBundleURL = locateMetalBundle() else {
            throw JarvisError.processFailure("MLX metal resources are unavailable for \(name).")
        }

        if FileManager.default.fileExists(atPath: expectedBundleURL.path) {
            try FileManager.default.removeItem(at: expectedBundleURL)
        }
        try FileManager.default.copyItem(at: sourceBundleURL, to: expectedBundleURL)
    }

    private func locateMetalBundle() -> URL? {
        let fileManager = FileManager.default
        let searchRoots = [
            paths.mlxAudioPackageDirectory.appendingPathComponent(".build", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Developer", isDirectory: true)
                .appendingPathComponent("Xcode", isDirectory: true)
                .appendingPathComponent("DerivedData", isDirectory: true)
        ]

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            while let item = enumerator?.nextObject() as? URL {
                guard item.lastPathComponent == "mlx-swift_Cmlx.bundle" else { continue }
                let metallibURL = item.appendingPathComponent("default.metallib")
                if fileManager.fileExists(atPath: metallibURL.path) {
                    return item
                }
            }
        }

        return nil
    }

    private func selectReferenceSamples(from samples: [URL]) throws -> [URL] {
        let preferredClipCount = ProcessInfo.processInfo.physicalMemory <= Constants.reducedMemoryThreshold
            ? Constants.reducedMemoryReferenceClipCount
            : Constants.preferredReferenceClipCount
        let maxReferenceDuration = ProcessInfo.processInfo.physicalMemory <= Constants.reducedMemoryThreshold
            ? Constants.reducedMemoryReferenceDuration
            : Constants.maxReferenceDuration
        let analyzed = try samples.map { url in
            (url, try VoiceReferenceAnalyzer().duration(of: url))
        }
        var selected: [URL] = []
        var totalDuration = 0.0

        for (url, duration) in analyzed.sorted(by: { $0.1 > $1.1 }) {
            if selected.count >= preferredClipCount {
                break
            }
            if totalDuration + duration > maxReferenceDuration, !selected.isEmpty {
                continue
            }
            selected.append(url)
            totalDuration += duration
        }

        guard !selected.isEmpty else {
            throw JarvisError.invalidInput("No usable voice reference samples were found.")
        }
        return selected
    }

    private func buildMergedReferenceAudio(from samples: [URL]) throws -> URL {
        let manifest = "\(Constants.sampleRate)|" + samples.map(\.lastPathComponent).joined(separator: "|")
        let key = stableHash(manifest)
        let outputURL = paths.voiceCacheDirectory.appendingPathComponent("reference-\(key).wav")
        if FileManager.default.fileExists(atPath: outputURL.path),
           try sampleRate(of: outputURL) == Constants.sampleRate
        {
            return outputURL
        }

        var merged: [Float] = []
        for sample in samples {
            let data = try VoiceReferenceAnalyzer().monoSamples(from: sample, targetSampleRate: Constants.sampleRate)
            if !merged.isEmpty {
                merged.append(contentsOf: Array(repeating: 0, count: Constants.sampleRate / 4))
            }
            merged.append(contentsOf: data)
        }

        try writeWaveform(samples: merged, sampleRate: Constants.sampleRate, outputURL: outputURL)
        return outputURL
    }

    private func prepareReferenceTranscript(for referenceURL: URL) throws -> String {
        let transcriptURL = paths.voiceCacheDirectory.appendingPathComponent(referenceURL.deletingPathExtension().lastPathComponent).appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: transcriptURL.path) {
            let cached = try String(contentsOf: transcriptURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cached.isEmpty {
                return cached
            }
        }

        let sttExecutable = try executableURL(named: "mlx-audio-swift-stt")
        let outputStem = transcriptURL.deletingPathExtension()
        _ = try runner.run(
            sttExecutable,
            arguments: [
                "--model", Constants.transcriptionModelRepository,
                "--audio", referenceURL.path,
                "--output-path", outputStem.path,
                "--format", "txt"
            ],
            currentDirectory: paths.mlxAudioPackageDirectory
        )

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw JarvisError.processFailure("Reference transcription for \(referenceURL.lastPathComponent) was empty.")
        }
        return transcript
    }

    private func personaFrame(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "[low voice] At your service."
        }
        if trimmed.contains("[") {
            return trimmed
        }
        return "[low voice] \(trimmed)"
    }

    private func writeWaveform(samples: [Float], sampleRate: Int, outputURL: URL) throws {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            throw JarvisError.processFailure("Unable to allocate waveform buffer for \(outputURL.path).")
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw JarvisError.processFailure("Unable to access waveform buffer for \(outputURL.path).")
        }
        for index in samples.indices {
            channelData[0][index] = samples[index]
        }

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try file.write(from: buffer)
    }

    private func stableHash(_ text: String) -> String {
        String(text.unicodeScalars.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1.value) }, radix: 16)
    }

    private func buildMergedReferenceAudioName(for samples: [URL]) -> String {
        let manifest = "\(Constants.sampleRate)|" + samples.map(\.lastPathComponent).joined(separator: "|")
        return "reference-\(stableHash(manifest)).wav"
    }
}

private struct VoiceReferenceAnalyzer {
    func analyze(samples: [URL]) throws -> VoiceReferenceProfile {
        var durations: [Double] = []
        var energies: [Double] = []
        var sampleRates: [Double] = []

        for sample in samples {
            let file = try AVAudioFile(forReading: sample)
            let format = file.processingFormat
            sampleRates.append(format.sampleRate)
            durations.append(Double(file.length) / format.sampleRate)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                continue
            }
            try file.read(into: buffer)
            if let channelData = buffer.floatChannelData?.pointee {
                let frameLength = Int(buffer.frameLength)
                let rms = sqrt((0..<frameLength).reduce(0.0) { partial, index in
                    let sample = Double(channelData[index])
                    return partial + (sample * sample)
                } / Double(max(frameLength, 1)))
                energies.append(rms)
            }
        }

        return VoiceReferenceProfile(
            sampleCount: samples.count,
            averageDuration: durations.average,
            averageEnergy: energies.average,
            averageSampleRate: sampleRates.average
        )
    }

    func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func monoSamples(from url: URL, targetSampleRate: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(targetSampleRate), channels: 1, interleaved: false),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length))
        else {
            throw JarvisError.processFailure("Unable to allocate audio buffers for \(url.path).")
        }

        try file.read(into: sourceBuffer)
        let sourceFrameCount = Int(sourceBuffer.frameLength)
        let monoSource: [Float]

        if sourceFormat.channelCount == 1, let channel = sourceBuffer.floatChannelData?[0] {
            monoSource = Array(UnsafeBufferPointer(start: channel, count: sourceFrameCount))
        } else if let channels = sourceBuffer.floatChannelData {
            let channelCount = Int(sourceFormat.channelCount)
            monoSource = (0..<sourceFrameCount).map { frameIndex in
                let total = (0..<channelCount).reduce(0.0 as Float) { partial, channelIndex in
                    partial + channels[channelIndex][frameIndex]
                }
                return total / Float(channelCount)
            }
        } else {
            throw JarvisError.processFailure("Unable to access audio channel data for \(url.path).")
        }

        if Int(sourceFormat.sampleRate) == targetSampleRate {
            return monoSource
        }

        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceFormat.sampleRate, channels: 1, interleaved: false),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(monoSource.count))
        else {
            throw JarvisError.processFailure("Unable to create mono conversion format for \(url.path).")
        }

        inputBuffer.frameLength = AVAudioFrameCount(monoSource.count)
        // CX-007: replaced unsafe memcpy with bounds-checked copy
        let copyCount = min(monoSource.count, Int(inputBuffer.frameLength))
        guard let channelData = inputBuffer.floatChannelData?[0],
              let sourceBase = monoSource.withUnsafeBufferPointer({ $0.baseAddress }) else {
            throw JarvisError.processFailure("Unable to access audio buffer memory for \(url.path).")
        }
        channelData.initialize(from: sourceBase, count: copyCount)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw JarvisError.processFailure("Unable to create audio converter for \(url.path).")
        }

        let ratio = Double(targetSampleRate) / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(max(1, Int(ceil(Double(monoSource.count) * ratio)) + 64))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw JarvisError.processFailure("Unable to create resampled buffer for \(url.path).")
        }

        final class Provider {
            let buffer: AVAudioPCMBuffer
            var consumed = false
            init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }
        let provider = Provider(buffer: inputBuffer)
        var conversionError: NSError?
        _ = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if provider.consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            provider.consumed = true
            outStatus.pointee = .haveData
            return provider.buffer
        }

        if let conversionError {
            throw JarvisError.processFailure(conversionError.localizedDescription)
        }

        let outputCount = Int(outputBuffer.frameLength)
        guard let channel = outputBuffer.floatChannelData?[0] else {
            throw JarvisError.processFailure("Unable to access resampled audio data for \(url.path).")
        }
        return Array(UnsafeBufferPointer(start: channel, count: outputCount))
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0.0, +) / Double(count)
    }
}
