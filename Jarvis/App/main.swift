import Foundation
import JarvisCore
import Security

struct JarvisCLI {
    static func main() {
        do {
            let paths = try WorkspacePaths.discover()
            let runtime = try JarvisRuntime(paths: paths)
            let registry = try JarvisSkillRegistry(paths: paths)
            let arguments = Array(CommandLine.arguments.dropFirst())
            let command = arguments.first ?? "list-skills"

            switch command {
            case "list-skills":
                try printJSON(registry.listPayload())
            case "run-skill":
                guard arguments.count >= 2 else {
                    throw JarvisError.invalidInput("Usage: Jarvis run-skill <skill-name> [json-payload]")
                }
                let payload = try parseJSONObject(arguments.count >= 3 ? arguments[2] : "{}")
                let result = try registry.execute(name: arguments[1], input: payload, runtime: runtime)
                try printJSON(result)
            case "repl":
                let prompt = try resolvePromptText(arguments: arguments)
                try runtime.pythonRLM.startREPL(prompt: prompt)
            case "start-interface", "interface":
                let interface = RealJarvisInterface(runtime: runtime)
                try interface.start(registry: registry)
            case "start-host-tunnel", "host-tunnel":
                let secret = try resolveTunnelSecret(paths: paths)
                let server = JarvisHostTunnelServer(runtime: runtime, registry: registry, sharedSecret: secret)
                try server.run()
            case "start-voice-bridge", "voice-bridge":
                // Lightweight HTTP front for the approved voice pipeline so
                // Obsidian (desktop + iOS/iPadOS) can read notes aloud in
                // the Jarvis-ratified voice.
                let portOverride = arguments.dropFirst().first.flatMap { UInt16($0) }
                let bridge = JarvisVoiceHTTPBridge(runtime: runtime, port: portOverride ?? 8787)
                try bridge.start()
                FileHandle.standardError.write(Data("[voice-bridge] listening on :\(portOverride ?? 8787) — bearer=\(bridge.bearerToken)\n".utf8))
                RunLoop.current.run()
            case "sync-control-plane", "control-plane":
                try printJSON(runtime.controlPlane.dashboardJSON())
            case "reseed-obsidian":
                let result = try runtime.controlPlane.synchronize(forceVaultReseed: true)
                try printJSON(result.json)
            case "self-heal":
                let result = try runtime.metaHarness.diagnoseAndRewrite(
                    workflowURL: paths.archonDirectory.appendingPathComponent("default_workflow.yaml"),
                    traceDirectory: paths.traceDirectory
                )
                try printJSON(result.json)
            case "voice-audition":
                guard arguments.count >= 2 else {
                    throw JarvisError.invalidInput("Usage: Jarvis voice-audition <text>")
                }
                let text = arguments[1]
                let token = try runtime.voice.audition(text: text)
                try printJSON([
                    "outputURL": token.outputURL.path,
                    "compositeFingerprint": token.fingerprint.composite,
                    "transcript": token.session.referenceTranscript,
                    "referenceAudio": token.session.referenceAudioURL.path,
                    "modelRepository": token.session.modelRepository,
                    "status": "awaiting-operator-approval"
                ] as [String: Any])
            case "voice-approve":
                guard arguments.count >= 2 else {
                    throw JarvisError.invalidInput("Usage: Jarvis voice-approve <operator-label> [notes]")
                }
                let operatorLabel = arguments[1]
                let notes = arguments.count >= 3 ? arguments[2] : nil
                let record = try runtime.voice.approveAudition(operatorLabel: operatorLabel, notes: notes)
                try printJSON([
                    "compositeFingerprint": record.composite,
                    "operatorLabel": record.operatorLabel,
                    "approvedAt": record.approvedAtISO8601,
                    "notes": record.notes ?? ""
                ] as [String: Any])
            case "voice-revoke":
                try runtime.voice.revokeApproval()
                try printJSON(["status": "revoked"])
            case "arc-submit":
                let (taskURL, outURL) = try parseArcSubmitArgs(arguments)
                try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
                let orchestrator = ARCSubmissionOrchestrator(
                    telemetry: runtime.telemetry,
                    physics: runtime.physics,
                    proposer: runtime.pythonRLM
                )
                // Bridge async→sync via a Sendable box; the Python subprocess is blocking.
                final class ResultBox: @unchecked Sendable {
                    var artifact: ARCSubmissionArtifact?
                    var failure: Error?
                }
                let box = ResultBox()
                let sema = DispatchSemaphore(value: 0)
                Task.detached { [orchestrator, taskURL, box, sema] in
                    do { box.artifact = try await orchestrator.run(taskFileURL: taskURL) }
                    catch { box.failure = error }
                    sema.signal()
                }
                sema.wait()
                if let e = box.failure { throw e }
                let a = box.artifact!

                // Write submission JSON
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let subData = try encoder.encode(a)
                let subURL = outURL.appendingPathComponent("\(a.taskId)-submission.json")
                try subData.write(to: subURL)

                // Emit single trailing JSON line for scripts to parse
                let line: [String: Any] = [
                    "taskId": a.taskId,
                    "candidateGrid": a.candidateGrid,
                    "latencyMs": a.latencyMs,
                    "ttl": a.ttl,
                    "witnessSha256": a.witnessSha256
                ]
                let lineData = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
                print(String(data: lineData, encoding: .utf8)!)
            default:
                fputs(usage(), stderr)
                exit(64)
            }
        } catch {
            fputs("Jarvis error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseArcSubmitArgs(_ arguments: [String]) throws -> (taskURL: URL, outURL: URL) {
        let defaultOut = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("arc-agi-submissions")
        var taskPath: String?
        var outPath = defaultOut.path
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--task":
                i += 1
                if i < arguments.count { taskPath = arguments[i] }
            case "--out":
                i += 1
                if i < arguments.count { outPath = arguments[i] }
            default: break
            }
            i += 1
        }
        guard let tp = taskPath else {
            throw JarvisError.invalidInput("Usage: Jarvis arc-submit --task <path> [--out <dir>]")
        }
        return (URL(fileURLWithPath: tp), URL(fileURLWithPath: outPath))
    }

