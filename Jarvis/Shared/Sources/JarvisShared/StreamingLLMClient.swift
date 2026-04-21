import Foundation

/// A streaming LLM client that ingests a prompt and emits `LLMToken`
/// values as they are generated. MK2-EPIC-05.
public protocol StreamingLLMClient: AnyObject, Sendable {
    /// Begin streaming tokens for the given prompt under the given principal.
    /// Must abort within 150 ms of `cancel()`.
    func generateStream(prompt: String, principal: Principal) throws -> AsyncThrowingStream<LLMToken, Error>

    /// Cancel the in-flight generation.
    func cancel()
}

