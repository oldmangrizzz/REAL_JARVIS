import Foundation

/// A streaming text-to-speech backend that emits audio chunks as sentences
/// are synthesized, not waiting for full response completion. MK2-EPIC-05.
public protocol StreamingTTSBackend: AnyObject, Sendable {
    /// Begin streaming audio chunks for `text` using the canon reference clip.
    /// Backends that don't support reference audio may ignore the reference args.
    func synthesizeStream(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters
    ) throws -> AsyncThrowingStream<TTSAudioChunk, Error>

    /// Cancel in-flight synthesis. Must abort within 150 ms.
    func cancel()
}

