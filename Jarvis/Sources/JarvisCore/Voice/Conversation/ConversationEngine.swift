import Foundation

// MARK: - ConversationEngine

/// The core engine that drives a conversation, handling user input, speech synthesis,
/// and barge‑in events from a duplex VAD gate.
final class ConversationEngine {
    /// The duplex VAD gate that provides barge‑in signals.
    private let vadGate: any DuplexVADGate

    /// Task that continuously listens for barge‑in events.
    private var bargeInTask: Task<Void, Never>?

    // MARK: Initialization

    /// Creates a new conversation engine.
    ///
    /// - Parameter vadGate: An instance conforming to the ambient ``DuplexVADGate`` protocol.
    init(vadGate: any DuplexVADGate) {
        self.vadGate = vadGate
        subscribeToBargeIn()
    }

    deinit {
        bargeInTask?.cancel()
    }

    // MARK: Barge‑In Handling

    /// Subscribes to the ``DuplexVADGate``'s ``BargeInEvent`` stream and routes
    /// each event to the appropriate handler.
    private func subscribeToBargeIn() {
        bargeInTask = Task { [weak self] in
            guard let self = self else { return }
            for await event in self.vadGate.bargeInSignal {
                self.handleBargeIn(event)
            }
        }
    }

    /// Dispatches a received ``BargeInEvent`` to the concrete handler based on its reason.
    ///
    /// - Parameter event: The barge‑in event emitted by the VAD gate.
    private func handleBargeIn(_ event: BargeInEvent) {
        switch event.reason {
        case .vadTrigger:
            handleVADTrigger()
        case .stopWord:
            handleStopWord()
        case .explicit:
            handleExplicitBargeIn()
        }
    }

    /// Handles a barge‑in caused by a VAD trigger (speech detected while the system is speaking).
    private func handleVADTrigger() {
        // TODO: Implement VAD‑triggered barge‑in logic (e.g., pause/stop current TTS output).
    }

    /// Handles a barge‑in caused by a configured stop‑word.
    private func handleStopWord() {
        // TODO: Implement stop‑word barge‑in logic (e.g., cancel current utterance).
    }

    /// Handles an explicit barge‑in request (e.g., user pressed a button).
    private func handleExplicitBargeIn() {
        // TODO: Implement explicit barge‑in logic (e.g., immediately interrupt speech).
    }

    // MARK: - Existing ConversationEngine API (place‑holders)

    /// Starts the conversation engine. Existing implementation details remain unchanged.
    func start() {
        // Existing start logic…
    }

    /// Stops the conversation engine and cleans up resources.
    func stop() {
        // Existing stop logic…
        bargeInTask?.cancel()
    }

    // Additional methods and properties that were part of the original engine
    // should remain here unchanged. They are omitted for brevity.
}
