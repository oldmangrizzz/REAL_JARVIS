import Foundation

/// A pluggable TTS backend. The backend is responsible for actually
/// turning text + a reference clip into a WAV at outputURL. Everything
/// upstream (reference selection, persona framing, approval gating,
/// telemetry) lives in JarvisVoicePipeline.
///
/// `identifier` is the source-of-truth string for VoiceIdentityFingerprint.
/// modelRepository — changing backends MUST change identifier so the
/// approval gate forces a re-audition.
public protocol TTSBackend {
    var identifier: String { get }
    var selectedVoiceLabel: String { get }
    var sampleRate: Int { get }

    func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws
}

