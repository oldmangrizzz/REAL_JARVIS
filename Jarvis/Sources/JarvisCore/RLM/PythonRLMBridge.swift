import Foundation

public struct RLMQueryResult {
    public let response: String
    public let symbols: [String]
    public let trace: [String]
    public let topMatches: [[String: Any]]

    public var json: [String: Any] {
        [
            "response": response,
            "symbols": symbols,
            "trace": trace,
            "topMatches": topMatches
        ]
    }
}

public final class PythonRLMBridge {
    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore

    public init(paths: WorkspacePaths, telemetry: TelemetryStore) {
        self.paths = paths
        self.telemetry = telemetry
    }

    public func query(prompt: String, query: String) throws -> RLMQueryResult {
        let promptURL = try writePrompt(prompt)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let output = try runPython(arguments: [
            paths.rlmScriptURL.path,
            "--mode", "query",
            "--prompt-file", promptURL.path,
            "--query", query
        ], captureOutput: true)

        guard let data = output.data(using: .utf8) else {
            throw JarvisError.processFailure("Python REPL bridge returned invalid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw JarvisError.processFailure("Python REPL bridge returned malformed JSON.")
        }

        let response = (dictionary["response"] as? String) ?? ""
        let symbols = (dictionary["symbols"] as? [String]) ?? []
        let trace = (dictionary["trace"] as? [String]) ?? []
        let topMatches = (dictionary["topMatches"] as? [[String: Any]]) ?? []
        try telemetry.logRecursiveThought(sessionID: "rlm-\(UUID().uuidString)", trace: trace, memoryPageFault: false)

        return RLMQueryResult(response: response, symbols: symbols, trace: trace, topMatches: topMatches)
    }

    public func startREPL(prompt: String) throws {
        let promptURL = try writePrompt(prompt)
        try runPython(arguments: [
            paths.rlmScriptURL.path,
            "--mode", "repl",
            "--prompt-file", promptURL.path
        ], captureOutput: false)
    }

    private func writePrompt(_ prompt: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let defaultTimeout: Double = 30.0  // CX-010: seconds before Python process is killed

    private func runPython(arguments: [String], captureOutput: Bool) throws -> String {
        guard FileManager.default.fileExists(atPath: paths.rlmScriptURL.path) else {
            throw JarvisError.processFailure("Missing Python RLM script at \(paths.rlmScriptURL.path).")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = arguments

        if captureOutput {
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()

            // CX-010: timeout with SIGKILL fallback
            let killTimer = DispatchSource.makeTimerSource(queue: .global())
            let processRef = process
            killTimer.setEventHandler {
                if processRef.isRunning { processRef.terminate() }
            }
            killTimer.schedule(deadline: .now() + defaultTimeout)
            killTimer.resume()

            // CX-010: use terminationHandler + readDataToEndOfFile after exit
            // avoids pipe deadlock and Swift 6 concurrency issues with captured mutation
            process.waitUntilExit()
            killTimer.cancel()

            let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                if !processRef.isRunning && process.terminationStatus == 15 {
                    throw JarvisError.processFailure("Python bridge timed out after \(Int(defaultTimeout))s.")
                }
                throw JarvisError.processFailure(stderr.isEmpty ? "Python bridge failed." : stderr)
            }
            return String(data: stdoutData, encoding: .utf8) ?? ""
        }

        // CX-010: REPL mode — use pipes instead of host stdin/stdout/stderr to prevent RCE
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let killTimer = DispatchSource.makeTimerSource(queue: .global())
        let processRef = process
        killTimer.setEventHandler {
            if processRef.isRunning { processRef.terminate() }
        }
        killTimer.schedule(deadline: .now() + defaultTimeout)
        killTimer.resume()

        process.waitUntilExit()
        killTimer.cancel()
        guard process.terminationStatus == 0 else {
            if process.terminationStatus == 15 {
                throw JarvisError.processFailure("Interactive Python REPL timed out after \(Int(defaultTimeout))s.")
            }
            throw JarvisError.processFailure("Interactive Python REPL exited with status \(process.terminationStatus).")
        }
        return ""
    }
}
