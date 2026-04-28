import Foundation

public enum JarvisMemorySurfaceRole: String, Codable, Equatable, Sendable {
    case identityAnchor
    case localWitnessedShard
    case agentMemory
    case semanticGraphRecall
    case realtimeStateBus
    case knowledgeCabinet
}

public enum JarvisMemorySurfaceState: String, Codable, Equatable, Sendable {
    case online
    case configured
    case degraded
    case missing
}

public struct JarvisMemorySurfaceStatus: Codable, Sendable {
    public let name: String
    public let role: JarvisMemorySurfaceRole
    public let state: JarvisMemorySurfaceState
    public let authority: String
    public let details: [String: String]

    public init(
        name: String,
        role: JarvisMemorySurfaceRole,
        state: JarvisMemorySurfaceState,
        authority: String,
        details: [String: String] = [:]
    ) {
        self.name = name
        self.role = role
        self.state = state
        self.authority = authority
        self.details = details
    }

    public var json: [String: Any] {
        [
            "name": name,
            "role": role.rawValue,
            "state": state.rawValue,
            "authority": authority,
            "details": details
        ]
    }
}

public struct JarvisMemoryFabricStatus: Codable, Sendable {
    public let canonicalSummary: String
    public let securityPosture: String
    public let surfaces: [JarvisMemorySurfaceStatus]

    public init(
        canonicalSummary: String,
        securityPosture: String,
        surfaces: [JarvisMemorySurfaceStatus]
    ) {
        self.canonicalSummary = canonicalSummary
        self.securityPosture = securityPosture
        self.surfaces = surfaces
    }

    public var json: [String: Any] {
        [
            "canonicalSummary": canonicalSummary,
            "securityPosture": securityPosture,
            "surfaces": surfaces.map(\.json)
        ]
    }
}

public struct JarvisMemoryFabricRecall {
    public let query: String
    public let external: ExternalMemoryRecall?
    public let local: PageInResult

    public var preferredSpokenSummary: String? {
        if let external, !external.isEmpty {
            return external.spokenSummary
        }
        return local.matches.first
    }

    public var source: String {
        if let external, !external.isEmpty {
            return "external-memory-fabric"
        }
        return "local-memory-shard"
    }

    public var json: [String: Any] {
        [
            "query": query,
            "source": source,
            "external": external?.json ?? [:],
            "local": local.json
        ]
    }
}

public final class JarvisRuntime {
    public let paths: WorkspacePaths
    public let soulAnchor: SoulAnchor
    public let telemetry: TelemetryStore
    public let pheromind: PheromindEngine
    public let memory: MemoryEngine
    public let pythonRLM: PythonRLMBridge
    public let retrievalBridge: ContextualRetrievalBridge
    public let voice: JarvisVoicePipeline
    public let metaHarness: MetaHarness
    public let controlPlane: MyceliumControlPlane
    public let oscillator: MasterOscillator
    public let phaseLock: PhaseLockMonitor
    public let telemetrySync: ConvexTelemetrySync
    public let physics: PhysicsEngine
    public let physicsSummarizer: PhysicsSummarizer
    public let arcBridge: ARCHarnessBridge
    public let presenceRouter: PresenceEventRouter
    public let externalMemory: ExternalMemoryBridge?
    public let lettaBridge: ResilientLettaBridge?

