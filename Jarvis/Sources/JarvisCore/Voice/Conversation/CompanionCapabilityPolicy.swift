import Foundation

/// Represents the policy for companion capabilities in voice conversation.
public enum CompanionCapabilityPolicy {
    /// No capabilities.
    case none
    /// Capability to speak in a deferred manner.
    case speakDeferred
    /// Capability to listen in real‑time.
    case listenRealtime
    /// Capability to listen in a deferred manner.
    case listenDeferred

    /// Indicates whether the policy permits speaking.
    public var canSpeak: Bool {
        switch self {
        case .speakDeferred:
            return true
        default:
            return false
        }
    }

    /// Indicates whether the policy permits listening.
    public var canListen: Bool {
        switch self {
        case .listenRealtime, .listenDeferred:
            return true
        default:
            return false
        }
    }

    /// Returns a description suitable for debugging.
    public var description: String {
        switch self {
        case .none:
            return "none"
        case .speakDeferred:
            return "speakDeferred"
        case .listenRealtime:
            return "listenRealtime"
        case .listenDeferred:
            return "listenDeferred"
        }
    }
}