import Foundation

/// Parameters tuned per render. Backends should accept whatever they
/// support and ignore the rest — defaults preserve current fish-audio
/// behavior. cfgScale + ddpmSteps are VibeVoice-specific (HTTP backend);
/// other backends ignore them.
public struct TTSRenderParameters {
    public let temperature: Double
    public let topP: Double
    public let maxNewTokens: Int?
    public let cfgScale: Double?
    public let ddpmSteps: Int?

    public init(
        temperature: Double = 0.65,
        topP: Double = 0.92,
        maxNewTokens: Int? = nil,
        cfgScale: Double? = nil,
        ddpmSteps: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxNewTokens = maxNewTokens
        self.cfgScale = cfgScale
        self.ddpmSteps = ddpmSteps
    }

    public static let `default` = TTSRenderParameters()

    /// Operator-locked VibeVoice defaults from the 2026-04-18 audition matrix.
    /// Reference clip: voice-samples/0299_TINCANS_CANONICAL.wav (Derek Urban
    /// HF dataset row 0299, Iron Man 1 dub-stage room tone). Anything else
    /// is NOT the approved JARVIS voice — re-audition required.
    public static let vibevoiceLocked = TTSRenderParameters(
        cfgScale: 2.1,
        ddpmSteps: 10
    )

    /// Operator-locked F5-TTS defaults. Used when the active backend
    /// identifier indicates F5-TTS. Values asserted by F5TTSBackendTests.
    public static let f5ttsLocked = TTSRenderParameters(
        cfgScale: 2.0,
        ddpmSteps: 32
    )
}

extension TTSRenderParameters: Sendable {}

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
