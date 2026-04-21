import Foundation
import Combine

// MARK: - Ambient Types (imported from the Ambient module)

/// Represents a voice activity detection gate that can be opened or closed.
typealias DuplexVADGate = Ambient.DuplexVADGate

/// Represents a single frame of audio data.
typealias AudioFrame = AmbientAudioFrame

/// Represents a barge‑in event (e.g., user interruption).
typealias BargeInEvent = Ambient.BargeInEvent

/// Reason why a barge‑in occurred.
typealias BargeInReason = Ambient.BargeInReason

// MARK: - Voice Source Protocol

/// A protocol that all voice sources must conform to.
protocol VoiceSource {
    /// The display name of the source.
    var name: String { get }

    /// Process an incoming audio frame and return a publisher that emits the processed text.
    ///
    /// - Parameter frame: The raw audio frame.
    /// - Returns: A publisher that emits a `String` containing the transcribed text.
    func process(frame: AudioFrame) -> AnyPublisher<String, Error>
}

// MARK: - Gemini VOICE‑002 Implementation

/// Implementation of the Gemini VOICE‑002 source.
final class GeminiVoice002Source: VoiceSource {
    let name = "Gemini VOICE‑002"

    /// Simulated processing of an audio frame.
    ///
    /// In a real implementation this would forward the audio to Gemini's API and decode the response.
    func process(frame: AudioFrame) -> AnyPublisher<String, Error> {
        // For the purpose of this repository we simulate a short delay and return a placeholder string.
        // Replace this stub with the actual Gemini client call when integrating with the real service.
        Just("Transcribed text from Gemini VOICE‑002")
            .delay(for: .milliseconds(200), scheduler: DispatchQueue.global())
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

// MARK: - Voice Conversation

/// Orchestrates a voice conversation using a selected `VoiceSource`.
final class VoiceConversation {
    // MARK: Public API

    /// The currently selected voice source.
    let source: VoiceSource

    /// Publisher that emits transcribed text as it becomes available.
    var transcriptionPublisher: AnyPublisher<String, Error> {
        transcriptionSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits barge‑in events.
    var bargeInPublisher: AnyPublisher<(event: BargeInEvent, reason: BargeInReason), Never> {
        bargeInSubject.eraseToAnyPublisher()
    }

    /// Starts listening for audio frames from the provided `DuplexVADGate`.
    ///
    /// - Parameter vadGate: The VAD gate that supplies audio frames.
    func startListening(using vadGate: DuplexVADGate) {
        // Subscribe to the VAD gate's audio stream.
        vadGate.audioFrames
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.transcriptionSubject.send(completion: .failure(error))
                }
            }, receiveValue: { [weak self] frame in
                self?.handleAudioFrame(frame)
            })
            .store(in: &cancellables)
    }

    /// Sends a barge‑in event to any listeners.
    ///
    /// - Parameters:
    ///   - event: The barge‑in event.
    ///   - reason: The reason for the barge‑in.
    func sendBargeIn(event: BargeInEvent, reason: BargeInReason) {
        bargeInSubject.send((event: event, reason: reason))
    }

    // MARK: Initialization

    /// Creates a new `VoiceConversation` with the specified source.
    ///
    /// - Parameter source: The voice source to use. Defaults to Gemini VOICE‑002.
    init(source: VoiceSource = GeminiVoice002Source()) {
        self.source = source
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private let transcriptionSubject = PassthroughSubject<String, Error>()
    private let bargeInSubject = PassthroughSubject<(event: BargeInEvent, reason: BargeInReason), Never>()

    /// Handles an incoming audio frame by forwarding it to the active `VoiceSource`.
    ///
    /// - Parameter frame: The raw audio frame.
    private func handleAudioFrame(_ frame: AudioFrame) {
        source.process(frame: frame)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.transcriptionSubject.send(completion: .failure(error))
                }
            }, receiveValue: { [weak self] text in
                self?.transcriptionSubject.send(text)
            })
            .store(in: &cancellables)
    }
}

// MARK: - Extensions for Ambient Integration (if needed)

extension Ambient.DuplexVADGate {
    /// A convenience publisher exposing audio frames as `AmbientAudioFrame`.
    var audioFrames: AnyPublisher<AmbientAudioFrame, Error> {
        // The real implementation would bridge the underlying VAD stream to Combine.
        // Here we provide a stub that never emits, satisfying the compiler.
        Empty<AmbientAudioFrame, Error>(completeImmediately: false)
            .eraseToAnyPublisher()
    }
}