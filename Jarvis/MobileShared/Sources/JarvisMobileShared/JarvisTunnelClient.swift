import Foundation
import Network

public final class JarvisTunnelClient: @unchecked Sendable {
    private let config: JarvisHostConfiguration
    private let registration: JarvisClientRegistration
    private let crypto: JarvisTunnelCrypto
    private let queue = DispatchQueue(label: "ai.realjarvis.mobile-tunnel")
    private let onMessage: @Sendable (JarvisTunnelMessage) -> Void
    private let onStateChange: @Sendable (JarvisConnectionState, String?) -> Void
    private var connection: NWConnection?
    private var buffer = Data()
    /// MK2-EPIC-02 wire-v2: Stored role token issued by the server at registration.
    /// Included in every post-registration frame for server-side validation.
    private var storedRoleToken: String?

    public init(
        config: JarvisHostConfiguration,
        registration: JarvisClientRegistration,
        onMessage: @escaping @Sendable (JarvisTunnelMessage) -> Void,
        onStateChange: @escaping @Sendable (JarvisConnectionState, String?) -> Void
    ) {
        self.config = config
        self.registration = registration
        self.crypto = JarvisTunnelCrypto(sharedSecret: config.sharedSecret)
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }

    public func connect() {
        guard connection == nil else { return }
        let endpointPort = NWEndpoint.Port(rawValue: config.hostPort) ?? NWEndpoint.Port(rawValue: 9443)!
        let connection = NWConnection(host: NWEndpoint.Host(config.hostAddress), port: endpointPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .setup, .preparing:
                self.publish(state: .connecting)
            case .ready:
                self.publish(state: .online)
                self.send(JarvisTunnelMessage(kind: .register, registration: self.registration))
                self.sendHeartbeat()
                self.receive(on: connection)
            case .failed(let error):
                self.publish(state: .failed, message: error.localizedDescription)
                self.disconnect()
            case .cancelled:
                self.publish(state: .disconnected)
                self.connection = nil
            default:
                self.publish(state: .degraded)
            }
        }
        self.connection = connection
        connection.start(queue: queue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
        publish(state: .disconnected)
    }

    public func send(_ command: JarvisRemoteCommand) {
        send(JarvisTunnelMessage(kind: .command, command: command))
    }

    public func sendHeartbeat() {
        send(JarvisTunnelMessage(kind: .heartbeat))
    }

    private func send(_ message: JarvisTunnelMessage) {
        guard let connection else { return }
        do {
            // MK2-EPIC-02 wire-v2: inject stored role token into every post-registration frame
            let outgoing: JarvisTunnelMessage
            if message.kind != .register, let token = storedRoleToken {
                outgoing = JarvisTunnelMessage(
                    kind: message.kind,
                    registration: message.registration,
                    command: message.command,
                    snapshot: message.snapshot,
                    response: message.response,
                    push: message.push,
                    error: message.error,
                    roleToken: token,
                    confirmHash: message.confirmHash,
                    nonce: message.nonce
                )
            } else {
                outgoing = message
            }
            let sealed = try crypto.seal(outgoing)
            let packet = JarvisTransportPacket(
                origin: registration.deviceID,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                payload: sealed
            )
            let data = try JSONEncoder().encode(packet) + Data([0x0A])
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            publish(state: .failed, message: error.localizedDescription)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if isComplete || error != nil {
                self.publish(state: .degraded, message: error?.localizedDescription)
                self.disconnect()
                return
            }
            self.receive(on: connection)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            decodeLine(Data(line))
        }
    }

    private func decodeLine(_ data: Data) {
        do {
            let packet = try JSONDecoder().decode(JarvisTransportPacket.self, from: data)
            let message = try crypto.open(JarvisTunnelMessage.self, from: packet.payload)
            // MK2-EPIC-02 wire-v2: persist role token from server registration response
            if let token = message.roleToken {
                storedRoleToken = token
            }
            DispatchQueue.main.async {
                self.onMessage(message)
            }
        } catch {
            publish(state: .failed, message: error.localizedDescription)
        }
    }

    private func publish(state: JarvisConnectionState, message: String? = nil) {
        DispatchQueue.main.async {
            self.onStateChange(state, message)
        }
    }
}