    public init(paths: WorkspacePaths, startTelemetrySync: Bool? = nil, bootstrapExternalMemory: Bool? = nil) throws {
        self.paths = paths
        try paths.ensureSupportDirectories()
        self.soulAnchor = try SoulAnchor.load(paths: paths)
        try self.soulAnchor.verify()
        self.telemetry = try TelemetryStore(paths: paths)
        let aox4 = AOxFourProbe(paths: paths, telemetry: telemetry)
        _ = try aox4.requireFullOrientation()
        self.pheromind = PheromindEngine(telemetry: telemetry)
        self.memory = try MemoryEngine(paths: paths, telemetry: telemetry)
        self.pythonRLM = PythonRLMBridge(paths: paths, telemetry: telemetry)
        self.retrievalBridge = ContextualRetrievalBridge(memory: memory, pheromind: pheromind)
        self.voice = JarvisVoicePipeline(paths: paths, telemetry: telemetry)
        self.metaHarness = MetaHarness(paths: paths, telemetry: telemetry)
        self.controlPlane = try MyceliumControlPlane(paths: paths, telemetry: telemetry)
        self.oscillator = MasterOscillator(telemetry: telemetry)
        self.phaseLock = PhaseLockMonitor(telemetry: telemetry)
        let shouldStartTelemetrySync = startTelemetrySync ?? Self.shouldStartTelemetrySync()
        self.telemetrySync = try ConvexTelemetrySync(paths: paths, warnWhenUnauthenticated: shouldStartTelemetrySync)
        self.physics = StubPhysicsEngine()
        self.physicsSummarizer = PhysicsSummarizer()
        self.arcBridge = ARCHarnessBridge(
            broadcasterURL: URL(string: "ws://localhost:8765")!,
            telemetry: telemetry,
            engine: self.physics
        )
        self.presenceRouter = PresenceEventRouter(
            voice: self.voice,
            telemetry: self.telemetry,
            voiceCacheDirectory: paths.voiceCacheDirectory
        )
        self.externalMemory = ExternalMemoryBridge(paths: paths, telemetry: telemetry)
        self.lettaBridge = Self.makeLettaBridge(paths: paths)
        let shouldBootstrapExternalMemory = bootstrapExternalMemory ?? Self.shouldBootstrapExternalMemory()
        if shouldBootstrapExternalMemory, let externalMemory = self.externalMemory {
            do {
                let result = try externalMemory.syncSession()
                try telemetry.logExecutionTrace(
                    workflowID: "external-memory",
                    stepID: "session-start",
                    inputContext: "boot",
                    outputResult: Self.describe(result),
                    status: "success"
                )
            } catch {
                let message = "ExternalMemoryBridge bootstrap failed: \(error)"
                do {
                    try telemetry.logExecutionTrace(
                        workflowID: "external-memory",
                        stepID: "session-start",
                        inputContext: "boot",
                        outputResult: message,
                        status: "error"
                    )
                } catch {
                    FileHandle.standardError.write(Data("JarvisRuntime telemetry bootstrap log failed: \(error)\n".utf8))
                }
                FileHandle.standardError.write(Data(message.appending("\n").utf8))
            }
        }
        if shouldStartTelemetrySync {
            Task.detached { [telemetrySync] in
                await telemetrySync.start()
            }
        }
    }

    public func memoryFabricStatus() -> JarvisMemoryFabricStatus {
        let env = JarvisRuntimeEnvironment.resolved(root: paths.root)
        let obsidianPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Obsidian Vault", isDirectory: true)
        let obsidianExists = FileManager.default.fileExists(atPath: obsidianPath.path)
        let externalDetails = externalMemory?.status ?? [:]
        let convexHasAuth = !(env["JARVIS_CONVEX_AUTH_TOKEN"] ?? env["CONVEX_DEPLOYMENT_KEY"] ?? "").isEmpty
        let convexURL = env["CONVEX_URL"]
            ?? env["JARVIS_CONVEX_URL"]
            ?? "https://enduring-starfish-794.convex.cloud/api/mutation"

        let surfaces = [
            JarvisMemorySurfaceStatus(
                name: "SoulAnchor",
                role: .identityAnchor,
                state: .online,
                authority: "identity continuity and canon binding",
                details: ["root": paths.root.path]
            ),
            JarvisMemorySurfaceStatus(
                name: "MemoryEngine",
                role: .localWitnessedShard,
                state: .online,
                authority: "authoritative local witnessed memory shard",
                details: [
                    "nodes": String(memory.graph.nodes.count),
                    "edges": String(memory.graph.edges.count),
                    "v1Path": paths.storageDirectory.appendingPathComponent(MemoryMigration.v1FileName).path
                ]
            ),
            JarvisMemorySurfaceStatus(
                name: "Letta/MemGPT",
                role: .agentMemory,
                state: externalMemory == nil ? .missing : .configured,
                authority: "durable conversational agent memory; not a chat model identity substitute",
                details: stringDetails(from: externalDetails, allowedKeys: ["baseURL", "agentID", "model"])
            ),
            JarvisMemorySurfaceStatus(
                name: "Cognee",
                role: .semanticGraphRecall,
                state: externalMemory == nil ? .missing : .configured,
                authority: "semantic graph recall and corpus retrieval through the external memory bridge",
                details: stringDetails(from: externalDetails, allowedKeys: ["embeddingModel", "bridgeConfigPath", "scriptsDirectory"])
            ),
            JarvisMemorySurfaceStatus(
                name: "Convex",
                role: .realtimeStateBus,
                state: convexHasAuth ? .configured : .degraded,
                authority: "real-time sync and node state bus; not long-term autobiographical memory",
                details: [
                    "url": convexURL,
                    "authenticated": convexHasAuth ? "true" : "false"
                ]
            ),
            JarvisMemorySurfaceStatus(
                name: "Obsidian",
                role: .knowledgeCabinet,
                state: obsidianExists ? .configured : .missing,
                authority: "knowledge wiki, corpus, and operator IDE; never the mind or identity root",
                details: ["path": obsidianPath.path]
            )
        ]

        let securityPosture = convexHasAuth
            ? "memory surfaces are explicitly role-separated; external sync has an auth token configured"
            : "memory surfaces are explicitly role-separated; Convex telemetry auth is not configured for this process"

        return JarvisMemoryFabricStatus(
            canonicalSummary: "JARVIS identity is anchored by SoulAnchor and expressed through the memory fabric. Obsidian is a knowledge cabinet, not the brain.",
            securityPosture: securityPosture,
            surfaces: surfaces
        )
    }

