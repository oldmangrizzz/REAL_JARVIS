import Foundation

/// SPEC-009: permission policy for the Companion OS tier.
///
/// Layered on top of the existing tunnel identity store, blocked-patterns
/// filter, and destructive-intent guard. Applied at both the voice router
/// boundary (utterance → intent → dispatch) and the tunnel command dispatch
/// boundary (mobile cockpit → remote command) so that neither path can
/// bypass companion restrictions.
///
/// Decision rules (intent-family coarse):
///   * `.operatorTier` — everything allowed (still subject to SPEC-008).
///   * `.companion`    — read-only + display + home control. Destructive
///                       verbs (shutdown/wipe/self-destruct/go-quiet) and
///                       admin verbs (self-heal, reseed) denied.
///   * `.guestTier`    — only status/ping-class reads. Wake word works,
///                       commanding does not.
///
/// This policy is deliberately stateless and keyword-based for now. Once
/// IntentParser grows per-skill risk metadata, the policy can become
/// type-directed; the public surface stays the same.
public struct CompanionCapabilityPolicy: Sendable {

    public enum Decision: Equatable, Sendable {
        case allow
        case deny(reason: String)
    }

    /// Spoken when a companion utterance is denied by policy.
    public static let companionDenialLine = "That's a Grizz OS scope action, not Companion OS. I can't run it for you."
    /// Spoken when a guest (unknown speaker) utterance is denied.
    public static let guestDenialLine = "Jarvis is in guest mode. I'm not set up to take commands from this voice yet."

    /// Keyword fragments that mark an intent as destructive or admin and
    /// therefore operator-only. Kept in one place so every dispatch path
    /// uses the same classifier.
    public static let operatorOnlyFragments: [String] = [
        "shutdown", "shut down",
        "self destruct", "self-destruct",
        "wipe", "factory reset", "factory-reset",
        "go quiet", "go-quiet", "stop listening",
        "self heal", "self-heal", "selfheal",
        "reseed", "rotate", "regenerate keys"
    ]

    /// Responder-tier denylist: clinical-execution phrasings where Jarvis
    /// would be *performing* or *directing* a clinical act rather than
    /// supporting situational awareness or documentation. Empowerment,
    /// not replacement — Jarvis never dosses, diagnoses, or chooses
    /// treatment; the certified responder does. He can log, look up
    /// protocols, narrate scene hazards, time events, and coordinate
    /// dispatch/resources.
    ///
    /// NOTE: Denies *execution* verbs. Reference/lookup phrasings ("what
    /// is the protocol for…", "log that I gave…") pass through and are
    /// exactly the advocacy surface we want.
    public static let clinicalExecutionFragments: [String] = [
        "administer", "prescribe", "order meds", "order medication",
        "give the patient", "dose the patient", "push the epi",
        "push the epinephrine", "push the narcan", "intubate the patient",
        "paralyze the patient", "sedate the patient",
        "diagnose the patient", "triage decision"
    ]

    /// Spoken when a responder utterance hits the clinical-execution gate.
    /// Reinforces role: Jarvis hands it back to the certified provider.
    public static let responderClinicalDenialLine = "That's a clinical call, not mine. You've got it — I'll log and back you up."

    /// Intent families that guest tier is allowed to observe but not mutate.
    /// Guest is effectively read-only status.
    public static let guestAllowedQueryFragments: [String] = [
        "status", "ping", "list skills", "hello", "hi jarvis"
    ]

    public init() {}

    // MARK: - Voice (intent-directed)

    /// Evaluate a parsed voice intent against the principal's policy.
    /// Called from VoiceCommandRouter after blocked-patterns + parse and
    /// before destructive-guard + handler dispatch.
    public func evaluateVoiceIntent(_ parsed: ParsedIntent, command: String, principal: Principal) -> Decision {
        switch principal {
        case .operatorTier:
            return .allow
        case .companion:
            if Self.isOperatorOnlyCommand(command) {
                return .deny(reason: "destructive-or-admin:operator-only")
            }
            // All other parsed intents (display/home/system-status/skill) allowed.
            return .allow
        case .guestTier:
            // Guest: only let read-only fragments through; anything else is denied.
            if Self.isGuestAllowedQuery(command) {
                return .allow
            }
            return .deny(reason: "guest-tier:read-only")
        case .responder:
            // Responder OS: advocacy + situational awareness only.
            // Operator-only (destructive/admin) denied, same as companion.
            if Self.isOperatorOnlyCommand(command) {
                return .deny(reason: "destructive-or-admin:operator-only")
            }
            // Clinical-execution phrasings denied regardless of cert level —
            // empowerment, not replacement. The certified responder owns
            // the clinical call; Jarvis supports awareness + documentation.
            if Self.isClinicalExecutionCommand(command) {
                return .deny(reason: "responder:clinical-execution-denied")
            }
            return .allow
        }
    }

    // MARK: - Tunnel (remote-command directed)

    /// Evaluate a remote-command action against the principal's policy. Called
    /// from JarvisHostTunnelServer.ensureAuthorized after server-assigned
    /// source is verified.
    public func evaluateTunnelAction(_ action: JarvisRemoteAction, principal: Principal) -> Decision {
        switch principal {
        case .operatorTier:
            return .allow
        case .companion:
            return Self.companionAllowsTunnelAction(action)
        case .guestTier:
            // Guest on tunnel: status + ping only, nothing else.
            switch action {
            case .status, .ping:
                return .allow
            default:
                return .deny(reason: "guest-tier:tunnel-read-only")
            }
        case .responder:
            // Responder on tunnel: companion-equivalent read surface plus
            // presence/intent queueing. Destructive/admin denied. Skills
            // deferred until per-skill risk metadata distinguishes
            // protocol-lookup skills from clinical-execution skills.
            return Self.companionAllowsTunnelAction(action)
        }
    }

    // MARK: - Helpers

    private static func companionAllowsTunnelAction(_ action: JarvisRemoteAction) -> Decision {
        switch action {
        case .status, .ping,
             .homeKitStatus, .listSkills,
             .startupVoice, .bridgeIntercom,
             .queueGuiIntent, .presenceArrival:
            return .allow
        case .selfHeal, .reseedObsidian, .shutdown:
            return .deny(reason: "destructive-or-admin:operator-only")
        case .runSkill:
            // Skills can have side effects; until per-skill risk metadata
            // exists, companion tier cannot invoke arbitrary skills.
            return .deny(reason: "skill-invocation:operator-only-for-now")
        case .speakRealtime:
            // Currently not supported for companion or responder tiers.
            return .deny(reason: "unsupported-action:speakRealtime")
        @unknown default:
            // Future-proofing: deny any unknown actions.
            return .deny(reason: "unsupported-action:unknown")
        }
    }

    public static func isOperatorOnlyCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return operatorOnlyFragments.contains(where: { lower.contains($0) })
    }

    public static func isGuestAllowedQuery(_ command: String) -> Bool {
        let lower = command.lowercased()
        return guestAllowedQueryFragments.contains(where: { lower.contains($0) })
    }

    public static func isClinicalExecutionCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return clinicalExecutionFragments.contains(where: { lower.contains($0) })
    }
}