import Foundation

/// SPEC-AMBIENT-002: Watch-first audio gateway protocol.
///
/// States:
///   - unpaired: no BT peer
///   - watchHosted: watch owns BT link (target state)
///   - phoneFallback: phone mediates (watch can't host)
///   - offWrist: wrist-detect lost, session frozen (~300ms)
///   - cellularTether: watch has tunnel, phone absent
///   - degraded: tunnel down, local buffering
public enum AmbientGatewayRoute: String, Codable, Sendable, Equatable {
    case unpaired              // no BT peer
    case watchHosted           // watch owns BT link to headphones (target state)
    case phoneFallback         // phone mediates because watch can't host this headphone
    case offWrist              // wrist-detect lost, session frozen
    case cellularTether        // watch has tunnel, phone absent
    case degraded              // tunnel down, local buffering
}

public struct AmbientEndpoint: Codable, Sendable, Equatable {
    public let deviceID: String           // BT identifier, opaque
    public let displayName: String        // "AirPods Pro", "Bose QC 45"
    public let supportsA2DP: Bool
    public let supportsHandsFreeMic: Bool // usually false for generic BT
}

public struct AmbientGatewayState: Codable, Sendable, Equatable {
    public let route: AmbientGatewayRoute
    public let activeEndpoint: AmbientEndpoint?
    public let availableEndpoints: [AmbientEndpoint]
    public let wristAttached: Bool
    public let tunnelReachable: Bool
    public let updatedAt: Date
}

public protocol AmbientAudioGateway: AnyObject, Sendable {
    var currentState: AmbientGatewayState { get }
    func reassign(to endpointID: String) throws
    func refreshEndpoints() async
    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken
    func cancel(_ token: AmbientObserverToken)
}

public struct AmbientObserverToken: Hashable, Sendable {
    public let uuid: String
    public init() { self.uuid = UUID().uuidString }
}

/// Canonical audio frame for VOICE-002 ingestion.
///
/// Contracts:
///   - sampleRate: 16000 or 24000 Hz (Phase 1)
///   - channelCount: 1 (mono) Phase 1
///   - pcmData: signed int16 LE, little-endian
///   -captureTimestamp: host-local clock at capture
///   - sequenceNumber: monotonic per-session, gap-detectable
///   - routeHint: ambient route for latency SLA computation
///   - wristAttached: for off-wrist conversation cancellation
public struct AmbientAudioFrame: Sendable, Equatable {
    public let sampleRate: Int            // 16000 or 24000 Hz, Phase 1
    public let channelCount: Int          // 1 (mono) Phase 1
    public let pcmData: Data              // signed int16 LE, little-endian
    public let captureTimestamp: Date     // host-local clock at capture
    public let sequenceNumber: UInt64     // monotonic per-session, gap-detectable
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

/// VOICE-002 contract: local VAD that fires bargeInSignal.
public protocol DuplexVADGate: Sendable {
    var bargeInSignal: AsyncStream<BargeInEvent> { get }
    func configure(stopWords: [String])
}

public struct BargeInEvent: Sendable, Equatable {
    public let at: Date
    public let reason: BargeInReason   // .vadTrigger | .stopWord | .explicit
    public let confidence: Double      // 0.0–1.0
}

public enum BargeInReason: String, Codable, Sendable, Equatable {
    case vadTrigger
    case stopWord
    case explicit
}

/// TTS output format for `emit(audioChunk:format:)`.
public struct AmbientAudioFormat: Codable, Sendable, Equatable {
    public let codec: String     // "opus" Phase 1
    public let sampleRate: Int   // 24000 Hz for opus output

    public static let opus24kHz = AmbientAudioFormat(codec: "opus", sampleRate: 24000)
}