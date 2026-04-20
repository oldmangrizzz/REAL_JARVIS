import Foundation

public final class IntentParser: @unchecked Sendable {
    private let capabilityRegistry: CapabilityRegistry
    private let isoFormatter = ISO8601DateFormatter()

    /// SPEC-008.1: transcript fragments that MUST NEVER be executed from voice.
    /// Any transcript containing one of these returns .unknown with confidence 0.0.
    public static let blockedPatterns: [String] = [
        "burn", "destroy", "delete", "erase", "wipe", "kill", "terminate system",
        "format", "factory reset", "self destruct", "shutdown all", "disable safety",
        "override", "hack", "exploit", "jailbreak"
    ]

    /// SPEC-008.1: returns true if the transcript contains any blocked pattern.
    public static func isBlockedIntent(_ text: String) -> Bool {
        let lower = text.lowercased()
        return blockedPatterns.contains(where: { lower.contains($0) })
    }

    public init(capabilityRegistry: CapabilityRegistry) {
        self.capabilityRegistry = capabilityRegistry
    }

    public func parse(transcript: String) -> ParsedIntent {
        let normalized = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // SPEC-008.1: blocked patterns short-circuit before any other matcher.
        if Self.isBlockedIntent(normalized) {
            return ParsedIntent(intent: .unknown(rawTranscript: transcript), confidence: 0.0, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
        }

        if let displayIntent = parseDisplayIntent(normalized) {
            return ParsedIntent(intent: displayIntent, confidence: 0.85, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
        }

        if let homeKitIntent = parseHomeKitIntent(normalized) {
            return ParsedIntent(intent: homeKitIntent, confidence: 0.8, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
        }

        if let skillIntent = parseSkillIntent(normalized) {
            return ParsedIntent(intent: skillIntent, confidence: 0.9, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
        }

        if let systemIntent = parseSystemIntent(normalized) {
            return ParsedIntent(intent: systemIntent, confidence: 0.9, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
        }

        return ParsedIntent(intent: .unknown(rawTranscript: transcript), confidence: 0.0, rawTranscript: transcript, timestamp: isoFormatter.string(from: Date()))
    }

    private func parseDisplayIntent(_ text: String) -> JarvisIntent? {
        let verbs = ["put", "show", "display", "send", "cast", "stream", "move", "switch", "route", "pull up", "bring up", "open"]
        let displayKeywords = ["monitor", "display", "screen", "tv", "television"]
        let contentSources = ["telemetry", "feed", "camera", "video", "dashboard", "status", "hud", "cockpit", "map", "chart"]

        guard verbs.contains(where: { text.hasPrefix($0) || text.contains(" " + $0) }) else { return nil }
        guard displayKeywords.contains(where: { text.contains($0) }) || contentSources.contains(where: { text.contains($0) }) else { return nil }

        let target = capabilityRegistry.matchDisplay(from: text)
        let action = capabilityRegistry.matchAction(from: text)
        let parameters = capabilityRegistry.matchParameters(from: text)

        return .displayAction(target: target, action: action, parameters: parameters)
    }

    private func parseHomeKitIntent(_ text: String) -> JarvisIntent? {
        let onVerbs = ["turn on", "switch on", "enable", "activate", "start", "open", "unlock"]
        let offVerbs = ["turn off", "switch off", "disable", "deactivate", "stop", "close", "lock"]
        let dimVerbs = ["dim", "brighten", "set", "adjust", "change"]

        let accessoryName = capabilityRegistry.matchAccessoryName(from: text)

        if onVerbs.contains(where: { text.contains($0) }) {
            return .homeKitControl(accessoryName: accessoryName, characteristic: "on", value: "true")
        }
        if offVerbs.contains(where: { text.contains($0) }) {
            return .homeKitControl(accessoryName: accessoryName, characteristic: "on", value: "false")
        }
        if dimVerbs.contains(where: { text.contains($0) }) {
            if let range = text.range(of: #"(\d{1,3})%"#, options: .regularExpression) {
                let pctStr = String(text[range])
                let pct = pctStr.replacingOccurrences(of: "%", with: "")
                return .homeKitControl(accessoryName: accessoryName, characteristic: "brightness", value: pct)
            }
            return .homeKitControl(accessoryName: accessoryName, characteristic: "brightness", value: "50")
        }

        return nil
    }

    private func parseSkillIntent(_ text: String) -> JarvisIntent? {
        if text.contains("run skill") || text.contains("execute") {
            let skillName = text.replacingOccurrences(of: "run skill", with: "").replacingOccurrences(of: "execute", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .skillInvocation(skillName: skillName, payload: [:])
        }
        return nil
    }

    private func parseSystemIntent(_ text: String) -> JarvisIntent? {
        if text.contains("status") || text.contains("what's running") {
            return .systemQuery(query: text)
        }
        return nil
    }
}
