import Foundation

/// NoopTTSBackend is a non-functional backend used when canonical TTS
/// configuration is missing. It deliberately fails all synthesis attempts
/// rather than falling back to non-canonical backends. This enforces
/// the principle that absence of canonical configuration = silence, not substitution.
public final class NoopTTSBackend: TTSBackend {
    public let identifier: String = "noop-disabled"
    public let selectedVoiceLabel: String = "silent"
    public let sampleRate: Int = 24_000

    public init() {}

    public func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        throw JarvisError.invalidInput(
            "TTS backend not configured. Canonical backend requires JARVIS_CANON_TTS_HOST and JARVIS_TTS_BEARER."
        )
    }
}
