import Foundation
import JarvisCore

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
                let server = JarvisHostTunnelServer(runtime: runtime, registry: registry)
                try server.run()
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
            default:
                fputs(usage(), stderr)
                exit(64)
            }
        } catch {
            fputs("Jarvis error: \(error)\n", stderr)
            exit(1)
        }
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
          Jarvis sync-control-plane
          Jarvis reseed-obsidian
          Jarvis self-heal
          Jarvis voice-audition <text>
          Jarvis voice-approve <operator-label> [notes]
          Jarvis voice-revoke
        """
    }
}

JarvisCLI.main()
