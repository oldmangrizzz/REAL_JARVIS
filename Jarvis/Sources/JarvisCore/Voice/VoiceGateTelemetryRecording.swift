import Foundation

// Protocol abstracting voice-gate telemetry so VoiceApprovalGate stays free
// of any direct coupling to TelemetryStore or Convex. Conformers are
// responsible for being best-effort: throwing here never blocks the gate.
public protocol VoiceGateTelemetryRecording {
    func logVoiceGateEvent(hostNode: String,
                           eventType: String,
                           composite: String?,
                           expectedComposite: String?,
                           operatorLabel: String?,
                           notes: String?) throws

    func syncVoiceGateState(hostNode: String,
                            state: String,
                            composite: String?,
                            expectedComposite: String?,
                            referenceAudioDigest: String?,
                            referenceTranscriptDigest: String?,
                            modelRepository: String?,
                            personaFramingVersion: String?,
                            operatorLabel: String?,
                            approvedAtISO8601: String?,
                            notes: String?) throws
}

extension TelemetryStore: VoiceGateTelemetryRecording {}
