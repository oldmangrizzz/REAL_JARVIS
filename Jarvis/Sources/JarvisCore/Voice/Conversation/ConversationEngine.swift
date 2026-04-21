import Foundation
import Ambient

// MARK: - ConversationEngineDelegate

/// A delegate protocol to receive transcription results or errors from the `ConversationEngine`.
public protocol ConversationEngineDelegate: AnyObject {
    /// Called when the engine produces a transcription string.
    func conversationEngine(_ engine: ConversationEngine, didReceiveTranscription text: String)
    
    /// Called when the engine encounters an error.
    func conversationEngine(_ engine: ConversationEngine, didEncounterError error: Error)
}

// MARK: - ConversationEngine

/// The core engine that drives a voice conversation pipeline.
///
/// It consumes an `Ambient.DuplexVADGate` to read audio frames, performs
/// voice‑activity‑detection (VAD) gating, and forwards the audio to the
/// Gemini `VOICE-002` model for transcription. Results are delivered via
/// the `ConversationEngineDelegate`.
public final class ConversationEngine {
    
    // MARK: - Public Constants
    
    /// Identifier for the Gemini voice model used by this engine.
    public static let source = "gemini-voice-002"
    
    // MARK: - Public Properties
    
    /// The delegate that receives transcription callbacks.
    public weak var delegate: ConversationEngineDelegate?
    
    // MARK: - Private Properties
    
    private let vadGate: Ambient.DuplexVADGate
    private let processingQueue = DispatchQueue(label: "com.jarvis.conversationEngine", qos: .userInitiated)
    private var isRunning = false
    
    // MARK: - Initialization
    
    /// Creates a new `ConversationEngine` with the supplied VAD gate.
    ///
    /// - Parameter vadGate: An object conforming to `Ambient.DuplexVADGate` that provides
    ///   audio frames and VAD state.
    public init(vadGate: Ambient.DuplexVADGate) {
        self.vadGate = vadGate
    }
    
    // MARK: - Public Control Methods
    
    /// Starts the conversation loop. Subsequent audio frames will be read from the VAD gate
    /// and processed on a background queue.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        processingQueue.async { [weak self] in
            self?.runLoop()
        }
    }
    
    /// Stops the conversation loop and signals the VAD gate to cease operation.
    public func stop() {
        isRunning = false
        vadGate.stop()
    }
    
    // MARK: - Private Loop
    
    private func runLoop() {
        while isRunning {
            do {
                // Read the next chunk of audio data from the VAD gate.
                let audioChunk = try vadGate.read()
                
                // Perform transcription using the Gemini model (placeholder implementation).
                let transcription = transcribe(audioChunk)
                
                // Deliver the result back on the main thread.
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.conversationEngine(self, didReceiveTranscription: transcription)
                }
            } catch {
                // Propagate any errors to the delegate and halt processing.
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.conversationEngine(self, didEncounterError: error)
                }
                isRunning = false
            }
        }
    }
    
    // MARK: - Placeholder Transcription
    
    /// Simulates a transcription call to the Gemini `VOICE-002` model.
    ///
    /// In a production implementation this would perform a network request or
    /// invoke a local inference engine. Here we simply return a formatted string.
    ///
    /// - Parameter data: The raw audio data to transcribe.
    /// - Returns: A string containing the simulated transcription.
    private func transcribe(_ data: Data) -> String {
        // NOTE: Replace this stub with real integration to Gemini VOICE-002.
        return "Transcribed (source: \(Self.source))"
    }
}