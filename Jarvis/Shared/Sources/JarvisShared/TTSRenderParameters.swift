import Foundation

/// Parameters tuned per render. Backends should accept whatever they
/// support and ignore the rest. cfgScale + ddpmSteps are backend-specific.
/// Lives in JarvisShared so all build targets (mac, iOS, watchOS) can
/// reference the streaming protocols without dragging JarvisCore in.
public struct TTSRenderParameters: Sendable {
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
    /// Reference clip: voice-samples/0299_TINCANS_CANONICAL.wav.
    /// DEPRECATED: VibeVoice is sunset; use `xttsLocked` for XTTS v2 canon.
    /// Retained for VoiceSynthesis env-fallback compatibility.
    public static let vibevoiceLocked = TTSRenderParameters(
        cfgScale: 2.1,
        ddpmSteps: 10
    )

    /// Operator-locked Coqui XTTS v2 defaults (voice canon 2026-04-21).
    /// Reference clip: voice-samples/0299_TINCANS_CANONICAL.wav.
    /// XTTS does not use diffusion params (cfgScale/ddpmSteps); tuning happens
    /// server-side on Delta:8787. Temperature/topP kept for client-side sampling.
    public static let xttsLocked = TTSRenderParameters(
        temperature: 0.7,
        topP: 0.85
    )

    /// Operator-locked F5-TTS defaults. Asserted by F5TTSBackendTests.
    public static let f5ttsLocked = TTSRenderParameters(
        cfgScale: 2.0,
        ddpmSteps: 32
    )
}
