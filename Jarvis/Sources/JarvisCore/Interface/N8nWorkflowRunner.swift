import Foundation

/// Protocol for running n8n workflows via webhook. Allows tests to inject stubs.
public protocol N8nWorkflowRunning: Sendable {
    /// Trigger an n8n webhook workflow and return the agent response.
    ///
    /// - Parameters:
    ///   - workflowPath: The webhook path segment (e.g. `jarvis/ha/call-service`,
    ///     `jarvis/scene/downstairs-on`). Do not include `/webhook/` prefix or a
    ///     leading slash — the runner prepends them.
    ///   - payload: JSON-serializable dictionary sent as request body.
    func run(workflowPath: String, payload: [String: Any]) async throws -> ExecutionResult
}

/// HTTP runner for n8n webhook workflows. Mirrors `MeshDisplayDispatcher`:
/// bearer/basic auth is optional, production request is HTTPS against the
/// Pangolin-fronted `n8n.grizzlymedicine.icu` domain, and every response is
/// summarized into an `ExecutionResult` for uniform downstream handling.
///
/// Wire format (request):
/// ```
/// POST /webhook/<workflow-path> HTTP/1.1
/// Content-Type: application/json
/// Authorization: Basic <base64(user:pass)>   (only if basicAuth is set)
///
/// { ...payload..., "ts": "<iso8601>", "source": "jarvis" }
/// ```
public final class N8nWorkflowRunner: N8nWorkflowRunning, @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let basicAuthUser: String?
    private let basicAuthPassword: String?
    private let timeout: TimeInterval
    private let isoFormatter: ISO8601DateFormatter

    public init(
        session: URLSession = .shared,
        baseURL: URL = N8nWorkflowRunner.defaultBaseURL(),
        basicAuthUser: String? = N8nWorkflowRunner.defaultBasicAuthUser(),
        basicAuthPassword: String? = N8nWorkflowRunner.defaultBasicAuthPassword(),
        timeout: TimeInterval = 6.0
    ) {
        self.session = session
        self.baseURL = baseURL
        self.basicAuthUser = basicAuthUser
        self.basicAuthPassword = basicAuthPassword
        self.timeout = timeout
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        self.isoFormatter = fmt
    }

    public func run(workflowPath: String, payload: [String: Any]) async throws -> ExecutionResult {
        let trimmed = workflowPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty else {
            throw JarvisError.invalidInput("n8n workflow path cannot be empty.")
        }
        guard let url = URL(string: "webhook/\(trimmed)", relativeTo: baseURL)?.absoluteURL else {
            throw JarvisError.invalidInput("Could not construct n8n webhook URL for path '\(trimmed)'.")
        }

        var body = payload
        // Stamp every invocation so n8n-side logs can trace origin + timing
        // without callers having to remember to pass these. Caller-provided
        // values win on collision.
        if body["ts"] == nil {
            body["ts"] = isoFormatter.string(from: Date())
        }
        if body["source"] == nil {
            body["source"] = "jarvis"
        }

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } catch {
            throw JarvisError.invalidInput("n8n payload for '\(trimmed)' was not JSON serializable: \(error.localizedDescription)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let user = basicAuthUser, let pass = basicAuthPassword,
           !user.isEmpty, !pass.isEmpty,
           let credData = "\(user):\(pass)".data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data
        request.timeoutInterval = timeout

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.processFailure("n8n workflow '\(trimmed)' request failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw JarvisError.processFailure("n8n workflow '\(trimmed)' returned non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: responseData.prefix(256), encoding: .utf8) ?? ""
            throw JarvisError.processFailure("n8n workflow '\(trimmed)' returned HTTP \(http.statusCode): \(snippet)")
        }

        var details: [String: String] = [
            "workflow": trimmed,
            "url": url.absoluteString,
            "httpStatus": "\(http.statusCode)",
            "status": "dispatched"
        ]
        if let text = String(data: responseData.prefix(1024), encoding: .utf8), !text.isEmpty {
            details["agentResponse"] = text
        }

        return ExecutionResult(
            success: true,
            spokenText: "Triggered n8n workflow \(trimmed).",
            details: details
        )
    }

    // MARK: - Defaults

    /// Resolve the default base URL from (in order): `N8N_WEBHOOK_BASE` env,
    /// `.jarvis/n8n-webhook-base` in the workspace root, or the public
    /// Pangolin-fronted domain. Always ends in `/` so `URL(string:relativeTo:)`
    /// appends correctly.
    public static func defaultBaseURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["N8N_WEBHOOK_BASE"],
           let url = normalizedBaseURL(env) {
            return url
        }
        if let paths = try? WorkspacePaths.discover() {
            let candidate = paths.root.appendingPathComponent(".jarvis/n8n-webhook-base")
            if let data = try? Data(contentsOf: candidate),
               let text = String(data: data, encoding: .utf8),
               let url = normalizedBaseURL(text) {
                return url
            }
        }
        return URL(string: "https://n8n.grizzlymedicine.icu/")!
    }

    public static func defaultBasicAuthUser() -> String? {
        envOrFile(env: "N8N_WEBHOOK_USER", relativePath: ".jarvis/n8n-webhook-user")
    }

    public static func defaultBasicAuthPassword() -> String? {
        envOrFile(env: "N8N_WEBHOOK_PASSWORD", relativePath: ".jarvis/n8n-webhook-password")
    }

    private static func normalizedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withSlash = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        return URL(string: withSlash)
    }

    private static func envOrFile(env: String, relativePath: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let paths = try? WorkspacePaths.discover() {
            let candidate = paths.root.appendingPathComponent(relativePath)
            if let data = try? Data(contentsOf: candidate),
               let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
