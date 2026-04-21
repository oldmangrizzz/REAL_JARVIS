import Foundation

// MARK: - Transport protocol (testable)

public protocol N8NTransport: Sendable {
    func post(_ request: URLRequest, body: Data) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionN8NTransport: N8NTransport {
    public init() {}

    public func post(_ request: URLRequest, body: Data) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw N8NBridgeError.invalidResponse
        }
        return (data, http)
    }
}

// MARK: - Errors

public enum N8NBridgeError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case invalidResponse
    case unauthorized
    case httpStatus(Int, String)
    case decodeFailed(String)
    case encodeFailed(String)
}

// MARK: - Bridge

/// Jarvis → n8n bridge.
///
/// Invokes n8n workflows via webhook POST. Workflows are the operator's
/// "hands" — each webhook path maps to a workflow that orchestrates
/// HA service calls, forge builds, self-heal sequences, etc.
///
/// Example:
/// ```
/// let bridge = N8NBridge(baseURL: URL(string: "http://192.168.4.119:5678")!)
/// let result = try await bridge.runWorkflow(
///     webhookPath: "jarvis/scene/downstairs-on",
///     payload: ["room": "downstairs"]
/// )
/// ```
public struct N8NBridge: Sendable {
    public let baseURL: URL
    public let basicAuthUser: String?
    public let basicAuthPassword: String?
    public let transport: any N8NTransport

    public init(
        baseURL: URL,
        basicAuthUser: String? = nil,
        basicAuthPassword: String? = nil,
        transport: any N8NTransport = URLSessionN8NTransport()
    ) {
        self.baseURL = baseURL
        self.basicAuthUser = basicAuthUser
        self.basicAuthPassword = basicAuthPassword
        self.transport = transport
    }

    /// Fire a webhook-triggered workflow. Returns the raw response JSON
    /// as `[String: Any]` (n8n's "Respond to Webhook" node output).
    public func runWorkflow(
        webhookPath: String,
        payload: [String: Any] = [:],
        timeout: TimeInterval = 15
    ) async throws -> [String: Any] {
        let path = webhookPath.hasPrefix("/") ? String(webhookPath.dropFirst()) : webhookPath
        guard let url = URL(string: "webhook/\(path)", relativeTo: baseURL) else {
            throw N8NBridgeError.invalidBaseURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let user = basicAuthUser, let pass = basicAuthPassword {
            let creds = "\(user):\(pass)"
            if let token = creds.data(using: .utf8)?.base64EncodedString() {
                request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw N8NBridgeError.encodeFailed(error.localizedDescription)
        }

        let (data, http) = try await transport.post(request, body: body)

        switch http.statusCode {
        case 200..<300:
            if data.isEmpty {
                return [:]
            }
            do {
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return obj
                }
                return ["raw": String(data: data, encoding: .utf8) ?? ""]
            } catch {
                throw N8NBridgeError.decodeFailed(error.localizedDescription)
            }
        case 401, 403:
            throw N8NBridgeError.unauthorized
        default:
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw N8NBridgeError.httpStatus(http.statusCode, msg)
        }
    }
}
