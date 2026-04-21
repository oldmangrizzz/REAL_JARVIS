import Foundation

/// The central orchestrator for bidirectional speech-to-speech interaction.
/// Matches SPEC-VOICE-002 §3.
public final class ConversationEngine: @unchecked Sendable {
    private let runtime: JarvisRuntime
    private let asr: StreamingASRBackend
    private let llm: StreamingLLMClient
    private let tts: StreamingTTSBackend
    private let duplexVADGate: (any DuplexVADGate)?
    private let queue = DispatchQueue(label: "ai.realjarvis.conversation-engine", attributes: .concurrent)
    
    private var activeSessions: [UUID: ConversationSession] = [:]
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]
    
    // SLA ceilings (p95 targets from SPEC §4)
    private enum SLACeilings {
        static let asrFirstPartial: TimeInterval = 0.250
        static let asrFinal: TimeInterval = 0.400
        static let llmFirstToken: TimeInterval = 0.400
        static let ttsFirstChunk: TimeInterval = 0.500
        static let endToEnd: TimeInterval = 1.000
    }
    
    public init(
        runtime: JarvisRuntime,
        asr: StreamingASRBackend,
        llm: StreamingLLMClient,
        tts: StreamingTTSBackend,
        duplexVADGate: (any DuplexVADGate)? = nil
    ) {
        self.runtime = runtime
        self.asr = asr
        self.llm = llm
        self.tts = tts
        self.duplexVADGate = duplexVADGate
    }
    
    /// Start a new conversational session for a principal.
    public func startSession(principal: Principal) -> ConversationSession {
        let session = ConversationSession(principal: principal)
        queue.async(flags: .barrier) {
            self.activeSessions[session.id] = session
        }
        return session
    }
    
    /// End an active session and cleanup.
    public func endSession(_ sessionID: UUID) {
        queue.async(flags: .barrier) {
            if let session = self.activeSessions.removeValue(forKey: sessionID) {
                try? session.transition(to: .closed)
                self.sessionTasks.removeValue(forKey: sessionID)?.cancel()
            }
        }
    }
    
    /// Handle incoming audio frames from the operator mic.
    public func ingestAudio(frame: Data, sessionID: UUID) throws {
        guard let session = queue.sync(execute: { activeSessions[sessionID] }) else {
            throw JarvisError.invalidInput("Session \(sessionID) not found.")
        }
        
        if session.state == .idle {
            try session.transition(to: .listening)
        }
        
        try asr.feed(audioFrame: frame)
    }

    /// Handle incoming ambient audio frames from the watch gateway.
    /// Canonicalizes AmbientAudioFrame to Data and routes to ASR.
    public func ingestAudio(frame: AmbientAudioFrame, sessionID: UUID) throws {
        // Validate Phase 1 constraints
        guard frame.sampleRate == 16000 || frame.sampleRate == 24000 else {
            throw JarvisError.invalidInput("AmbientAudioFrame sampleRate must be 16000 or 24000 Hz (got \(frame.sampleRate)).")
        }
        guard frame.channelCount == 1 else {
            throw JarvisError.invalidInput("AmbientAudioFrame channelCount must be 1 (got \(frame.channelCount)).")
        }

        // Canonicalize to Data (signed int16 LE)
        // The pcmData is already in the correct format per spec
        try ingestAudio(frame: frame.pcmData, sessionID: sessionID)
    }
    
