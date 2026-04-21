import Foundation

// MARK: - Provider Enumerations

/// Speech‑to‑Text providers ordered by preference.
public enum STTProvider: String, CaseIterable {
    case localSFSpeech   // Apple's on‑device SFSpeechRecognizer
    case whisperCPP     // Whisper.cpp local inference
    case gcp            // Google Cloud Speech‑to‑Text
}

/// Text‑to‑Speech providers ordered by preference.
public enum TTSProvider: String, CaseIterable {
    case f5TTS          // F5‑TTS commercial service
    case fishAudioMLX   // FishAudio MLX model
    case textOnly       // Text‑only fallback (no audio)
}

// MARK: - Voice Failover Matrix

/// Central orchestrator that determines the next viable provider for STT/TTS
/// based on a predefined fallback order and a re‑approval (cool‑down) mechanism
/// after a provider reports a failure.
public final class VoiceFailoverMatrix {
    
    // MARK: Public API
    
    /// Shared singleton instance.
    public static let shared = VoiceFailoverMatrix()
    
    /// Returns the next enabled STT provider according to the fallback order.
    /// - Parameter after: The provider that just failed (optional). If `nil`, the first enabled provider is returned.
    /// - Returns: An enabled `STTProvider`. If all providers are disabled, the first provider in the order is returned as a last‑resort fallback.
    public func nextSTTProvider(after failedProvider: STTProvider? = nil) -> STTProvider {
        return nextProvider(
            after: failedProvider,
            orderedProviders: sttFallbackOrder,
            disabledMap: &disabledSTTProviders
        )
    }
    
    /// Returns the next enabled TTS provider according to the fallback order.
    /// - Parameter after: The provider that just failed (optional). If `nil`, the first enabled provider is returned.
    /// - Returns: An enabled `TTSProvider`. If all providers are disabled, the first provider in the order is returned as a last‑resort fallback.
    public func nextTTSProvider(after failedProvider: TTSProvider? = nil) -> TTSProvider {
        return nextProvider(
            after: failedProvider,
            orderedProviders: ttsFallbackOrder,
            disabledMap: &disabledTTSProviders
        )
    }
    
    /// Notifies the matrix that a provider has failed. The provider will be
    /// temporarily disabled for ``cooldownInterval`` seconds.
    /// - Parameter provider: The provider that experienced a failure.
    public func reportFailure(of provider: STTProvider) {
        setProvider(provider, disabled: true, map: &disabledSTTProviders)
    }
    
    /// Notifies the matrix that a provider has failed. The provider will be
    /// temporarily disabled for ``cooldownInterval`` seconds.
    /// - Parameter provider: The provider that experienced a failure.
    public func reportFailure(of provider: TTSProvider) {
        setProvider(provider, disabled: true, map: &disabledTTSProviders)
    }
    
    // MARK: Configuration
    
    /// Cool‑down interval (seconds) after which a failed provider becomes eligible again.
    public var cooldownInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: Private
    
    private init() {}
    
    // Ordered fallback matrices
    private let sttFallbackOrder: [STTProvider] = [.localSFSpeech, .whisperCPP, .gcp]
    private let ttsFallbackOrder: [TTSProvider] = [.f5TTS, .fishAudioMLX, .textOnly]
    
    // Disabled provider tracking (provider rawValue → timestamp when it can be re‑enabled)
    private var disabledSTTProviders: [String: Date] = [:]
    private var disabledTTSProviders: [String: Date] = [:]
    
    // Serial queue to guarantee thread‑safety for state mutations.
    private let syncQueue = DispatchQueue(label: "com.jarvis.voiceFailoverMatrix.sync")
    
    // Generic provider selection logic
    private func nextProvider<P: RawRepresentable & CaseIterable>(
        after failedProvider: P?,
        orderedProviders: [P],
        disabledMap: inout [String: Date]
    ) -> P where P.RawValue == String {
        return syncQueue.sync {
            // Remove any entries whose cooldown has elapsed.
            purgeExpiredEntries(in: &disabledMap)
            
            // If a specific provider just failed, ensure it is marked disabled.
            if let failed = failedProvider {
                disabledMap[failed.rawValue] = Date().addingTimeInterval(cooldownInterval)
            }
            
            // Find the first provider that is not currently disabled.
            for provider in orderedProviders {
                if disabledMap[provider.rawValue] == nil {
                    return provider
                }
            }
            
            // All providers are currently disabled – return the first in the order as a last‑resort.
            return orderedProviders.first!
        }
    }
    
    // Marks a provider as disabled/enabled in the appropriate map.
    private func setProvider<P: RawRepresentable>(
        _ provider: P,
        disabled: Bool,
        map: inout [String: Date]
    ) where P.RawValue == String {
        syncQueue.sync {
            if disabled {
                map[provider.rawValue] = Date().addingTimeInterval(cooldownInterval)
            } else {
                map.removeValue(forKey: provider.rawValue)
            }
        }
    }
    
    // Removes entries whose cooldown timestamp has passed.
    private func purgeExpiredEntries(in map: inout [String: Date]) {
        let now = Date()
        for (key, expiry) in map where expiry <= now {
            map.removeValue(forKey: key)
        }
    }
}