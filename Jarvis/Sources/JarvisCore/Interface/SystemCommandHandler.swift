import Foundation

/// SPEC-004: Handles `.systemQuery` and `.skillInvocation` intents parsed by
/// `IntentParser` and produces a `VoiceCommandResponse`.
///
/// This replaces the hardcoded `if command.contains("status")` branches that
/// used to live in `VoiceCommandRouter.route`. By routing *all* dispatch
/// through the IntentParser → handler chain, we can add new verbs by
/// extending the parser + handler instead of editing router internals.
public final class SystemCommandHandler: @unchecked Sendable {
    private let runtime: JarvisRuntime
    private let skillRegistry: JarvisSkillRegistry

    public init(runtime: JarvisRuntime, skillRegistry: JarvisSkillRegistry) {
        self.runtime = runtime
        self.skillRegistry = skillRegistry
    }

    public func handle(intent: ParsedIntent, command: String) throws -> VoiceCommandResponse? {
        switch intent.intent {
        case .systemQuery(let query):
            return try handleSystemQuery(query: query, command: command)
        case .skillInvocation(let skillName, _):
            return try handleSkillInvocation(requested: skillName)
        default:
            return nil
        }
    }

    // MARK: - System query dispatch

    private func handleSystemQuery(query: String, command: String) throws -> VoiceCommandResponse? {
        let q = query.lowercased()

        if q.contains("list skills") || q.contains("what can you do") {
            let callable = skillRegistry.callableSkillNames()
            let spokenList = callable
                .map { $0.replacingOccurrences(of: "-", with: " ") }
                .prefix(5)
                .joined(separator: ", ")
            return VoiceCommandResponse(
                spokenText: "Native callable skills online: \(spokenList).",
                details: ["command": "list-skills", "skills": callable],
                shouldShutdown: false
            )
        }

        if q.contains("self heal") || q.contains("heal the harness") {
            let result = try runtime.metaHarness.diagnoseAndRewrite(
                workflowURL: runtime.paths.archonDirectory.appendingPathComponent("default_workflow.yaml"),
                traceDirectory: runtime.paths.traceDirectory
            )
            let spoken = result.mutationApplied
                ? "I've rewritten the harness and closed the failure pocket."
                : "The harness is already holding together rather well."
            return VoiceCommandResponse(spokenText: spoken, details: result.json, shouldShutdown: false)
        }

        if q.contains("recall") || q.contains("what happened") {
            let page = try runtime.memory.pageIn(query: command, limit: 3)
            let spoken = page.matches.first.map { "Here's the strongest memory trace: \($0)" } ?? "I don't yet have a strong memory trace for that."
            return VoiceCommandResponse(spokenText: spoken, details: page.json, shouldShutdown: false)
        }

        if q.contains("shutdown") || q.contains("go quiet") || q.contains("stop listening") {
            return VoiceCommandResponse(
                spokenText: "Very good. Going quiet now.",
                details: ["command": "shutdown"],
                shouldShutdown: true
            )
        }

        // Default: `.systemQuery` fell through to generic status report.
        let callable = skillRegistry.callableSkillNames()
        let sampleCount = (try? runtime.paths.audioSampleURLs().count) ?? 0
        let summary = "Systems are online. I have \(skillRegistry.allSkillNames().count) indexed skills, \(callable.count) native callable skills, and \(sampleCount) local voice reference samples ready."
        return VoiceCommandResponse(
            spokenText: summary,
            details: [
                "command": "status",
                "indexedSkills": skillRegistry.allSkillNames().count,
                "callableSkills": callable
            ],
            shouldShutdown: false
        )
    }

    // MARK: - Skill invocation

    private func handleSkillInvocation(requested: String) throws -> VoiceCommandResponse? {
        let normalized = normalizedSkillFragment(from: requested)
        if let matched = bestSkillMatch(for: normalized) {
            let payload = defaultPayload(for: matched)
            let result = try skillRegistry.execute(name: matched, input: payload, runtime: runtime)
            let spoken = "Executed \(matched.replacingOccurrences(of: "-", with: " "))."
            return VoiceCommandResponse(spokenText: spoken, details: result, shouldShutdown: false)
        }
        return VoiceCommandResponse(
            spokenText: "I couldn't match that to a native skill, which is irritatingly unhelpful of reality.",
            details: ["command": "run-skill", "requested": normalized],
            shouldShutdown: false
        )
    }

    private func normalizedSkillFragment(from text: String) -> String {
        let lowered = text.lowercased()
        let stripped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == " " ? ch : " "
        }
        return String(stripped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")
    }

    private func bestSkillMatch(for requested: String) -> String? {
        let normalizedRequested = requested.replacingOccurrences(of: "--", with: "-")
        guard !normalizedRequested.isEmpty else { return nil }
        return skillRegistry.callableSkillNames().first { skill in
            skill == normalizedRequested || skill.contains(normalizedRequested) || normalizedRequested.contains(skill)
        }
    }

    private func defaultPayload(for skill: String) -> [String: Any] {
        switch skill {
        case "stigmergic-regulation-skill":
            return [
                "source": "planning",
                "target": "implementation",
                "currentPheromone": 0.5,
                "deposits": [["signal": 1, "magnitude": 1.0, "agentID": "voice-interface"]]
            ]
        case "recursive-language-model-repl-skill":
            return [
                "prompt": "J.A.R.V.I.S. interface runtime context.",
                "query": "Summarize the active interface state."
            ]
        case "memory-tier-memify-skill":
            return ["query": "latest interface activity"]
        case "zero-shot-voice-synthesis-skill":
            return ["text": "The interface is online and listening."]
        case "meta-harness-convex-observability-skill":
            return ["workflowPath": "Archon/default_workflow.yaml"]
        default:
            return [:]
        }
    }
}