    public func recallMemory(query: String, limit: Int = 3) throws -> JarvisMemoryFabricRecall {
        let external = try externalMemory?.recall(query: query)
        let local = try memory.pageIn(query: query, limit: limit)
        return JarvisMemoryFabricRecall(query: query, external: external, local: local)
    }

    private static func shouldStartTelemetrySync() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if isEnabled(env["JARVIS_DISABLE_TELEMETRY_SYNC"]) {
            return false
        }
        if isEnabled(env["CI"]) && !isEnabled(env["JARVIS_ENABLE_TELEMETRY_SYNC_IN_CI"]) {
            return false
        }
        return true
    }

    private static func shouldBootstrapExternalMemory() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if isEnabled(env["JARVIS_DISABLE_EXTERNAL_MEMORY_BOOTSTRAP"]) {
            return false
        }
        if isEnabled(env["CI"]) && !isEnabled(env["JARVIS_ENABLE_EXTERNAL_MEMORY_BOOTSTRAP_IN_CI"]) {
            return false
        }
        return true
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func makeLettaBridge(paths: WorkspacePaths) -> ResilientLettaBridge? {
        let env = JarvisRuntimeEnvironment.resolved(root: paths.root)
        guard let raw = env["JARVIS_LETTA_BASE_URL"] ?? env["LETTA_BASE_URL"],
              let url = URL(string: raw) else {
            return nil
        }
        // H2: Letta exclusivity preflight. The Letta server on Alpha LXC 201
        // stores episodic memory for a *digital person* (see PRINCIPLES.md §1,
        // Natural-Language Barrier). If that same Letta instance is shared
        // with any other persona/project the substrate-merger invariant is
        // violated. We require operator attestation via env var. Default
        // (unset / not "true") disables the bridge; memory stays local in
        // .jarvis/storage/ via MemoryEngine.
        let exclusive = (env["JARVIS_LETTA_EXCLUSIVE"] ?? "").lowercased()
        guard exclusive == "true" || exclusive == "1" || exclusive == "yes" else {
            return nil
        }
        let inner = LettaBridge(
            baseURL: url,
            bearerToken: env["JARVIS_LETTA_TOKEN"] ?? env["LETTA_API_KEY"]
        )
        return ResilientLettaBridge(inner: inner)
    }

    private static func describe(_ value: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private func stringDetails(from payload: [String: Any], allowedKeys: [String]) -> [String: String] {
        var details: [String: String] = [:]
        for key in allowedKeys {
            guard let value = payload[key] else { continue }
            details[key] = String(describing: value)
        }
        return details
    }
}

