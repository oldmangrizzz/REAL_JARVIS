import Foundation
import os

private let arcBridgeLog = Logger(subsystem: "ai.realjarvis", category: "arc-bridge")

// MARK: - ARC-AGI Harness Bridge

/// WebSocket sender to ARC-AGI broadcaster. Connects to ws://localhost:8765.
/// Accepts ARC task JSON files, loads grids into physics engine, emits
/// hypothesis/grid/score/action messages, maintains proper lifecycle.
/// Note: This is a sender-only bridge (not a display client).
public actor ARCHarnessBridge {
    private let broadcasterURL: URL
    private let telemetry: TelemetryStore
    private let engine: PhysicsEngine
    private let physicsBridge: ARCPhysicsBridge
    private var loopTask: Task<Void, Never>?
    private var isRunning = false
    private var processedFiles: Set<String> = []  // CX-012: track already-processed files

    public init(broadcasterURL: URL, telemetry: TelemetryStore, engine: PhysicsEngine? = nil) {
        self.broadcasterURL = broadcasterURL
        self.telemetry = telemetry
        let e = engine ?? StubPhysicsEngine()
        self.engine = e
        self.physicsBridge = ARCPhysicsBridge(engine: e)
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        tearDownWebSocket()
    }

    private func runLoop() async {
        guard !isRunning else { return }
        isRunning = true

        while !Task.isCancelled {
            await processPendingTasks()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }

        isRunning = false
    }

    private func processPendingTasks() async {
        let tasksDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("arc-agi-tasks")

        guard FileManager.default.fileExists(atPath: tasksDir.path) else {
            logTelemetry(event: "Tasks directory not found: \(tasksDir.path)")
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: tasksDir, includingPropertiesForKeys: [])
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            let maxTaskFileSize: UInt64 = 1_048_576 // 1MB

            for fileURL in jsonFiles {
                // CX-012: skip files already processed
                let fileKey = fileURL.lastPathComponent
                if processedFiles.contains(fileKey) { continue }

                // Resolve symlinks and verify path stays inside tasks directory
                let resolved = fileURL.resolvingSymlinksInPath()
                let tasksResolved = tasksDir.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(tasksResolved.path) else {
                    logTelemetry(event: "Rejected symlink escape: \(fileURL.lastPathComponent)")
                    continue
                }

                // Verify regular file and check size
                let attrs = try FileManager.default.attributesOfItem(atPath: resolved.path)
                guard let fileType = attrs[.type] as? FileAttributeType, fileType == .typeRegular else {
                    logTelemetry(event: "Skipped non-regular file: \(fileURL.lastPathComponent)")
                    continue
                }
                guard let fileSize = attrs[.size] as? UInt64, fileSize <= maxTaskFileSize else {
                    logTelemetry(event: "Rejected oversized file (\(attrs[.size] ?? 0) bytes): \(fileURL.lastPathComponent)")
                    continue
                }

                let data = try Data(contentsOf: resolved)
                let task = try JSONDecoder().decode(ARCTask.self, from: data)
                logTelemetry(event: "Loaded ARC task: \(fileURL.lastPathComponent) — \(task.train.count) train, \(task.test.count) test")

                // Load first training input into physics world
                if let first = task.train.first {
                    let mapping = try physicsBridge.loadGrid(first.input)
                    logTelemetry(event: "Grid loaded into physics: \(mapping.count) bodies")
                }
                processedFiles.insert(fileKey)  // CX-012: mark as processed
            }
        } catch {
            logTelemetry(event: "Error scanning tasks directory: \(error)")
        }
    }

    // MARK: - WebSocket Send

    private var webSocket: URLSessionWebSocketTask?

    public func emitState(_ payload: [String: String]) async {
        await sendJSON(type: "state", payload: payload)
    }

    public func emitHypothesis(_ payload: [String: String]) async {
        await sendJSON(type: "hypothesis", payload: payload)
    }

    public func emitGrid(_ payload: [String: String]) async {
        await sendJSON(type: "grid", payload: payload)
    }

    public func emitScore(_ payload: [String: String]) async {
        await sendJSON(type: "score", payload: payload)
    }

    public func emitAction(_ payload: [String: String]) async {
        await sendJSON(type: "action", payload: payload)
    }

    private func sendJSON(type: String, payload: [String: String]) async {
        let message: [String: Any] = ["type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []),
              let json = String(data: data, encoding: .utf8) else {
            logTelemetry(event: "Failed to serialize \(type) message")
            return
        }

        let task = ensureWebSocket()
        do {
            try await task.send(.string(json))
        } catch {
            logTelemetry(event: "WebSocket send failed: \(error.localizedDescription)")
            tearDownWebSocket()
        }
    }

    private func ensureWebSocket() -> URLSessionWebSocketTask {
        if let existing = webSocket, existing.state == .running {
            return existing
        }
        tearDownWebSocket()
        let task = URLSession.shared.webSocketTask(with: broadcasterURL)
        task.resume()
        logTelemetry(event: "WebSocket connected to \(broadcasterURL.absoluteString)")
        webSocket = task
        return task
    }

    private func tearDownWebSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    // MARK: - Telemetry

    private func logTelemetry(event: String) {
        do {
            try telemetry.append(record: [
                "source": "arc_agi_bridge",
                "event": event,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ], to: "arc_agi_events")
        } catch {
            arcBridgeLog.error("ARC telemetry write failed: \(error.localizedDescription, privacy: .public) — event: \(event, privacy: .public)")
        }
    }
}
