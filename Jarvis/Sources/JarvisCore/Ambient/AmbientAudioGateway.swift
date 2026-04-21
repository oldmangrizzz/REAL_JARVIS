import Foundation

/// Represents a logical route within the ambient audio gateway system.
public struct AmbientGatewayRoute: Hashable {
    /// The raw path string used to identify the route.
    public let path: String

    /// Creates a new route with the given path.
    /// - Parameter path: The string that identifies the route.
    public init(_ path: String) {
        self.path = path
    }
}

/// Describes a concrete endpoint that the ambient audio gateway can communicate with.
public struct AmbientEndpoint: Hashable {
    /// The base URL of the endpoint (e.g. `wss://ambient.example.com`).
    public let url: URL

    /// The route on the endpoint that should be used for audio traffic.
    public let route: AmbientGatewayRoute

    /// Creates a new endpoint description.
    /// - Parameters:
    ///   - url: The base URL of the remote service.
    ///   - route: The route that will be used for the audio stream.
    public init(url: URL, route: AmbientGatewayRoute) {
        self.url = url
        self.route = route
    }
}

/// The connection state of an ``AmbientAudioGateway`` instance.
public enum AmbientGatewayState {
    /// The gateway is idle and not attempting a connection.
    case disconnected

    /// The gateway is in the process of establishing a connection.
    case connecting

    /// The gateway has an active, healthy connection.
    case connected

    /// The gateway failed to connect or encountered a runtime error.
    /// - Parameter error: The underlying error that caused the failure.
    case failed(Error)
}

/// A token that can be used to cancel an observation of gateway state changes.
public final class AmbientObserverToken {
    private let cancellation: () -> Void

    /// Creates a token that will invoke `cancellation` when ``cancel()`` is called.
    /// - Parameter cancellation: The closure that removes the observer.
    public init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    /// Cancels the observation associated with this token.
    public func cancel() {
        cancellation()
    }
}

/// A lightweight representation of a single audio frame that can be sent through the gateway.
public struct AmbientAudioFrame {
    /// Raw PCM or encoded audio payload.
    public let data: Data

    /// The presentation timestamp of the frame, expressed as seconds since the Unix epoch.
    public let timestamp: TimeInterval

    /// The sample rate (in Hz) of the audio data.
    public let sampleRate: Int

    /// Creates a new audio frame.
    /// - Parameters:
    ///   - data: The audio payload.
    ///   - timestamp: The presentation timestamp. Defaults to the current time.
    ///   - sampleRate: The sample rate of the audio data.
    public init(data: Data, timestamp: TimeInterval = Date().timeIntervalSince1970, sampleRate: Int) {
        self.data = data
        self.timestamp = timestamp
        self.sampleRate = sampleRate
    }
}

/// The public contract for an ambient‑audio gateway. Implementations are responsible for
/// establishing a connection to a remote ``AmbientEndpoint``, delivering audio frames,
/// and broadcasting state changes to observers.
public protocol AmbientAudioGateway: AnyObject {
    /// The current connection state of the gateway.
    var state: AmbientGatewayState { get }

    /// Starts the gateway, establishing a connection to its configured endpoint.
    func start()

    /// Stops the gateway and tears down any active connections.
    func stop()

    /// Registers an observer that will be called whenever the gateway's ``state`` changes.
    ///
    /// The returned ``AmbientObserverToken`` can be used to cancel the observation.
    ///
    /// - Parameter observer: A closure that receives the new ``AmbientGatewayState``.
    /// - Returns: A token that can cancel the observation.
    func observeState(_ observer: @escaping (AmbientGatewayState) -> Void) -> AmbientObserverToken

    /// Sends an audio frame to the remote endpoint.
    ///
    /// - Parameter frame: The frame to transmit.
    /// - Throws: An error if the frame cannot be sent (e.g. because the gateway is not connected).
    func send(_ frame: AmbientAudioFrame) throws
}