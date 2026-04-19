import Foundation

/// Periodically syncs local JSONL telemetry to the Convex backend.
/// Best-effort only; never blocks the runtime.
public actor ConvexTelemetrySync {
    private let paths: WorkspacePaths
    private let hostNode: String
    private let convexURL: URL
    private let authToken: String?
    private let isoFormatter = ISO8601DateFormatter()
    private let session = URLSession.shared
    private var isRunning = false
    private var lastEventOffset: Int64 = 0
    private var pushFailureCount: Int64 = 0

    public init(paths: WorkspacePaths,
                hostNode: String = ProcessInfo.processInfo.hostName,
                convexURLString: String? = nil,
                authToken: String? = nil) throws {
        self.paths = paths
        self.hostNode = hostNode
        // R11: allow environment variable override for Convex URL
        let resolvedURLString = convexURLString
            ?? ProcessInfo.processInfo.environment["CONVEX_URL"]
            ?? "https://enduring-starfish-794.convex.cloud/api/mutation"
        guard let url = URL(string: resolvedURLString) else {
            throw JarvisError.processFailure("Invalid Convex URL: \(resolvedURLString)")
        }
        self.convexURL = url
        self.authToken = authToken
    }

    public func start() {
        guard !isRunning else { return }
        Task { await self.runLoop() }
    }

    private func runLoop() async {
        guard !isRunning else { return }
        isRunning = true
        while isRunning {
            await sync()
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
    }

    public func stop() {
        isRunning = false
        lastEventOffset = 0
    }

    public func sync() async {
        await syncVoiceGateState()
        await syncVoiceGateEvents()
    }

    private func syncVoiceGateState() async {
        let url = tableURL("voice_gate_state")
        guard let lastLine = readLastLine(of: url) else { return }
        guard let data = lastLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        await pushToConvex(path: "jarvis:syncVoiceGateState", args: json)
    }

    private func syncVoiceGateEvents() async {
        let url = tableURL("voice_gate_events")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        let sidecarURL = url.appendingPathExtension("synced_offset")
        var offset: Int64 = 0
        
        // Load previous offset if available, otherwise start from 0
        do {
            let data = try Data(contentsOf: sidecarURL)
            let offsetStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let o = Int64(offsetStr) {
                offset = o
            }
        } catch {
            // If sidecar missing or corrupt, start from 0; will read all lines
        }
        
        // CX-043: incremental read — seek to offset instead of full file re-read
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: url)
        } catch {
            return
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return
        }
        guard offset >= 0, UInt64(offset) < fileSize else { return }  // nothing new

        try? fileHandle.seek(toFileOffset: UInt64(clamping: offset))
        let newData = fileHandle.readDataToEndOfFile()
        guard let newContent = String(data: newData, encoding: .utf8) else { return }
        let newLines = newContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        // If nothing new, nothing to do
        if newLines.isEmpty { return }
        
        // Push each new event to Convex
        for line in newLines {
            guard let data = line.data(using: .utf8),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if json["timestamp"] == nil {
                json["timestamp"] = isoFormatter.string(from: Date())
            }
            await pushToConvex(path: "jarvis:logVoiceGateEvent", args: json)
        }
        
        // Update offset to reflect what we've processed
        do {
            try String(format: "%lld", Int64(fileSize)).write(to: sidecarURL, atomically: true, encoding: .utf8)
        } catch {
            // Best-effort: don't block if offset update fails
        }
    }

    private func pushToConvex(path: String, args: [String: Any]) async {
        var request = URLRequest(url: convexURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "path": path,
            "args": args
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try await session.data(for: request)
        } catch {
            pushFailureCount += 1
            // Observability: log first failure and every 100th thereafter to avoid log spam
            if pushFailureCount == 1 || pushFailureCount % 100 == 0 {
                let message = "Convex push failed (total failures: \(pushFailureCount)): \(path) — \(error.localizedDescription)"
                let record: [String: Any] = [
                    "source": "convex_telemetry_sync",
                    "event": "push_failure",
                    "path": path,
                    "failureCount": pushFailureCount,
                    "error": error.localizedDescription,
                    "timestamp": isoFormatter.string(from: Date())
                ]
                do {
                    let dir = paths.telemetryDirectory
                    let url = dir.appendingPathComponent("convex_sync_errors.jsonl")
                    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    if !FileManager.default.fileExists(atPath: url.path) {
                        FileManager.default.createFile(atPath: url.path, contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    if let nl = "\n".data(using: .utf8) {
                        try handle.write(contentsOf: nl)
                    }
                    try handle.close()
                } catch {
                    // Double failure — can't even write the error log. Silent.
                }
            }
        }
    }

    public func getPushFailureCount() -> Int64 {
        pushFailureCount
    }

    private func tableURL(_ name: String) -> URL {
        paths.telemetryDirectory.appendingPathComponent("\(name).jsonl")
    }

    private func readLastLine(of url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // CX-043: read from FileHandle instead of full file String(contentsOf:)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        // Read last 4KB max — any single JSONL line will fit
        let readStart = max(0, Int64(fileSize) - 4096)
        try? handle.seek(toFileOffset: UInt64(clamping: readStart))
        let tailData = handle.readDataToEndOfFile()
        guard let tail = String(data: tailData, encoding: .utf8) else { return nil }
        return tail.components(separatedBy: .newlines).filter { !$0.isEmpty }.last
    }
}
