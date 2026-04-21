import Foundation

/// NAV-001 §11.1: Navigation utterance emitted by the routing engine.
///
/// Contract surface for downstream VOICE-002 wiring. This PR emits to a
/// local `AsyncChannel` only — no TTS call, no `AVSpeechSynthesizer`.
/// The conversation engine (VOICE-002) will consume this queue and route
/// through `AmbientAudioGateway.emit → F5-TTS → speaker`.
///
/// CANON: downstream wiring in NAV-003.
///
/// Priority ordering: `advisory` < `turnByTurn` < `hazard` < `emergency`.
/// Off-wrist cancels conversation within 150ms but does **NOT** cancel
/// nav — nav drains to phone/CarPlay if phone is in mesh. This asymmetry
/// is intentional; do not unify.
public enum NavUtterancePriority: String, Codable, Sendable, Comparable {
    /// Low-priority contextual info ("route recalculating").
    /// Cancelable, drops on barge-in.
    case advisory = "advisory"
    /// Standard turn-by-turn directions ("turn left in 500 feet").
    /// Cancelable but retried once with updated distance.
    case turnByTurn = "turnByTurn"
    /// Safety-relevant hazard alert ("debris ahead, slow down").
    /// Uncancelable safety override — preempts advisory and turnByTurn.
    case hazard = "hazard"
    /// Responder-tier only ("scene collapse, reroute now").
    /// Preempts all other priorities AND suppresses conversation for TTL.
    case emergency = "emergency"

    public static func < (lhs: NavUtterancePriority, rhs: NavUtterancePriority) -> Bool {
        // advisory(0) < turnByTurn(1) < hazard(2) < emergency(3)
        let order: [NavUtterancePriority] = [.advisory, .turnByTurn, .hazard, .emergency]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// NAV-001 §11.1: A navigation utterance queued for voice output.
///
/// Produced by `UniversalRouter` and related engines. Consumed by
/// `ConversationEngine` via `NavUtteranceQueue`. Tier-gated:
/// `.emergency` is responder-only; `.hazard` is available to all tiers.
///
/// CANON: downstream wiring in NAV-003.
public struct NavUtterance: Codable, Sendable, Equatable {
    public let id: UUID
    /// The text to be spoken, e.g. "Turn left in 500 feet."
    public let text: String
    /// Priority for barge-in preemption. See §11.2.
    public let priority: NavUtterancePriority
    /// Timestamp when this utterance was created.
    public let issuedAt: Date
    /// Route step this utterance refers to, or nil for hazard alerts.
    public let routeStepID: String?
    /// Drop if not spoken within this many seconds.
    public let ttlSeconds: Double

    public init(
        id: UUID = UUID(),
        text: String,
        priority: NavUtterancePriority,
        issuedAt: Date = Date(),
        routeStepID: String? = nil,
        ttlSeconds: Double = 30.0
    ) {
        self.id = id
        self.text = text
        self.priority = priority
        self.issuedAt = issuedAt
        self.routeStepID = routeStepID
        self.ttlSeconds = ttlSeconds
    }
}

/// Async queue for nav utterances. Thread-safe (actor).
///
/// Routes: `RoutingEngine → NavUtteranceQueue → ConversationEngine → F5-TTS → AmbientAudioGateway.emit`
///
/// This PR: local queue only. No TTS call. Full voice wiring is VOICE-002's job.
/// CANON: downstream wiring in NAV-003.
public actor NavUtteranceQueue {
    private var queue: [NavUtterance] = []

    public init() {}

    /// Enqueue a navigation utterance. Barge-in preemption per §11.2:
    /// - `hazard` cancels all `advisory` and `turnByTurn` in queue.
    /// - `emergency` cancels everything else and suppresses conversation for TTL.
    public func enqueue(_ utterance: NavUtterance) {
        switch utterance.priority {
        case .hazard:
            // Uncancelable safety override: drop advisory + turnByTurn.
            queue.removeAll { $0.priority < .hazard }
        case .emergency:
            // Preempts everything. Caller is responsible for tier check.
            queue.removeAll { $0.priority < .emergency }
        default:
            break
        }
        queue.append(utterance)
    }

    /// Dequeue the highest-priority utterance, or nil if empty.
    /// Utterances past their TTL are silently dropped.
    public func dequeue() -> NavUtterance? {
        let now = Date()
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            if candidate.issuedAt.addingTimeInterval(candidate.ttlSeconds) > now {
                return candidate
            }
            // TTL expired — drop silently, continue
        }
        return nil
    }

    /// Peek without removing.
    public func peek() -> NavUtterance? {
        let now = Date()
        return queue.first { $0.issuedAt.addingTimeInterval($0.ttlSeconds) > now }
    }

    /// Current queue depth (for telemetry / testing).
    public var count: Int { queue.count }
}