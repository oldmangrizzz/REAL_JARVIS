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
    public static let vibevoiceLocked = TTSRenderParameters(
        cfgScale: 2.1,
        ddpmSteps: 10
    )

    /// Operator-locked F5-TTS defaults. Asserted by F5TTSBackendTests.
    public static let f5ttsLocked = TTSRenderParameters(
        cfgScale: 2.0,
        ddpmSteps: 32
    )
}
