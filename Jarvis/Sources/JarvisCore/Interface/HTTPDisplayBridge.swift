import Foundation

public final class HTTPDisplayBridge {
    public func launchApp(address: String, appId: String) async throws -> ExecutionResult {
        guard let url = URL(string: "http://\(address):3000/apps/\(appId)") else {
            throw JarvisError.invalidInput("Invalid display address: \(address)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        guard httpResponse?.statusCode == 200 else {
            throw JarvisError.processFailure("Display at \(address) returned status \(httpResponse?.statusCode ?? 0)")
        }

        return ExecutionResult(
            success: true,
            spokenText: "Launched app on HTTP display at \(address).",
            details: ["address": address, "appId": appId]
        )
    }
}
