import Foundation

// MARK: - Transport protocol (testable)

public protocol LettaTransport: Sendable {
    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionLettaTransport: LettaTransport {
    public init() {}

    public func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var req = request
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LettaBridgeError.invalidResponse
        }
        return (data, http)
    }
}

// MARK: - Errors

public enum LettaBridgeError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case invalidResponse
    case unauthorized
    case httpStatus(Int, String)
    case decodeFailed(String)
    case encodeFailed(String)
}

// MARK: - Bridge

/// Jarvis ↔ Letta bridge (episodic/agent memory peripheral).
///
/// Letta is Jarvis's external episodic memory + long-running agent runtime
/// (LXC 201 on alpha, 192.168.7.200:8283). Bearer auth via SECURE=true.
/// The local MemoryEngine handles somatic/stigmergic graph memory; Letta
/// provides durable conversational agents with tool-augmented recall.
public struct LettaBridge: Sendable {
    public let baseURL: URL
    public let bearerToken: String?
    public let transport: any LettaTransport

    public init(
        baseURL: URL,
        bearerToken: String? = nil,
        transport: any LettaTransport = URLSessionLettaTransport()
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.transport = transport
    }

    /// GET /v1/health/ — returns version + status dict.
    public func health(timeout: TimeInterval = 10) async throws -> [String: Any] {
        try await get(path: "v1/health/", timeout: timeout)
    }

    /// GET /v1/agents/ — list all agents in the default org.
    public func listAgents(timeout: TimeInterval = 15) async throws -> [[String: Any]] {
        let (data, http) = try await request(method: "GET", path: "v1/agents/", body: nil, timeout: timeout)
        try validate(http: http, data: data)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LettaBridgeError.decodeFailed("expected JSON array")
        }
        return arr
    }

    /// POST /v1/agents/ — create a new Letta agent. `payload` should follow
    /// Letta's CreateAgent schema (name, system, llm_config, embedding_config, …).
    @discardableResult
    public func createAgent(payload: [String: Any], timeout: TimeInterval = 30) async throws -> [String: Any] {
        try await postJSON(path: "v1/agents/", payload: payload, timeout: timeout)
    }

    /// POST /v1/agents/{agentId}/messages — send a user message to an agent
    /// and return the assistant's response payload.
    public func sendMessage(
        agentID: String,
        message: String,
        role: String = "user",
        timeout: TimeInterval = 60
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "messages": [
                ["role": role, "text": message]
            ]
        ]
        return try await postJSON(path: "v1/agents/\(agentID)/messages", payload: payload, timeout: timeout)
    }

    /// POST /v1/agents/{agentId}/core-memory/append — append text to agent core memory.
    @discardableResult
    public func appendCoreMemory(
        agentID: String,
        blockLabel: String,
        text: String,
        timeout: TimeInterval = 30
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "label": blockLabel,
            "value": text
        ]
        return try await postJSON(
            path: "v1/agents/\(agentID)/core-memory/append",
            payload: payload,
            timeout: timeout
        )
    }

    // MARK: - Internals

    private func get(path: String, timeout: TimeInterval) async throws -> [String: Any] {
        let (data, http) = try await request(method: "GET", path: path, body: nil, timeout: timeout)
        try validate(http: http, data: data)
        if data.isEmpty { return [:] }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LettaBridgeError.decodeFailed("expected JSON object")
        }
        return dict
    }

    private func postJSON(path: String, payload: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw LettaBridgeError.encodeFailed(error.localizedDescription)
        }
        let (data, http) = try await request(method: "POST", path: path, body: body, timeout: timeout)
        try validate(http: http, data: data)
        if data.isEmpty { return [:] }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return ["items": arr]
        }
        return ["raw": String(data: data, encoding: .utf8) ?? ""]
    }

    private func request(
        method: String,
        path: String,
        body: Data?,
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: rel, relativeTo: baseURL) else {
            throw LettaBridgeError.invalidBaseURL(baseURL.absoluteString)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let token = bearerToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await transport.send(req, body: body)
    }

    private func validate(http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw LettaBridgeError.unauthorized
        default:
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw LettaBridgeError.httpStatus(http.statusCode, msg)
        }
    }
}
