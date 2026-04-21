import Foundation

/// Protocol for dispatching display actions to remote mesh nodes
/// (alpha / beta / foxtrot / charlie). Allows tests to inject stubs.
public protocol MeshDisplayDispatching: Sendable {
    func dispatch(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult
}

/// HTTP-based dispatcher for mesh display commands. Each mesh node runs a
/// lightweight display-agent (see `scripts/mesh-display-agent.py`) that
/// listens on port 9455 and routes rendering requests to a local kiosk
/// browser or framebuffer writer.
///
/// Wire format (request):
/// ```
/// POST /display HTTP/1.1
/// Authorization: Bearer <shared-secret>
/// Content-Type: application/json
///
/// { "display": "<id>", "action": "<action>", "parameters": {...}, "ts": "<iso8601>" }
/// ```
public final class MeshDisplayDispatcher: MeshDisplayDispatching, @unchecked Sendable {
    private let session: URLSession
    private let bearerToken: String?
    private let port: Int
    private let scheme: String
    private let isoFormatter: ISO8601DateFormatter
    private let timeout: TimeInterval

    public init(
        session: URLSession = .shared,
        bearerToken: String? = MeshDisplayDispatcher.defaultBearer(),
        port: Int = 9455,
        scheme: String = "http",
        timeout: TimeInterval = 4.0
    ) {
        self.session = session
        self.bearerToken = bearerToken
        self.port = port
        self.scheme = scheme
        self.timeout = timeout
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        self.isoFormatter = fmt
    }

    public func dispatch(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult {
        guard let rawAddress = display.address, !rawAddress.isEmpty else {
            throw JarvisError.processFailure("Mesh display '\(display.id)' has no address configured.")
        }
        let host = rawAddress.split(separator: ":").first.map(String.init) ?? rawAddress
        guard let url = URL(string: "\(scheme)://\(host):\(port)/display") else {
            throw JarvisError.invalidInput("Invalid mesh dispatcher URL for '\(display.id)': \(rawAddress)")
        }

        let body: [String: Any] = [
            "display": display.id,
            "action": action,
            "parameters": parameters,
            "ts": isoFormatter.string(from: Date()),
            "authority": display.authority.rawValue
        ]
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = payload
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.processFailure("Mesh dispatch to '\(display.id)' (\(host):\(port)) failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw JarvisError.processFailure("Mesh dispatch to '\(display.id)' returned non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw JarvisError.processFailure("Mesh dispatch to '\(display.id)' returned HTTP \(http.statusCode): \(snippet)")
        }

        var details: [String: String] = [
            "display": display.id,
            "transport": "jarvis-tunnel",
            "address": rawAddress,
            "action": action,
            "authority": display.authority.rawValue,
            "status": "dispatched",
            "httpStatus": "\(http.statusCode)"
        ]
        if let text = String(data: data.prefix(512), encoding: .utf8), !text.isEmpty {
            details["agentResponse"] = text
        }

        return ExecutionResult(
            success: true,
            spokenText: "Dispatched \(action) to \(display.displayName) on the Jarvis mesh.",
            details: details
        )
    }

    /// Resolve the default bearer from (in order): `MESH_DISPLAY_SECRET` env,
    /// `.jarvis/mesh-display-secret` in the workspace root, or `nil`.
    public static func defaultBearer() -> String? {
        if let env = ProcessInfo.processInfo.environment["MESH_DISPLAY_SECRET"],
           !env.isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let candidates: [URL] = {
            if let paths = try? WorkspacePaths.discover() {
                return [paths.root.appendingPathComponent(".jarvis/mesh-display-secret")]
            }
            return [URL(fileURLWithPath: "/Users/grizzmed/REAL_JARVIS/.jarvis/mesh-display-secret")]
        }()
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
