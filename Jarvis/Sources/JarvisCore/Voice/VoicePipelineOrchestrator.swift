import Foundation

// MARK: - Supporting Types

/// Represents a raw audio buffer. The concrete implementation is provided elsewhere in the project.
public struct AudioBuffer {
    public let data: Data
    public let sampleRate: Int

    public init(data: Data, sampleRate: Int) {
        self.data = data
        self.sampleRate = sampleRate
    }
}

/// Simple enum describing each stage of the voice pipeline. Used for telemetry and watch‑gateway events.
public enum VoicePipelineStage: String, CaseIterable {
    case vad = "VoiceActivityDetection"
    case stt = "SpeechToText"
    case approval = "VoiceApprovalGate"
    case intentParsing = "IntentParsing"
    case actionExecution = "ActionExecution"
    case tts = "TextToSpeech"
    case playback = "AudioPlayback"
}

/// Represents an intent parsed from a transcript. The concrete shape is defined elsewhere.
public protocol Intent {}

/// Simple struct used to convey events to the watch gateway.
public struct VoicePipelineEvent {
    public let stage: VoicePipelineStage
    public let details: [String: Any]

    public init(stage: VoicePipelineStage, details: [String: Any] = [:]) {
        self.stage = stage
        self.details = details
    }
}

// MARK: - Dependency Protocols

/// Detects voice activity in an audio buffer.
public protocol VoiceActivityDetector {
    func detectVoice(in audio: AudioBuffer) async throws -> Bool
}

/// Speech‑to‑text engine. May throw on failure.
public protocol SpeechToTextEngine {
    func transcribe(_ audio: AudioBuffer) async throws -> String
}

/// Gate that decides whether a transcript is allowed to continue through the pipeline.
public protocol VoiceApprovalGate {
    func approve(_ transcript: String) async throws -> Bool
}

/// Parses a transcript into a concrete `Intent`.
public protocol IntentParser {
    func parse(_ transcript: String) async throws -> Intent
}

/// Executes a concrete `Intent`.
public protocol ActionExecutor {
    func execute(_ intent: Intent) async throws
}

/// Text‑to‑speech engine. May throw on failure.
public protocol TextToSpeechEngine {
    func synthesize(_ text: String) async throws -> AudioBuffer
}

/// Plays back an audio buffer.
public protocol AudioPlayer {
    func play(_ audio: AudioBuffer) async throws
}

/// Sends telemetry data for each pipeline stage.
public protocol TelemetryReporter {
    func report(stage: VoicePipelineStage, details: [String: Any]) async
}

/// Sends high‑level events to a paired watch device.
public protocol WatchGateway {
    func send(_ event: VoicePipelineEvent) async
}

// MARK: - Failover Matrix

/// Holds primary and secondary engines for STT and TTS, providing transparent failover.
public struct VoiceEngineFailoverMatrix {
    public let primarySTT: SpeechToTextEngine
    public let secondarySTT: SpeechToTextEngine?
    public let primaryTTS: TextToSpeechEngine
    public let secondaryTTS: TextToSpeechEngine?

    public init(primarySTT: SpeechToTextEngine,
                secondarySTT: SpeechToTextEngine? = nil,
                primaryTTS: TextToSpeechEngine,
                secondaryTTS: TextToSpeechEngine? = nil) {
        self.primarySTT = primarySTT
        self.secondarySTT = secondarySTT
        self.primaryTTS = primaryTTS
        self.secondaryTTS = secondaryTTS
    }
}

// MARK: - VoicePipelineOrchestrator

