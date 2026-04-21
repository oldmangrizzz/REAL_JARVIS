import Foundation
import Gemini

@MainActor
final class VoiceEngine: Sendable {
    private var voice: Gemini.VOICE?
    private(set) var isSpeaking: Bool = false

    init() {}

    /// Assigns the underlying Gemini voice implementation.
    func setVoice(_ voice: Gemini.VOICE) {
        self.voice = voice
    }

    /// Speaks the provided text using the configured Gemini voice.
    ///
    /// This method bridges Gemini's callback‑based API to Swift's async/await
    /// model, ensuring proper concurrency handling under Swift 6's strict
    /// concurrency rules.
    ///
    /// - Parameter text: The text to be spoken.
    /// - Throws: An error if the underlying voice reports a failure.
    func speak(_ text: String) async throws {
        guard let voice = voice else { return }
        isSpeaking = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            voice.speak(text) { @Sendable result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        isSpeaking = false
    }

    /// Stops any ongoing speech.
    func stop() {
        voice?.stop()
        isSpeaking = false
    }
}