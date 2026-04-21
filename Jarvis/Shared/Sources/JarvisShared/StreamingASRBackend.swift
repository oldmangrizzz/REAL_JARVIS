import Foundation

/// A streaming speech-to-text backend that emits partial hypotheses as
/// audio frames arrive, not just at endpoint detection. MK2-EPIC-05.
public protocol StreamingASRBackend: AnyObject, Sendable {
    /// Feed audio frames incrementally. Backend accumulates and begins
    /// emitting hypotheses as soon as it has enough data.
    func feed(audioFrame: Data) throws

    /// Begin streaming partial + final hypotheses. The stream completes
    /// when the endpoint is detected or `cancel()` is called.
    func startStreaming() throws -> AsyncThrowingStream<ASRHypothesis, Error>

    /// Stop the currently-active stream without tearing down the backend.
    func stopStreaming()
}

