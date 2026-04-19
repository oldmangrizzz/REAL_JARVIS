import AVFoundation
import Foundation
@preconcurrency import MLX
import MLXAudioCore
@preconcurrency import MLXAudioTTS

public final class JarvisMobileVoiceCloneEngine: @unchecked Sendable {
    private enum Constants {
        static let modelRepository = "mlx-community/fish-audio-s2-pro-8bit"
        static let sampleCount = 3
    }

    final class BundleToken {}

    private let bundle: Bundle
    private var model: SpeechGenerationModel?
    private var player: AVAudioPlayer?

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle(for: BundleToken.self)
    }

    public func warm() async throws {
        let model = try await resolvedModel()
        _ = try referenceAudio(using: model)
        _ = referenceTranscript()
    }

    @discardableResult
    public func play(text: String) async throws -> URL {
        let model = try await resolvedModel()
        let refAudio = try referenceAudio(using: model)
        let rendered = try await model.generate(
            text: personaFrame(text),
            voice: nil,
            refAudio: refAudio,
            refText: referenceTranscript(),
            language: "en"
        ).asArray(Float.self)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-mobile-\(UUID().uuidString).wav")
        try writeAudioFile(samples: rendered, sampleRate: Double(model.sampleRate), outputURL: outputURL)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: outputURL)
        player.prepareToPlay()
        self.player = player
        player.play()
        return outputURL
    }

    private func resolvedModel() async throws -> SpeechGenerationModel {
        if let model {
            return model
        }
        let loaded = try await TTS.loadModel(modelRepo: Constants.modelRepository)
        self.model = loaded
        return loaded
    }

    private func referenceAudio(using model: SpeechGenerationModel) throws -> MLXArray {
        let candidates = try referenceURLs().sorted { duration(of: $0) > duration(of: $1) }
        let selected = Array(candidates.prefix(Constants.sampleCount))
        guard !selected.isEmpty else {
            throw JarvisConvexError.serverError("No bundled voice reference WAVs are available.")
        }

        var merged: [Float] = []
        for url in selected {
            let (_, sample) = try loadAudioArray(from: url, sampleRate: model.sampleRate)
            merged.append(contentsOf: sample.asArray(Float.self))
        }
        return MLXArray(merged)
    }

    private func referenceURLs() throws -> [URL] {
        let subdirectoryMatches = bundle.urls(forResourcesWithExtension: "wav", subdirectory: "voice-samples") ?? []
        let rootMatches = bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? []
        let combined = Array(Set(subdirectoryMatches + rootMatches)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !combined.isEmpty else {
            throw JarvisConvexError.serverError("The mobile bundle does not contain voice reference samples.")
        }
        return combined
    }

    private func referenceTranscript() -> String {
        if let url = bundle.url(forResource: "voice-reference", withExtension: "txt", subdirectory: "voice-samples"),
           let text = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let url = bundle.url(forResource: "voice-reference", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return "Good evening. Keep your head, trust the evidence, and leave the drama to lesser systems."
    }

    private func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0.0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func personaFrame(_ text: String) -> String {
        text
    }

    private func writeAudioFile(samples: [Float], sampleRate: Double, outputURL: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw JarvisConvexError.serverError("Unable to allocate audio buffer for mobile voice synthesis.")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }

        let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try file.write(from: buffer)
    }
}
