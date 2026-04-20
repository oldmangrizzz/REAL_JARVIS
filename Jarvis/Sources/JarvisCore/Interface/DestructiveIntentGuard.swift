import Foundation

/// SPEC-008: Guardrail for destructive voice intents at the router boundary.
///
/// The general `CommandRateLimiter` already throttles display/HomeKit
/// dispatch, but system-level destructive verbs (`shutdown`, `go quiet`,
/// `stop listening`) bypass it because they flow through
/// `SystemCommandHandler`. Those verbs revoke the runtime's ability to
/// take any further action and therefore deserve a stricter, separate
/// token bucket. An operator (or an injected adversary transcript)
/// hammering "shutdown" repeatedly should be refused with a spoken
/// reason and a `command_refused` telemetry event.
///
/// Classification is kept deliberately narrow: only intents whose
/// successful dispatch would silence or power-down the assistant count
/// as destructive. Expansion points (e.g. "self destruct", "wipe
/// memory") are additive — add them to `Self.destructiveFragments` and
/// the guard picks them up without a caller change.
public final class DestructiveIntentGuard: @unchecked Sendable {
    public enum Classification: Equatable {
        case destructive(reason: String)
        case nonDestructive
        public var isDestructive: Bool {
            if case .destructive = self { return true }
            return false
        }
    }

    public let capacity: Int
    public let window: TimeInterval

    private let lock = NSLock()
    private var timestamps: [Date] = []

    /// Fragments that, when present in the parsed systemQuery payload
    /// or raw transcript, mark the intent as destructive.
    public static let destructiveFragments: [String] = [
        "shutdown", "shut down", "go quiet", "stop listening",
        "self destruct", "self-destruct", "kill switch",
        "disable safety", "wipe memory", "factory reset"
    ]

    public init(capacity: Int = 2, window: TimeInterval = 300) {
        self.capacity = max(1, capacity)
        self.window = max(0.1, window)
    }

    /// Classify a parsed intent against its original transcript.
    /// `.skillInvocation` and `.displayAction` / `.homeKitControl`
    /// never classify as destructive here — display surfaces are
    /// revocable via the UI and skills run through a separate
    /// authorization gate.
    public func classify(intent: ParsedIntent, command: String) -> Classification {
        let haystack: String
        switch intent.intent {
        case .systemQuery(let q):
            haystack = q.lowercased()
        case .unknown:
            haystack = command.lowercased()
        case .displayAction, .homeKitControl, .skillInvocation:
            return .nonDestructive
        }
        for fragment in Self.destructiveFragments {
            if haystack.contains(fragment) {
                return .destructive(reason: fragment)
            }
        }
        return .nonDestructive
    }

    /// Consume a token. Returns `true` if the caller may dispatch.
    public func allow(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-window)
        timestamps.removeAll(where: { $0 < cutoff })
        guard timestamps.count < capacity else { return false }
        timestamps.append(now)
        return true
    }

    /// Standard spoken refusal for a rate-limited destructive intent.
    public static let refusalResponse = "That's a destructive command and I've already honored one recently. I'm going to wait before doing another."
}
