import Foundation
import Combine

// MARK: - Supporting Types (Placeholders)

/// Placeholder for the audio format description used by the gateway.
public struct AudioFormat {
    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
}

/// Protocol defining the contract for an ambient audio gateway.
public protocol AmbientAudioGateway: AnyObject {
    /// Emits an audio chunk to the voice pipeline.
    func emit(audioChunk: Data, format: AudioFormat) async throws

    /// Reassigns the gateway to a new endpoint.
    func reassign(to endpoint: Endpoint) async throws

    /// Refreshes the list of reachable endpoints.
    func refreshEndpoints() async throws

    /// Adds an observer to receive state updates.
    func addObserver(_ observer: AmbientAudioGatewayObserver)

    /// Removes a previously‑added observer.
    func removeObserver(_ observer: AmbientAudioGatewayObserver)
}

/// Simple endpoint representation.
public struct Endpoint: Hashable {
    public let identifier: UUID
    public let address: URL
}

/// Observer protocol for state changes.
public protocol AmbientAudioGatewayObserver: AnyObject {
    func ambientAudioGateway(_ gateway: AmbientAudioGateway, didChangeState state: AmbientAudioGatewayImpl.State)
}

// MARK: - Dependency Protocols (Placeholders)

public protocol BluetoothBroker {
    func connect(to endpoint: Endpoint) async throws
    func disconnect() async throws
    var isConnected: Bool { get }
}

public protocol WristSensor {
    var audioPublisher: AnyPublisher<(Data, AudioFormat), Never> { get }
    func start() async throws
    func stop() async throws
}

public protocol TunnelProbe {
    func discoverEndpoints() async throws -> [Endpoint]
}

public protocol Telemetry {
    func emit(event: String, metadata: [String: Any]?)
}

public protocol VoicePipeline {
    func process(audioChunk: Data, format: AudioFormat) async throws
}

public protocol BiometricRegistrar {
    func registerBiometricData(_ data: Data) async throws
}

public protocol TunnelIdentityProvider {
    var currentIdentity: UUID { get }
}

// MARK: - AmbientAudioGateway Implementation

public final class AmbientAudioGatewayImpl: AmbientAudioGateway {
    // MARK: - Public State

    public enum State: Equatable {
        case idle
        case discovering
        case connecting(Endpoint)
        case connected(Endpoint)
        case error(Error)
    }

    // MARK: - Private Properties

    private let bluetoothBroker: BluetoothBroker
    private let wristSensor: WristSensor
    private let tunnelProbe: TunnelProbe
    private let telemetry: Telemetry
    private let voicePipeline: VoicePipeline
    private let biometricRegistrar: BiometricRegistrar
    private let identityProvider: TunnelIdentityProvider

    private var currentState: State = .idle {
        didSet { notifyObservers(of: currentState) }
    }

    private var observers = NSHashTable<AnyObject>.weakObjects()
    private var cancellables = Set<AnyCancellable>()
    private var discoveredEndpoints: [Endpoint] = []

    // MARK: - Init

    public init(
        bluetoothBroker: BluetoothBroker,
        wristSensor: WristSensor,
        tunnelProbe: TunnelProbe,
        telemetry: Telemetry,
        voicePipeline: VoicePipeline,
        biometricRegistrar: BiometricRegistrar,
        identityProvider: TunnelIdentityProvider
    ) {
        self.bluetoothBroker = bluetoothBroker
        self.wristSensor = wristSensor
        self.tunnelProbe = tunnelProbe
        self.telemetry = telemetry
        self.voicePipeline = voicePipeline
        self.biometricRegistrar = biometricRegistrar
        self.identityProvider = identityProvider

        // Begin listening to wrist‑sensor audio stream.
        self.wristSensor.audioPublisher
            .sink { [weak self] chunk, format in
                Task.detached { await self?.handleIncomingAudio(chunk, format: format) }
            }
            .store(in: &cancellables)
    }

    // MARK: - AmbientAudioGateway Conformance

    public func emit(audioChunk: Data, format: AudioFormat) async throws {
        do {
            try await voicePipeline.process(audioChunk: audioChunk, format: format)
            telemetry.emit(event: "audioChunkEmitted", metadata: [
                "size": audioChunk.count,
                "sampleRate": format.sampleRate,
                "channelCount": format.channelCount
            ])
        } catch {
            telemetry.emit(event: "audioEmitFailed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    public func reassign(to endpoint: Endpoint) async throws {
        guard endpoint != currentEndpoint else { return }

        currentState = .connecting(endpoint)
        telemetry.emit(event: "reassignStart", metadata: ["endpoint": endpoint.identifier.uuidString])

        do {
            try await bluetoothBroker.disconnect()
            try await bluetoothBroker.connect(to: endpoint)
            currentState = .connected(endpoint)
            telemetry.emit(event: "reassignSuccess", metadata: ["endpoint": endpoint.identifier.uuidString])
        } catch {
            currentState = .error(error)
            telemetry.emit(event: "reassignFailed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    public func refreshEndpoints() async throws {
        currentState = .discovering
        telemetry.emit(event: "endpointRefreshStart", metadata: nil)

        do {
            let endpoints = try await tunnelProbe.discoverEndpoints()
            discoveredEndpoints = endpoints
            currentState = .idle
            telemetry.emit(event: "endpointRefreshSuccess", metadata: ["count": endpoints.count])
        } catch {
            currentState = .error(error)
            telemetry.emit(event: "endpointRefreshFailed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    public func addObserver(_ observer: AmbientAudioGatewayObserver) {
        observers.add(observer)
    }

    public func removeObserver(_ observer: AmbientAudioGatewayObserver) {
        observers.remove(observer)
    }

    // MARK: - Private Helpers

    private var currentEndpoint: Endpoint? {
        if case let .connected(endpoint) = currentState { return endpoint }
        if case let .connecting(endpoint) = currentState { return endpoint }
        return nil
    }

    private func notifyObservers(of state: State) {
        // Dispatch on a detached actor to avoid blocking the state machine.
        Task.detached { [weak self] in
            guard let self = self else { return }
            for case let observer as AmbientAudioGatewayObserver in self.observers.allObjects {
                observer.ambientAudioGateway(self, didChangeState: state)
            }
        }
    }

    private func handleIncomingAudio(_ chunk: Data, format: AudioFormat) async {
        // Forward audio to the voice pipeline and optionally register biometric data.
        do {
            try await emit(audioChunk: chunk, format: format)

            // Example: register a hash of the audio as biometric data.
            let biometricHash = SHA256.hash(data: chunk)
            let hashData = Data(biometricHash)
            try await biometricRegistrar.registerBiometricData(hashData)

            telemetry.emit(event: "audioProcessed", metadata: [
                "size": chunk.count,
                "identity": identityProvider.currentIdentity.uuidString
            ])
        } catch {
            telemetry.emit(event: "audioProcessingFailed", metadata: ["error": error.localizedDescription])
        }
    }
}

// MARK: - SHA256 Helper (Swift Crypto)

import CryptoKit

private extension SHA256 {
    static func hash(data: Data) -> Digest {
        return SHA256.hash(data: data)
    }
}