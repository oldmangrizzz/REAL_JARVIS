import Foundation

// MARK: - Ambient Audio Gateway Protocol

/// The core contract for an ambient audio gateway. Implementations are responsible for handling
/// audio capture, transmission, and reception in the ambient (always‑listening) mode.
public protocol AmbientAudioGateway: AnyObject {
    /// The current state of the gateway.
    var state: AmbientGatewayState { get }

    /// The audio format that the gateway operates with.
    var format: AmbientAudioFormat { get }

    /// Optional handler that receives barge‑in events.
    var bargeInEventHandler: ((BargeInEvent) -> Void)? { get set }

    /// Starts the gateway using the supplied route and endpoint.
    ///
    /// - Parameters:
    ///   - route: The routing strategy to be used.
    ///   - endpoint: The remote endpoint to connect to.
    /// - Throws: Errors that occur while starting the gateway.
    func start(route: AmbientGatewayRoute, endpoint: AmbientEndpoint) throws

    /// Stops the gateway and releases any allocated resources.
    ///
    /// - Throws: Errors that occur while stopping the gateway.
    func stop() throws

    /// Sends an audio frame to the remote side.
    ///
    /// - Parameter frame: The audio frame to transmit.
    /// - Throws: Errors that occur while sending the frame.
    func sendAudio(_ frame: AmbientAudioFrame) throws

    /// Registers an observer that will be called whenever the gateway state changes.
    ///
    /// - Parameter observer: A closure that receives the new state.
    /// - Returns: A token that can be used to cancel the observation.
    func observe(_ observer: @escaping (AmbientGatewayState) -> Void) -> AmbientObserverToken
}

// MARK: - Supporting Types

/// Describes the routing strategy for an ambient audio session.
public enum AmbientGatewayRoute: Equatable {
    /// Use a local (on‑device) processing pipeline.
    case local

    /// Use a remote (cloud) processing pipeline.
    case remote

    /// A custom route identified by a string token.
    case custom(String)
}

/// Information required to identify a remote endpoint.
public struct AmbientEndpoint: Equatable {
    /// A unique identifier for the endpoint.
    public let id: String

    /// A human‑readable name for the endpoint.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Represents the current operational state of the gateway.
public enum AmbientGatewayState: Equatable {
    /// The gateway is idle and not processing audio.
    case idle

    /// The gateway is actively listening for user speech.
    case listening

    /// The gateway is speaking (playback) to the user.
    case speaking

    /// An error has occurred; the associated value provides details.
    case error(Error)
}

/// Describes the audio format used throughout the ambient session.
public struct AmbientAudioFormat: Equatable {
    /// Sample rate in Hertz (e.g., 16000).
    public let sampleRate: Int

    /// Number of audio channels (e.g., 1 for mono).
    public let channels: Int

    /// Bits per sample (e.g., 16).
    public let bitsPerSample: Int

    public init(sampleRate: Int, channels: Int, bitsPerSample: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }
}

/// A single chunk of audio data.
public struct AmbientAudioFrame: Equatable {
    /// Raw PCM data.
    public let data: Data

    /// Timestamp (seconds since the start of the session) for this frame.
    public let timestamp: TimeInterval

    public init(data: Data, timestamp: TimeInterval) {
        self.data = data
        self.timestamp = timestamp
    }
}

/// Reasons why a barge‑in (interrupt) may have been triggered.
public enum BargeInReason: Equatable {
    /// The user started speaking while the system was speaking.
    case userSpeech

    /// No speech was detected within the expected window.
    case timeout

    /// An internal error caused the interruption.
    case error(Error)
}

/// Event emitted when a barge‑in occurs.
public struct BargeInEvent: Equatable {
    /// The reason for the barge‑in.
    public let reason: BargeInReason

    /// Timestamp (seconds since session start) when the barge‑in happened.
    public let timestamp: TimeInterval

    public init(reason: BargeInReason, timestamp: TimeInterval) {
        self.reason = reason
        self.timestamp = timestamp
    }
}

// MARK: - Duplex VAD Gate

/// A very small helper that can be used by concrete gateway implementations to perform
/// voice‑activity‑detection (VAD) on incoming audio frames. The default implementation simply
/// returns `true` for every frame, meaning “speech detected”. Implementations may replace
/// this with a real VAD algorithm.
public final class DuplexVADGate {
    /// Determines whether the supplied frame contains speech.
    ///
    /// - Parameter frame: The audio frame to analyse.
    /// - Returns: `true` if speech is detected, otherwise `false`.
    public func isSpeech(_ frame: AmbientAudioFrame) -> Bool {
        // Placeholder implementation – always reports speech.
        // Real implementations should replace this with actual VAD logic.
        return true
    }

    public init() {}
}

// MARK: - Observation Token

/// Token returned from ``AmbientAudioGateway/observe(_:)`` that can be used to cancel the
/// observation. The concrete token type is opaque to callers.
public protocol AmbientObserverToken {
    /// Cancels the observation, preventing further callbacks.
    func cancel()
}

// Simple concrete implementation used by default gateway stubs.
internal final class AmbientObserverTokenImpl: AmbientObserverToken {
    private var isCancelled = false
    private let cancellationClosure: () -> Void

    init(_ cancellationClosure: @escaping () -> Void) {
        self.cancellationClosure = cancellationClosure
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellationClosure()
    }
}

// MARK: - Default No‑Op Gateway (useful for tests)

/// A minimal, no‑op implementation of ``AmbientAudioGateway`` that satisfies the protocol
/// requirements without performing any real work. This is primarily intended for unit‑test
/// scaffolding where the behaviour of the gateway itself is not under test.
public final class AmbientAudioGatewayNoOp: AmbientAudioGateway {
    public private(set) var state: AmbientGatewayState = .idle
    public let format: AmbientAudioFormat
    public var bargeInEventHandler: ((BargeInEvent) -> Void)?

    private var observers: [(AmbientGatewayState) -> Void] = []

    public init(format: AmbientAudioFormat = AmbientAudioFormat(sampleRate: 16000,
                                                                channels: 1,
                                                                bitsPerSample: 16)) {
        self.format = format
    }

    public func start(route: AmbientGatewayRoute, endpoint: AmbientEndpoint) throws {
        state = .listening
        notifyObservers()
    }

    public func stop() throws {
        state = .idle
        notifyObservers()
    }

    public func sendAudio(_ frame: AmbientAudioFrame) throws {
        // No‑op – in a real implementation this would forward the frame.
    }

    public func observe(_ observer: @escaping (AmbientGatewayState) -> Void) -> AmbientObserverToken {
        observers.append(observer)
        // Immediately deliver the current state.
        observer(state)

        let token = AmbientObserverTokenImpl { [weak self] in
            self?.observers.removeAll { $0 as AnyObject === observer as AnyObject }
        }
        return token
    }

    private func notifyObservers() {
        for observer in observers {
            observer(state)
        }
    }
}