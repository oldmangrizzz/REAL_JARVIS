import Foundation

public enum JarvisConvexError: Error, LocalizedError {
    case invalidURL
    case serverError(String)
    case missingResponseValue

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Convex URL is invalid."
        case .serverError(let message):
            return message
        case .missingResponseValue:
            return "Convex response did not include a value payload."
        }
    }
}

public actor JarvisConvexSyncClient {
    private let configuration: JarvisHostConfiguration
    private let session: URLSession

    public init(configuration: JarvisHostConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func registerDevice(_ registration: JarvisClientRegistration) async throws {
        try await postMutation(
            path: "jarvis:registerMobileDevice",
            args: RegisterDeviceArgs(
                deviceID: registration.deviceID,
                deviceName: registration.deviceName,
                platform: registration.platform,
                role: registration.role,
                appVersion: registration.appVersion
            )
        )
    }

    public func heartbeat(registration: JarvisClientRegistration, state: JarvisConnectionState, pushToken: String?) async throws {
        try await postMutation(
            path: "jarvis:recordMobileHeartbeat",
            args: HeartbeatArgs(
                deviceID: registration.deviceID,
                tunnelState: state.rawValue,
                pushToken: pushToken
            )
        )
    }

    public func log(push: JarvisPushDirective, registration: JarvisClientRegistration) async throws {
        try await postMutation(
            path: "jarvis:logPushDirective",
            args: PushDirectiveArgs(
                deviceID: registration.deviceID,
                directiveID: push.id,
                title: push.title,
                body: push.body,
                startupLine: push.startupLine,
                requiresSpeech: push.requiresSpeech,
                timestamp: push.timestamp
            )
        )
    }

    public func fetchSharedState(limit: Int = 8) async throws -> JarvisSharedState {
        try await postQuery(path: "jarvis:sharedMobileState", args: LimitArgs(limit: limit), as: JarvisSharedState.self)
    }

    private func postMutation<Args: Encodable>(path: String, args: Args) async throws {
        let envelope: ConvexEnvelope<Bool> = try await send(path: path, endpoint: "mutation", args: args, decode: ConvexEnvelope<Bool>.self)
        if let error = envelope.errorMessage {
            throw JarvisConvexError.serverError(error)
        }
    }

    private func postQuery<Args: Encodable, Value: Decodable>(path: String, args: Args, as type: Value.Type) async throws -> Value {
        let envelope: ConvexEnvelope<Value> = try await send(path: path, endpoint: "query", args: args, decode: ConvexEnvelope<Value>.self)
        if let error = envelope.errorMessage {
            throw JarvisConvexError.serverError(error)
        }
        guard let value = envelope.value else {
            throw JarvisConvexError.missingResponseValue
        }
        return value
    }

    private func send<Args: Encodable, Value: Decodable>(path: String, endpoint: String, args: Args, decode: Value.Type) async throws -> Value {
        let url = configuration.convexURL.appendingPathComponent("api/\(endpoint)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.convexAuthToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(ConvexRequest(path: path, args: args))

        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            throw JarvisConvexError.serverError("Convex returned HTTP \(response.statusCode).")
        }

        return try JSONDecoder().decode(decode, from: data)
    }
}

private struct ConvexRequest<Args: Encodable>: Encodable {
    let path: String
    let args: Args
}

private struct ConvexEnvelope<Value: Decodable>: Decodable {
    let value: Value?
    let errorMessage: String?
}

private struct RegisterDeviceArgs: Encodable {
    let deviceID: String
    let deviceName: String
    let platform: String
    let role: String
    let appVersion: String
}

private struct HeartbeatArgs: Encodable {
    let deviceID: String
    let tunnelState: String
    let pushToken: String?
}

private struct PushDirectiveArgs: Encodable {
    let deviceID: String
    let directiveID: String
    let title: String
    let body: String
    let startupLine: String
    let requiresSpeech: Bool
    let timestamp: String
}

private struct LimitArgs: Encodable {
    let limit: Int
}
