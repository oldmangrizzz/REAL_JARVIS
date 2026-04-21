import Foundation

/// Protocol for triggering Alexa routines (Echo Show / Echo / Fire TV)
/// via a configured webhook. Real deployments point `display.address` at
/// an n8n / IFTTT / Voice Monkey webhook that fires the routine.
public protocol AlexaRoutineDispatching: Sendable {
    func trigger(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult
}

/// Concrete Alexa routine bridge. Expects `display.address` to contain a
/// fully-qualified webhook URL (http/https). Posts a JSON payload
/// describing the routine and any parameters. 2xx responses are considered
/// success.
public final class AlexaRoutineBridge: AlexaRoutineDispatching, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval
    private let isoFormatter: ISO8601DateFormatter

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 4.0
    ) {
        self.session = session
        self.timeout = timeout
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        self.isoFormatter = fmt
    }

    public func trigger(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult {
        guard let webhookRaw = display.address, !webhookRaw.isEmpty else {
            throw JarvisError.processFailure("Alexa routine display '\(display.id)' has no webhook address configured.")
        }
        let webhookString: String
        if webhookRaw.hasPrefix("http://") || webhookRaw.hasPrefix("https://") {
            webhookString = webhookRaw
        } else {
            webhookString = "https://\(webhookRaw)"
        }
        guard let url = URL(string: webhookString) else {
            throw JarvisError.invalidInput("Invalid Alexa webhook URL for '\(display.id)': \(webhookRaw)")
        }

        let routine = parameters["routine"] ?? parameters["content"] ?? action
        let body: [String: Any] = [
            "display": display.id,
            "routine": routine,
            "action": action,
            "parameters": parameters,
            "ts": isoFormatter.string(from: Date())
        ]
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JarvisError.processFailure("Alexa routine dispatch for '\(display.id)' failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw JarvisError.processFailure("Alexa routine dispatch for '\(display.id)' returned non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(256), encoding: .utf8) ?? ""
            throw JarvisError.processFailure("Alexa routine dispatch for '\(display.id)' returned HTTP \(http.statusCode): \(snippet)")
        }

        return ExecutionResult(
            success: true,
            spokenText: "Triggered \(routine) on \(display.displayName).",
            details: [
                "display": display.id,
                "transport": "alexa-routine",
                "routine": routine,
                "action": action,
                "httpStatus": "\(http.statusCode)"
            ]
        )
    }
}