public struct JarvisBridgeConfiguration: Codable, Sendable {
    public let baseURL: URL
    public let agentID: String
    public let model: String?
    public let embeddingModel: String?
    public let vaultPath: String?
    public let vaultWriteFolder: String?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case agentID = "agent_id"
        case model
        case embeddingModel = "embedding_model"
        case vaultPath = "vault_path"
        case vaultWriteFolder = "vault_write_folder"
    }

    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("letta-runtime", isDirectory: true)
            .appendingPathComponent("bridge.json")
    }

    public static func load(from url: URL) throws -> JarvisBridgeConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(JarvisBridgeConfiguration.self, from: data)
    }

    public static func loadIfPresent(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> JarvisBridgeConfiguration? {
        let url = defaultURL(homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? load(from: url)
    }

    public var json: [String: Any] {
        [
            "baseURL": baseURL.absoluteString,
            "agentID": agentID,
            "model": model ?? "",
            "embeddingModel": embeddingModel ?? "",
            "vaultPath": vaultPath ?? "",
            "vaultWriteFolder": vaultWriteFolder ?? ""
        ]
    }
}

public enum JarvisRuntimeEnvironment {
    public static func resolved(
        root: URL? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var merged = processEnvironment
        for candidate in dotEnvCandidates(root: root, homeDirectory: homeDirectory) {
            guard FileManager.default.fileExists(atPath: candidate.path),
                  let text = try? String(contentsOf: candidate, encoding: .utf8) else {
                continue
            }
            for (key, value) in parseDotEnv(text) where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }

    static func dotEnvCandidates(root: URL?, homeDirectory: URL) -> [URL] {
        var ordered: [URL] = []
        func appendUnique(_ url: URL) {
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            guard !ordered.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == normalized }) else {
                return
            }
            ordered.append(normalized)
        }
        if let root {
            appendUnique(root.appendingPathComponent(".env"))
        }
        appendUnique(homeDirectory.appendingPathComponent("real_jarvis/.env"))
        appendUnique(homeDirectory.appendingPathComponent("REAL_JARVIS/.env"))
        return ordered
    }

    static func parseDotEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" || first == "'"),
               first == last {
                value.removeFirst()
                value.removeLast()
            } else if let commentStart = value.firstIndex(of: "#") {
                value = String(value[..<commentStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            values[key] = value
        }
        return values
    }
}

public struct ExternalMemoryRecall: Sendable {
    public let query: String
    public let additionalContext: String
    public let systemMessage: String?

    public var isEmpty: Bool {
        additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var spokenSummary: String? {
        additionalContext
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first {
                !$0.isEmpty &&
                !$0.hasPrefix("===") &&
                !$0.lowercased().hasPrefix("bridge recall")
            }?
            .replacingOccurrences(of: "- ", with: "")
    }

    public var json: [String: Any] {
        [
            "query": query,
            "additionalContext": additionalContext,
            "systemMessage": systemMessage ?? "",
            "isEmpty": isEmpty,
            "spokenSummary": spokenSummary ?? ""
        ]
    }
}

public final class ExternalMemoryBridge: @unchecked Sendable {
    private let paths: WorkspacePaths
    private let telemetry: TelemetryStore
    private let bridgeConfig: JarvisBridgeConfiguration
    private let bridgeConfigURL: URL
    private let scriptsDirectory: URL
    private let pythonExecutableURL: URL
    private let environment: [String: String]
    private let timeoutSeconds: TimeInterval = 90

    public convenience init?(paths: WorkspacePaths, telemetry: TelemetryStore) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bridgeConfigURL = JarvisBridgeConfiguration.defaultURL(homeDirectory: home)
        let scriptsDirectory = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("vendor", isDirectory: true)
            .appendingPathComponent("cognee-integrations", isDirectory: true)
            .appendingPathComponent("integrations", isDirectory: true)
            .appendingPathComponent("claude-code", isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: bridgeConfigURL.path),
              FileManager.default.fileExists(atPath: scriptsDirectory.path),
              let config = try? JarvisBridgeConfiguration.load(from: bridgeConfigURL) else {
            return nil
        }
        let environment = JarvisRuntimeEnvironment.resolved(root: paths.root)
        self.init(
            paths: paths,
            telemetry: telemetry,
            bridgeConfig: config,
            bridgeConfigURL: bridgeConfigURL,
            scriptsDirectory: scriptsDirectory,
            pythonExecutableURL: Self.resolveBridgePython(environment: environment, homeDirectory: home),
            environment: environment
        )
    }

    private static func resolveBridgePython(environment: [String: String], homeDirectory: URL) -> URL {
        let fileManager = FileManager.default
        if let override = environment["JARVIS_MEMORY_BRIDGE_PYTHON"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let cogneeVenv = homeDirectory
            .appendingPathComponent(".jarvis", isDirectory: true)
            .appendingPathComponent("cognee-venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        if fileManager.isExecutableFile(atPath: cogneeVenv.path) {
            return cogneeVenv
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    init(
        paths: WorkspacePaths,
        telemetry: TelemetryStore,
        bridgeConfig: JarvisBridgeConfiguration,
        bridgeConfigURL: URL,
        scriptsDirectory: URL,
        pythonExecutableURL: URL,
        environment: [String: String]
    ) {
        self.paths = paths
        self.telemetry = telemetry
        self.bridgeConfig = bridgeConfig
        self.bridgeConfigURL = bridgeConfigURL
        self.scriptsDirectory = scriptsDirectory
        self.pythonExecutableURL = pythonExecutableURL
        self.environment = environment
    }

    public var status: [String: Any] {
        var payload = bridgeConfig.json
        payload["configured"] = true
        payload["bridgeConfigPath"] = bridgeConfigURL.path
        payload["scriptsDirectory"] = scriptsDirectory.path
        return payload
    }

    public func syncSession() throws -> [String: Any] {
        let output = try runBridgeScript(
            named: "bridge-session-start.py",
            arguments: [],
            payload: ["source": "archon-runtime", "workspaceRoot": paths.root.path]
        )
        let result = try decodeJSONObject(from: output)
        record(stepID: "session-start", input: "boot", output: output.isEmpty ? "{}" : output, status: "success")
        return result
    }

    public func recall(query: String) throws -> ExternalMemoryRecall {
        let output = try runBridgeScript(
            named: "bridge-context-lookup.py",
            arguments: [],
            payload: ["prompt": query]
        )
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            record(stepID: "recall", input: query, output: "empty", status: "success")
            return ExternalMemoryRecall(query: query, additionalContext: "", systemMessage: nil)
        }
        let decoded = try decodeJSONObject(from: output)
        let hookSpecific = decoded["hookSpecificOutput"] as? [String: Any]
        let recall = ExternalMemoryRecall(
            query: query,
            additionalContext: hookSpecific?["additionalContext"] as? String ?? "",
            systemMessage: hookSpecific?["systemMessage"] as? String
        )
        record(stepID: "recall", input: query, output: output, status: "success")
        return recall
    }

    public func storeAssistantMessage(_ message: String) throws -> [String: Any] {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JarvisError.invalidInput("ExternalMemoryBridge.storeAssistantMessage requires non-empty text.")
        }
        let output = try runBridgeScript(
            named: "bridge-store-to-memory.py",
            arguments: ["--stop"],
            payload: ["assistant_message": trimmed]
        )
        let decoded = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ["status": "stored", "bytes": trimmed.count] as [String: Any]
            : try decodeJSONObject(from: output)
        record(stepID: "store", input: trimmed, output: output.isEmpty ? "{\"status\":\"stored\"}" : output, status: "success")
        return decoded
    }

    private func runBridgeScript(named scriptName: String, arguments: [String], payload: [String: Any]) throws -> String {
        let scriptURL = scriptsDirectory.appendingPathComponent(scriptName)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw JarvisError.processFailure("Missing bridge script at \(scriptURL.path).")
        }

        let process = Process()
        process.executableURL = pythonExecutableURL
        process.arguments = [scriptURL.path] + arguments
        process.environment = environment.merging([
            "PYTHONIOENCODING": "utf-8",
            "PYTHONUNBUFFERED": "1"
        ]) { current, _ in current }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let stdinData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        stdinPipe.fileHandleForWriting.write(stdinData)
        try stdinPipe.fileHandleForWriting.close()

        let killTimer = DispatchSource.makeTimerSource(queue: .global())
        let processRef = process
        killTimer.setEventHandler {
            if processRef.isRunning {
                processRef.terminate()
            }
        }
        killTimer.schedule(deadline: .now() + timeoutSeconds)
        killTimer.resume()
        process.waitUntilExit()
        killTimer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            record(stepID: scriptName, input: String(data: stdinData, encoding: .utf8) ?? "", output: stderr, status: "error")
            if process.terminationStatus == 15 {
                throw JarvisError.processFailure("Bridge script \(scriptName) timed out after \(Int(timeoutSeconds))s.")
            }
            throw JarvisError.processFailure(stderr.isEmpty ? "Bridge script \(scriptName) failed." : stderr)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    private func decodeJSONObject(from output: String) throws -> [String: Any] {
        guard let data = output.data(using: .utf8) else {
            throw JarvisError.processFailure("Bridge script returned invalid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw JarvisError.processFailure("Bridge script returned malformed JSON.")
        }
        return dictionary
    }

    private func record(stepID: String, input: String, output: String, status: String) {
        do {
            try telemetry.logExecutionTrace(
                workflowID: "external-memory",
                stepID: stepID,
                inputContext: String(input.prefix(512)),
                outputResult: String(output.prefix(2_000)),
                status: status
            )
        } catch {
            FileHandle.standardError.write(Data("ExternalMemoryBridge telemetry failed: \(error)\n".utf8))
        }
    }
}