/// Subscribes to the ASR partials and coordinates the generation/synthesis loop.
    /// Also subscribes to bargeInSignal for handling barge-in events.
    public func activate(sessionID: UUID) {
        let hypotheses: AsyncThrowingStream<ASRHypothesis, Error>
        do {
            hypotheses = try asr.startStreaming()
        } catch {
            if let session = queue.sync(execute: { activeSessions[sessionID] }) {
                try? transition(session: session, to: .degraded, reason: "asr_start_failure: \(error.localizedDescription)")
            }
            return
        }

        let asrTask = Task {
            guard let session = queue.sync(execute: { activeSessions[sessionID] }) else { return }

            do {
                for try await hypo in hypotheses {
                    if Task.isCancelled { break }

                    if session.state == .idle {
                        try transition(session: session, to: .listening, reason: "asr_activity")
                    }
                    if !hypo.isFinal {
                        if session.state != .partialUnderstanding {
                            try transition(session: session, to: .partialUnderstanding, reason: "asr_partial")
                        }
                    } else {
                        // ASR Final reached -> Start LLM + TTS pipeline
                        try await runTurn(session: session, prompt: hypo.text)
                    }
                }
            } catch {
                try? transition(session: session, to: .degraded, reason: "asr_failure: \(error.localizedDescription)")
            }
        }
        
        let bargeInTask = Task { [weak self] in
            guard let self else { return }
            guard let gate = self.duplexVADGate else { return }
            guard let session = self.queue.sync(execute: { self.activeSessions[sessionID] }) else { return }

            for await event in gate.bargeInSignal {
                if Task.isCancelled { break }

                switch event.reason {
                case .vadTrigger, .stopWord, .explicit:
                    try? self.handleBargeIn(sessionID: session.id)
                }
            }
        }
        
        queue.async(flags: .barrier) {
            self.sessionTasks[sessionID] = Task {
                _ = await asrTask.result
                _ = await bargeInTask.result
            }
        }
    }
    
    private func transition(session: ConversationSession, to state: ConversationState, reason: String? = nil) throws {
        let fromState = session.state
        try session.transition(to: state, reason: reason)
        
        // Log transition (SPEC-009)
        let record = ConversationStateTransitionRecord(
            sessionId: session.id,
            turnId: nil, // TODO: track active turnId
            fromState: fromState.rawValue,
            toState: state.rawValue,
            reason: reason,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        
        if let data = try? JSONEncoder().encode(record),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try? runtime.telemetry.append(record: dict, to: "conversation_state_transitions", principal: session.principal)
        }
        
        // Check for degradation
        if session.shouldDegrade && state != .degraded {
            try? transition(session: session, to: .degraded, reason: "3_sla_misses_30s")
        }
    }
    
    private func runTurn(session: ConversationSession, prompt: String) async throws {
        let turnID = UUID()
        let startedAt = Date()
        try transition(session: session, to: .generating, reason: "asr_final")
        
        do {
            // 1. LLM Generation
            let tokenStream = try llm.generateStream(prompt: prompt, principal: session.principal)
            
            var fullResponse = ""
            var firstTokenReceived = false
            
            for try await token in tokenStream {
                if Task.isCancelled { break }
                if !firstTokenReceived {
                    session.recordLLMFirstToken()
                    firstTokenReceived = true
                }
                
                fullResponse += token.text
                
                // Sentence chunking for TTS streaming
                if isSentenceBoundary(token.text) {
                    try await synthesizeAndSpeak(session: session, turnID: turnID, text: fullResponse, isFinal: token.isFinal)
                    fullResponse = "" // Reset for next sentence
                }
            }
            
            // Handle any trailing text
            if !fullResponse.isEmpty {
                try await synthesizeAndSpeak(session: session, turnID: turnID, text: fullResponse, isFinal: true)
            }
            
            // Turn completed
            let endedAt = Date()
            let metrics = session.getTurnMetrics(endedAt: endedAt)
            try finalizeTurn(session: session, turnID: turnID, startedAt: startedAt, endedAt: endedAt, outcome: "completed", metrics: metrics)
            
            try transition(session: session, to: .listening, reason: "turn_completed")
            
        } catch is CancellationError {
            let endedAt = Date()
            let metrics = session.getTurnMetrics(endedAt: endedAt)
            try finalizeTurn(session: session, turnID: turnID, startedAt: startedAt, endedAt: endedAt, outcome: "cancelled", metrics: metrics)
        } catch {
            try transition(session: session, to: .degraded, reason: "llm_failure: \(error.localizedDescription)")
        }
    }
    
    private func synthesizeAndSpeak(session: ConversationSession, turnID: UUID, text: String, isFinal: Bool) async throws {
        if session.state != .speaking {
            try transition(session: session, to: .speaking, reason: "first_sentence_ready")
        }
        
        // Prepare the TTS synthesis session (using cached reference samples)
        let config = try runtime.voice.prepareSession()
        
        // Start the streaming synthesis
        let chunkStream = try tts.synthesizeStream(
            text: text,
            referenceAudioURL: config.referenceAudioURL,
            referenceTranscript: config.referenceTranscript,
            parameters: backendIsF5() ? .f5ttsLocked : .vibevoiceLocked
        )
        
        var firstChunk = true
        for try await chunk in chunkStream {
            if Task.isCancelled { 
                tts.cancel()
                break 
            }
            
            if firstChunk {
                session.recordTTSFirstChunk()
                firstChunk = false
            }
            
            // Log SLA miss if first chunk took too long
            // (Budget logic here using session.recordSlaMiss())
            
            // Emit to the Ambient Gateway (owned by Qwen/AMBIENT-002)
            // Note: AmbientAudioGateway protocol must be available in runtime
            // try await runtime.ambientGateway.emit(audioChunk: chunk.data, format: .wav)
        }
    }
    
    private func backendIsF5() -> Bool {
        // Simple heuristic for Phase 1
        return true 
    }
    
    private func finalizeTurn(
        session: ConversationSession,
        turnID: UUID,
        startedAt: Date,
        endedAt: Date,
        outcome: String,
        metrics: [String: Double]
    ) throws {
        let formatter = ISO8601DateFormatter()
        let record = ConversationTurnRecord(
            turnId: turnID,
            sessionId: session.id,
            startedAt: formatter.string(from: startedAt),
            endedAt: formatter.string(from: endedAt),
            outcome: outcome,
            latencyMs: .init(
                asrFirstPartial: metrics["asrFirstPartial"],
                asrFinal: metrics["asrFinal"],
                llmFirstToken: metrics["llmFirstToken"],
                ttsFirstChunk: metrics["ttsFirstChunk"],
                endToEnd: metrics["endToEnd"] ?? 0
            ),
            bargeInCount: 0, // TODO
            principal: session.principal.tierToken,
            route: "watchHosted", // TODO: read from gateway
            multiplier: 1.0
        )
        
        if let data = try? JSONEncoder().encode(record),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try runtime.telemetry.append(record: dict, to: "conversation_turns", principal: session.principal)
        }
    }
    
    private func isSentenceBoundary(_ text: String) -> Bool {
        let terminal = [".", "!", "?", "\n"]
        return terminal.contains { text.contains($0) }
    }
    
    // MARK: - Preemption & Barge-in
    
    public func handleBargeIn(sessionID: UUID) throws {
        guard let session = queue.sync(execute: { activeSessions[sessionID] }) else { return }
        
        if session.state == .speaking {
            try session.transition(to: .bargeInterrupt)
            llm.cancel()
            tts.cancel()
            // Immediately return to listening
            try session.transition(to: .listening)
        }
    }
}
