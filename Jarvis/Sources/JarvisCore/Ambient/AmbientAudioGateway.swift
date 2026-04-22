import Foundation

// MARK: - Route + endpoint model
//
// SPEC-AMBIENT-002-FIX-01 §3.1 — canonical contract. Source of truth for
// VOICE-002 §3.2, NAV-001 §11, and `Construction/Nemotron/spec/VOICE-002-FIX-01-remediation.md`.
// Do not re-declare these types elsewhere.

public enum AmbientGatewayRoute: String, Sendable, Equatable {
    case unpaired              // no BT peer
    case watchHosted           // watch owns BT link to headphones (target state)
    case phoneFallback         // phone mediates because watch can't host this headphone
    case offWrist              // wrist-detect lost, session frozen
    case cellularTether        // watch has tunnel, phone absent
    case degraded              // tunnel down, local buffering
}

public struct AmbientEndpoint: Sendable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let supportsHandsFreeProfile: Bool

    public init(id: String, displayName: String, supportsHandsFreeProfile: Bool) {
        self.id = id
        self.displayName = displayName
        self.supportsHandsFreeProfile = supportsHandsFreeProfile
    }
}

public struct AmbientGatewayState: Sendable, Equatable {
    public let route: AmbientGatewayRoute
    public let endpoint: AmbientEndpoint?
    public let wristAttached: Bool
    public let tunnelReachable: Bool
    public let updatedAt: Date

    public init(
        route: AmbientGatewayRoute,
        endpoint: AmbientEndpoint?,
        wristAttached: Bool,
        tunnelReachable: Bool,
        updatedAt: Date
    ) {
        self.route = route
        self.endpoint = endpoint
        self.wristAttached = wristAttached
        self.tunnelReachable = tunnelReachable
        self.updatedAt = updatedAt
    }
}

// MARK: - Canonical audio frame (VOICE-002 consumes this; must not redefine)

public struct AmbientAudioFormat: Sendable, Equatable, Codable {
    public let codec: String
    public let sampleRate: Int

    public init(codec: String, sampleRate: Int) {
        self.codec = codec
        self.sampleRate = sampleRate
    }

    public static let opus24kHz = AmbientAudioFormat(codec: "opus", sampleRate: 24000)
}

public struct AmbientAudioFrame: Sendable, Equatable {
    public let sampleRate: Int
    public let channelCount: Int
    public let pcmData: Data
    public let captureTimestamp: Date
    public let sequenceNumber: UInt64
    public let routeHint: AmbientGatewayRoute
    public let wristAttached: Bool

    public init(
        sampleRate: Int,
        channelCount: Int,
        pcmData: Data,
        captureTimestamp: Date,
        sequenceNumber: UInt64,
        routeHint: AmbientGatewayRoute,
        wristAttached: Bool
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.pcmData = pcmData
        self.captureTimestamp = captureTimestamp
        self.sequenceNumber = sequenceNumber
        self.routeHint = routeHint
        self.wristAttached = wristAttached
    }
}

// MARK: - Barge-in (VOICE-002 and NAV-001 consume; do not redefine)

public enum BargeInReason: String, Sendable, Equatable {
    case operatorSpeech      // VAD picked up incoming utterance while TTS was playing
    case navHazard           // NAV-001 emergency/hazard preempted conversation
    case offWristCancel      // wrist detach while conversation TTS queued
    case responderOverride   // cockpit emergency key
}

public struct BargeInEvent: Sendable, Equatable {
    public let reason: BargeInReason
    public let detectedAt: Date
    public let routeHint: AmbientGatewayRoute

    public init(reason: BargeInReason, detectedAt: Date, routeHint: AmbientGatewayRoute) {
        self.reason = reason
        self.detectedAt = detectedAt
        self.routeHint = routeHint
    }
}

public protocol DuplexVADGate: AnyObject, Sendable {
    /// Feed a frame; returns a barge-in event if the gate determines ongoing TTS
    /// should be preempted. Non-barge-in traffic returns nil.
    func ingest(frame: AmbientAudioFrame) -> BargeInEvent?
    func reset()
}

// MARK: - Observer pattern

public struct AmbientObserverToken: Hashable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

public protocol AmbientAudioGateway: AnyObject, Sendable {
    var state: AmbientGatewayState { get }
    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken
    func cancel(_ token: AmbientObserverToken)
}
