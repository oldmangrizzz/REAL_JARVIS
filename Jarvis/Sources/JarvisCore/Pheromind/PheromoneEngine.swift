import Foundation

public enum TernarySignal: Int, Codable, Sendable {
    case repel = -1
    case neutral = 0
    case reinforce = 1

    public static func regulate(score: Double, positiveThreshold: Double = 0.2, negativeThreshold: Double = -0.2) -> TernarySignal {
        if score >= positiveThreshold { return .reinforce }
        if score <= negativeThreshold { return .repel }
        return .neutral
    }
}

public struct EdgeKey: Hashable, Codable, Sendable {
    public let source: String
    public let target: String

    public var dictionary: [String: Any] {
        ["source": source, "target": target]
    }
}

public struct PheromoneDeposit: Codable, Sendable {
    public let edge: EdgeKey
    public let signal: TernarySignal
    public let magnitude: Double
    public let agentID: String
    public let timestamp: Date
}

public struct PheromoneEdgeState: Codable, Sendable {
    public var pheromone: Double
    public var somaticWeight: Double
    public var lastUpdated: Date
    public var successCount: Int
    public var failureCount: Int
}

public final class PheromindEngine {  // CX-002: added NSLock for thread safety (actor conversion deferred — too many callers)
    private var states: [EdgeKey: PheromoneEdgeState] = [:]
    private let telemetry: TelemetryStore
    public var baseEvaporation: Double
    public let learningRate: Double
    private let lock = NSLock()  // CX-002: serializes all mutable state access

    public init(baseEvaporation: Double = 0.12, learningRate: Double = 0.35, telemetry: TelemetryStore) {
        self.baseEvaporation = baseEvaporation
        self.learningRate = learningRate
        self.telemetry = telemetry
    }

    public func register(edge: EdgeKey, pheromone: Double = 0.0, somaticWeight: Double = 0.0) {
        lock.lock(); defer { lock.unlock() }  // CX-002
        if states[edge] == nil {
            states[edge] = PheromoneEdgeState(
                pheromone: pheromone,
                somaticWeight: somaticWeight,
                lastUpdated: Date(),
                successCount: 0,
                failureCount: 0
            )
        }
    }

    public func state(for edge: EdgeKey) -> PheromoneEdgeState? {
        lock.lock(); defer { lock.unlock() }  // CX-002
        return states[edge]
    }

    public func effectiveEvaporation(for state: PheromoneEdgeState, now: Date = Date()) -> Double {
        let ageSeconds = max(0.0, now.timeIntervalSince(state.lastUpdated))
        // CX-045: raised staleness slope so cap engages at ~30min instead of ~3hr
        let staleness = min(0.25, ageSeconds / 1_800.0 * 0.15)
        let attempts = max(1, state.successCount + state.failureCount)
        let failureBias = Double(state.failureCount) / Double(attempts) * 0.2
        return min(0.95, max(0.05, baseEvaporation + staleness + failureBias))
    }

    public func chooseNextEdge(from source: String) -> EdgeKey? {
        lock.lock(); defer { lock.unlock() }  // CX-002
        return states
            .filter { $0.key.source == source }
            .max {
                ($0.value.pheromone + $0.value.somaticWeight) < ($1.value.pheromone + $1.value.somaticWeight)
            }?
            .key
    }

    @discardableResult
    public func applyGlobalUpdate(deposits: [PheromoneDeposit], now: Date = Date()) throws -> [EdgeKey: PheromoneEdgeState] {
        lock.lock(); defer { lock.unlock() }  // CX-002
        let grouped = Dictionary(grouping: deposits, by: \.edge)

        for (edge, edgeDeposits) in grouped {
            var state = states[edge] ?? PheromoneEdgeState(
                pheromone: 0.0,
                somaticWeight: 0.0,
                lastUpdated: now,
                successCount: 0,
                failureCount: 0
            )

            let evaporation = effectiveEvaporation(for: state, now: now)
            let deltaTau = edgeDeposits.reduce(0.0) { partial, deposit in
                partial + Double(deposit.signal.rawValue) * deposit.magnitude
            }

            // ϕ(i,j,t+1) = (1 − ε)ϕ(i,j,t) + ΣΔτk(i,j)
            state.pheromone = min(((1.0 - evaporation) * state.pheromone) + deltaTau, 1000.0)  // CX-033: infinity clamp
            state.somaticWeight = min(max(0.0, state.somaticWeight + (deltaTau * learningRate)), 100.0)  // CX-034: somatic clamp
            state.lastUpdated = now

            for deposit in edgeDeposits {
                switch deposit.signal {
                case .reinforce:
                    state.successCount += 1
                case .repel:
                    state.failureCount += 1
                case .neutral:
                    break
                }
                try telemetry.logStigmergicSignal(edge: edge, signal: deposit.signal, agentID: deposit.agentID, pheromone: state.pheromone)
            }

            states[edge] = state
        }

        for (edge, state) in states where grouped[edge] == nil {
            var updated = state
            let evaporation = effectiveEvaporation(for: state, now: now)
            updated.pheromone = (1.0 - evaporation) * state.pheromone
            updated.lastUpdated = now
            states[edge] = updated
        }

        return states
    }
}