    private static func resolveTunnelSecret(paths: WorkspacePaths) throws -> String {
        if let env = ProcessInfo.processInfo.environment["JARVIS_TUNNEL_SECRET"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fm = FileManager.default
        let dir = paths.storageRoot.appendingPathComponent("storage/tunnel", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("secret")
        if fm.fileExists(atPath: file.path),
           let raw = try? String(contentsOf: file, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        let secret = "jarvis-" + bytes.map { String(format: "%02x", $0) }.joined()
        try secret.write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return secret
    }

    private static func resolvePromptText(arguments: [String]) throws -> String {
        guard arguments.count >= 2 else {
            throw JarvisError.invalidInput("Usage: Jarvis repl <prompt-text|prompt-file>")
        }

        let candidate = arguments[1]
        let fileURL = URL(fileURLWithPath: candidate)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try String(contentsOf: fileURL, encoding: .utf8)
        }
        return candidate
    }

    private static func parseJSONObject(_ raw: String) throws -> [String: Any] {
        guard let data = raw.data(using: .utf8) else {
            throw JarvisError.invalidInput("Payload must be valid UTF-8 JSON.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw JarvisError.invalidInput("Payload must be a JSON object.")
        }
        return dictionary
    }

    private static func printJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw JarvisError.serializationFailure("Unable to encode JSON output.")
        }
        print(text)
    }

    private static func usage() -> String {
        """
        Usage:
          Jarvis list-skills
          Jarvis run-skill <skill-name> [json-payload]
          Jarvis repl <prompt-text|prompt-file>
          Jarvis start-interface
          Jarvis start-host-tunnel
          Jarvis start-voice-bridge [port]
          Jarvis sync-control-plane
          Jarvis reseed-obsidian
          Jarvis self-heal
          Jarvis voice-audition <text>
          Jarvis voice-approve <operator-label> [notes]
          Jarvis voice-revoke
          Jarvis arc-submit --task <path> [--out <dir>]
        """
    }
}

JarvisCLI.main()
