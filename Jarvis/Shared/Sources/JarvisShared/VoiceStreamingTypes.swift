import Foundation

/// Voice pipeline streaming primitives (MK2-EPIC-05 canonical shapes).
/// Consumed by `ConversationEngine` and by every ASR/LLM/TTS backend.

/// One hypothesis emitted by the streaming ASR. `isFinal == true` marks
/// the endpoint of an utterance; `isFinal == false` is a partial that
/// should drive the `partialUnderstanding` conversation state.
public struct ASRHypothesis: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Double

    public init(text: String, isFinal: Bool, confidence: Double) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

/// One token (or short run of tokens) from the streaming LLM.
/// `isFinal == true` indicates the terminal token of the generation.
public struct LLMToken: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// One audio chunk emitted by the streaming TTS backend.
public struct TTSAudioChunk: Sendable, Equatable {
    public let data: Data
    public let sampleRate: Int
    public let isFinal: Bool

    public init(data: Data, sampleRate: Int, isFinal: Bool) {
        self.data = data
        self.sampleRate = sampleRate
        self.isFinal = isFinal
    }
}
