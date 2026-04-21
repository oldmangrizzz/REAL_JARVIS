import Foundation

/// Protocol for launching apps over the DIAL (Discovery And Launch) protocol
/// used by Fire TV, Roku, and cast-compatible TVs.
public protocol DIALDispatching: Sendable {
    func launchApp(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult
}

/// Concrete DIAL bridge. Targets the DIAL application-launch endpoint on a
/// device's configured address. DIAL URLs typically live at
/// `http://<host>:<port>/apps/<appName>` with POST launching the app.
///
/// Defaults:
/// - port 8008 (Cast-compatible Fire TV / Chromecast)
/// - 200/201 status codes accepted
/// - 4-second timeout (TVs on LAN should respond well within that)
///
/// The `address` field on the `DisplayEndpoint` may carry a full `host:port`
/// or just `host` — both forms are handled. Parameters["content"] names the
/// app to launch (defaults to "YouTube" which is universally available).
public final class DIALBridge: DIALDispatching, @unchecked Sendable {
    private let session: URLSession
    private let defaultPort: Int
    private let timeout: TimeInterval

    public init(
        session: URLSession = .shared,
        defaultPort: Int = 8008,
        timeout: TimeInterval = 4.0
    ) {
        self.session = session
        self.defaultPort = defaultPort
        self.timeout = timeout
    }

    public func launchApp(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult {
        guard let rawAddress = display.address, !rawAddress.isEmpty else {
            throw JarvisError.processFailure("DIAL display '\(display.id)' has no address configured.")
        }
        let (host, port) = parseHostPort(rawAddress, defaultPort: defaultPort)
        let appName = parameters["content"] ?? parameters["app"] ?? defaultApp(for: action)
        guard let url = URL(string: "http://\(host):\(port)/apps/\(appName)") else {
            throw JarvisError.invalidInput("Invalid DIAL URL for '\(display.id)': \(rawAddress)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        if let payload = parameters["payload"], !payload.isEmpty {
            request.httpBody = payload.data(using: .utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.processFailure("DIAL launch on '\(display.id)' (\(host):\(port)/\(appName)) failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw JarvisError.processFailure("DIAL launch on '\(display.id)' returned non-HTTP response.")
        }
        // DIAL returns 201 Created or 200 OK on success; 206 Partial for
        // already-running apps. Anything else is a hard error.
        guard [200, 201, 206].contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw JarvisError.processFailure("DIAL launch on '\(display.id)' returned HTTP \(http.statusCode): \(snippet)")
        }

        return ExecutionResult(
            success: true,
            spokenText: "Launched \(appName) on \(display.displayName).",
            details: [
                "display": display.id,
                "transport": "dial",
                "address": rawAddress,
                "action": action,
                "app": appName,
                "httpStatus": "\(http.statusCode)"
            ]
        )
    }

    private func parseHostPort(_ raw: String, defaultPort: Int) -> (String, Int) {
        // Strip any leading http(s):// if present.
        var cleaned = raw
        if let range = cleaned.range(of: "://") {
            cleaned = String(cleaned[range.upperBound...])
        }
        let parts = cleaned.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let host = parts.first.map(String.init) ?? raw
        if parts.count == 2, let port = Int(parts[1]) {
            return (host, port)
        }
        return (host, defaultPort)
    }

    private func defaultApp(for action: String) -> String {
        switch action {
        case "display-dashboard", "display-hud", "display-telemetry":
            return "YouTube"
        case "display-camera":
            return "RingVideoDoorbell"
        default:
            return "YouTube"
        }
    }
}
