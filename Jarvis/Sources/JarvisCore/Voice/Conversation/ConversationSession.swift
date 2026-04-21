import Foundation

/// State machine for a single conversation session.
/// Matches SPEC-VOICE-002 §3.2.
public enum ConversationState: String, Sendable, Equatable {
    case idle
    case listening
    case partialUnderstanding
    case generating
    case speaking
    case bargeInterrupt
    case degraded
    case closed
}

/// A single bidirectional conversation session, tracking state and SLA metrics.
public final class ConversationSession: @unchecked Sendable {
    public let id: UUID
    public let principal: Principal
    public private(set) var state: ConversationState = .idle

    // SLA tracking
    private var llmFirstTokenAt: Date?
    private var ttsFirstChunkAt: Date?
    private var slaMissCount: Int = 0
    private var turnStartedAt: Date?

    // Per-turn / per-session tracking (VOICE-002 telemetry)
    public private(set) var activeTurnID: UUID?
    public private(set) var bargeInCount: Int = 0
    public private(set) var currentRoute: AmbientGatewayRoute = .watchHosted

    public var shouldDegrade: Bool { slaMissCount >= 3 }

    public init(principal: Principal) {
        self.id = UUID()
        self.principal = principal
    }

    public func beginTurn(_ turnID: UUID) {
        activeTurnID = turnID
    }

    public func endTurn() {
        activeTurnID = nil
    }

    public func incrementBargeIn() {
        bargeInCount += 1
    }

    public func resetBargeInCount() {
        bargeInCount = 0
    }

    public func updateRoute(_ route: AmbientGatewayRoute) {
        currentRoute = route
    }

    public func transition(to newState: ConversationState, reason: String? = nil) throws {
        // Basic FSM validation — closed is terminal
        guard state != .closed else {
            throw JarvisError.invalidInput("Cannot transition from closed state.")
        }
        let allowed: [ConversationState: Set<ConversationState>] = [
            .idle: [.listening, .closed, .degraded],
            .listening: [.partialUnderstanding, .generating, .idle, .closed, .degraded],
            .partialUnderstanding: [.generating, .listening, .idle, .closed, .degraded],
            .generating: [.speaking, .listening, .bargeInterrupt, .closed, .degraded],
            .speaking: [.listening, .bargeInterrupt, .idle, .closed, .degraded],
            .bargeInterrupt: [.listening, .idle, .closed, .degraded],
            .degraded: [.idle, .listening, .closed]
        ]
        if state != newState, !(allowed[state]?.contains(newState) ?? false) {
            throw JarvisError.invalidInput("Illegal transition \(state.rawValue) -> \(newState.rawValue)")
        }
        state = newState
        if newState == .generating {
            turnStartedAt = Date()
        }
    }

    public func recordLLMFirstToken() {
        llmFirstTokenAt = Date()
    }

    public func recordTTSFirstChunk() {
        ttsFirstChunkAt = Date()
    }

    public func recordSlaMiss() {
        slaMissCount += 1
    }

    public func getTurnMetrics(endedAt: Date) -> [String: Double] {
        var metrics: [String: Double] = [:]
        if let start = turnStartedAt {
            metrics["endToEnd"] = endedAt.timeIntervalSince(start) * 1000
        }
        return metrics
    }
}

/// Record of a state transition for SPEC-009 telemetry.
public struct ConversationStateTransitionRecord: Codable, Sendable {
    public let sessionId: UUID
    public let turnId: UUID?
    public let fromState: String
    public let toState: String
    public let reason: String?
    public let timestamp: String
}

/// Record of a completed conversation turn for SPEC-009 telemetry.
public struct ConversationTurnRecord: Codable, Sendable {
    public struct Latency: Codable, Sendable {
        public let asrFirstPartial: Double?
        public let asrFinal: Double?
        public let llmFirstToken: Double?
        public let ttsFirstChunk: Double?
        public let endToEnd: Double
    }

    public let turnId: UUID
    public let sessionId: UUID
    public let startedAt: String
    public let endedAt: String
    public let outcome: String
    public let latencyMs: Latency
    public let bargeInCount: Int
    public let principal: String
    public let route: String
    public let multiplier: Double
}