/// Orchestrates the full voice interaction pipeline:
/// 1️⃣ VAD → 2️⃣ STT (with failover) → 3️⃣ Approval Gate →
/// 4️⃣ Intent Parsing → 5️⃣ Action Execution →
/// 6️⃣ TTS (with failover) → 7️⃣ Playback.
///
/// All stages are serialized by the actor, telemetry is emitted for each stage,
/// and a high‑level event is forwarded to the watch gateway.
public actor VoicePipelineOrchestrator {

    // MARK: Dependencies

    private let vad: VoiceActivityDetector
    private let engines: VoiceEngineFailoverMatrix
    private let approvalGate: VoiceApprovalGate
    private let parser: IntentParser
    private let executor: ActionExecutor
    private let player: AudioPlayer
    private let telemetry: TelemetryReporter
    private let watchGateway: WatchGateway

    // MARK: Initialiser

    public init(vad: VoiceActivityDetector,
                engines: VoiceEngineFailoverMatrix,
                approvalGate: VoiceApprovalGate,
                parser: IntentParser,
                executor: ActionExecutor,
                player: AudioPlayer,
                telemetry: TelemetryReporter,
                watchGateway: WatchGateway) {
        self.vad = vad
        self.engines = engines
        self.approvalGate = approvalGate
        self.parser = parser
        self.executor = executor
        self.player = player
        self.telemetry = telemetry
        self.watchGateway = watchGateway
    }

    // MARK: Public API

    /// Entry point for processing a raw audio buffer. The method is fully asynchronous
    /// and guarantees that only one audio buffer is processed at a time because the
    /// orchestrator is an `actor`.
    ///
    /// - Parameter audio: The captured audio buffer.
    public func process(audio: AudioBuffer) async {
        await reportAndNotify(stage: .vad, details: [:])
        guard await runVAD(on: audio) else {
            // No voice activity – nothing further to do.
            return
        }

        await reportAndNotify(stage: .stt, details: [:])
        guard let transcript = await runSTT(on: audio) else {
            // STT failed on both primary and secondary engines.
            return
        }

        await reportAndNotify(stage: .approval, details: ["transcript": transcript])
        guard await runApprovalGate(on: transcript) else {
            // Not approved – stop processing.
            return
        }

        await reportAndNotify(stage: .intentParsing, details: ["transcript": transcript])
        guard let intent = await runIntentParsing(on: transcript) else {
            // Parsing failed – stop processing.
            return
        }

        await reportAndNotify(stage: .actionExecution, details: ["intent": String(describing: intent)])
        await runActionExecution(on: intent)

        // For simplicity we reuse the transcript as the response text.
        // In a real system this would likely be generated by a separate response generator.
        let responseText = transcript

        await reportAndNotify(stage: .tts, details: ["responseText": responseText])
        guard let ttsAudio = await runTTS(on: responseText) else {
            // TTS failed on both engines.
            return
        }

        await reportAndNotify(stage: .playback, details: ["audioLength": ttsAudio.data.count])
        await runPlayback(on: ttsAudio)
    }

    // MARK: Private Helpers

    private func runVAD(on audio: AudioBuffer) async -> Bool {
        do {
            let hasVoice = try await vad.detectVoice(in: audio)
            return hasVoice
        } catch {
            // VAD errors are non‑fatal – treat as no voice detected.
            return false
        }
    }

    private func runSTT(on audio: AudioBuffer) async -> String? {
        // Try primary engine first.
        do {
            let result = try await engines.primarySTT.transcribe(audio)
            return result
        } catch {
            // Primary failed – attempt secondary if available.
            guard let secondary = engines.secondarySTT else { return nil }
            do {
                let result = try await secondary.transcribe(audio)
                return result
            } catch {
                // Both failed.
                return nil
            }
        }
    }

    private func runApprovalGate(on transcript: String) async -> Bool {
        do {
            let approved = try await approvalGate.approve(transcript)
            return approved
        } catch {
            // On error we conservatively reject.
            return false
        }
    }

    private func runIntentParsing(on transcript: String) async -> Intent? {
        do {
            let intent = try await parser.parse(transcript)
            return intent
        } catch {
            // Parsing failure – stop pipeline.
            return nil
        }
    }

    private func runActionExecution(on intent: Intent) async {
        do {
            try await executor.execute(intent)
        } catch {
            // Action execution errors are logged via telemetry but do not abort playback.
            await telemetry.report(stage: .actionExecution, details: ["error": error.localizedDescription])
        }
    }

    private func runTTS(on text: String) async -> AudioBuffer? {
        // Primary TTS first.
        do {
            let audio = try await engines.primaryTTS.synthesize(text)
            return audio
        } catch {
            // Primary failed – try secondary if present.
            guard let secondary = engines.secondaryTTS else { return nil }
            do {
                let audio = try await secondary.synthesize(text)
                return audio
            } catch {
                // Both failed.
                return nil
            }
        }
    }

    private func runPlayback(on audio: AudioBuffer) async {
        do {
            try await player.play(audio)
        } catch {
            // Playback errors are reported but there is nothing further to do.
            await telemetry.report(stage: .playback, details: ["error": error.localizedDescription])
        }
    }

    private func reportAndNotify(stage: VoicePipelineStage, details: [String: Any]) async {
        await telemetry.report(stage: stage, details: details)
        let event = VoicePipelineEvent(stage: stage, details: details)
        await watchGateway.send(event)
    }
}