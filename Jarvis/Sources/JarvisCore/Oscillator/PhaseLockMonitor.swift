import Foundation

// MARK: - Phase-Locked Variability (PLV) Monitor
//
// Observes how closely each subscriber's "work completed" timestamp
// tracks the master oscillator's tick schedule. Computes a healthy-HRV-
// like variability metric per subscriber over a rolling window.
//
// Clinical mapping (biomimetic only, not medical device):
//   - PLV score in [0, 1]. 1.0 = perfectly phase-locked. 0 = decoupled.
//   - Too-perfect phase lock (variance ≈ 0) also degrades: autonomic
//     flatlining. We want some jitter. The healthy band is 0.7–0.97.
//   - Healthy band → ternary .reinforce
//     Marginal band → ternary .neutral
//     Out of band   → ternary .repel (degrade signal to ControlPlane)
//
// See: PRINCIPLES §2, Pheromind TernarySignal, PAPER_3 §4.1

public struct PhaseSample: Sendable {
    public let sequence: UInt64
    public let driftMilliseconds: Double       // completion - tick.emitted, in ms
    public let intervalMilliseconds: Double    // current tick interval (for normalization)
}

public struct PhaseLockScore: Codable, Sendable, Equatable {
    public let subscriberID: String
    public let sampleCount: Int
    public let meanDriftMilliseconds: Double
    public let stddevDriftMilliseconds: Double
    public let plv: Double              // 0...1 — phase-locking value
    public let regulated: TernarySignal
    public let lastSequence: UInt64
    public let timestamp: Date
}

public final class PhaseLockMonitor {
    public struct Configuration: Sendable {
        public var windowSize: Int
        public var healthyBandLower: Double   // plv lower bound for reinforce
        public var healthyBandUpper: Double   // plv upper bound for reinforce
        public var marginalBand: Double       // plv still OK but not ideal
        public var scoreEvery: UInt64         // telemetry cadence per subscriber

        public init(windowSize: Int = 32,
                    healthyBandLower: Double = 0.70,
                    healthyBandUpper: Double = 0.97,
                    marginalBand: Double = 0.45,
                    scoreEvery: UInt64 = 8) {
            self.windowSize = windowSize
            self.healthyBandLower = healthyBandLower
            self.healthyBandUpper = healthyBandUpper
            self.marginalBand = marginalBand
            self.scoreEvery = scoreEvery
        }
    }

    private let telemetry: TelemetryStore
    private let config: Configuration
    private let lock = NSLock()
    private var windows: [String: [PhaseSample]] = [:]
    private var ticksObserved: [String: UInt64] = [:]
    private var latestScores: [String: PhaseLockScore] = [:]

    public init(telemetry: TelemetryStore, configuration: Configuration = .init()) {
        self.telemetry = telemetry
        self.config = configuration
    }

    public func recordCompletion(subscriberID: String, tick: OscillatorTick, completedAt: Date = Date()) {
        let drift = (completedAt.timeIntervalSince1970 - tick.emitted.timeIntervalSince1970) * 1000.0
        let sample = PhaseSample(
            sequence: tick.sequence,
            driftMilliseconds: drift,
            intervalMilliseconds: tick.intervalMilliseconds
        )
        lock.lock()
        var win = windows[subscriberID, default: []]
        win.append(sample)
        if win.count > config.windowSize { win.removeFirst(win.count - config.windowSize) }
        windows[subscriberID] = win
        ticksObserved[subscriberID, default: 0] &+= 1
        let observed = ticksObserved[subscriberID]!
        let shouldScore = observed % config.scoreEvery == 0 && win.count >= max(4, config.windowSize / 4)
        let windowCopy = shouldScore ? win : []
        lock.unlock()

        guard shouldScore else { return }
        let score = computeScore(subscriberID: subscriberID, window: windowCopy)
        lock.lock(); latestScores[subscriberID] = score; lock.unlock()
        try? telemetry.append(record: [
            "event": "plv_score",
            "subscriber": score.subscriberID,
            "samples": score.sampleCount,
            "mean_drift_ms": score.meanDriftMilliseconds,
            "stddev_drift_ms": score.stddevDriftMilliseconds,
            "plv": score.plv,
            "regulated": score.regulated.rawValue,
            "sequence": score.lastSequence
        ], to: "oscillator_plv")
    }

    public func currentScore(for subscriberID: String) -> PhaseLockScore? {
        lock.lock(); defer { lock.unlock() }
        return latestScores[subscriberID]
    }

    public func allScores() -> [PhaseLockScore] {
        lock.lock(); defer { lock.unlock() }
        return Array(latestScores.values).sorted { $0.subscriberID < $1.subscriberID }
    }

    public func reset(subscriberID: String) {
        lock.lock(); defer { lock.unlock() }
        windows.removeValue(forKey: subscriberID)
        ticksObserved.removeValue(forKey: subscriberID)
        latestScores.removeValue(forKey: subscriberID)
    }

    private func computeScore(subscriberID: String, window: [PhaseSample]) -> PhaseLockScore {
        let n = Double(window.count)
        let drifts = window.map(\.driftMilliseconds)

        // Guard against NaN/Inf propagation from Date arithmetic edge cases.
        let safeDrifts = drifts.filter { $0.isFinite && !$0.isNaN }
        guard !safeDrifts.isEmpty else {
            return PhaseLockScore(
                subscriberID: subscriberID,
                sampleCount: window.count,
                meanDriftMilliseconds: 0.0,
                stddevDriftMilliseconds: 0.0,
                plv: 0.0,
                regulated: .repel,
                lastSequence: window.last?.sequence ?? 0,
                timestamp: Date()
            )
        }
        let safeN = Double(safeDrifts.count)
        let mean = safeDrifts.reduce(0, +) / safeN
        let variance = safeDrifts.map { pow($0 - mean, 2) }.reduce(0, +) / safeN
        let stddev = sqrt(variance)

        // Normalize stddev against the tick interval — one full interval of
        // drift stddev is a catastrophic decoupling. Cap at 1.0.
        let intervalMs = window.last?.intervalMilliseconds ?? 1000.0
        let normalized = min(stddev / max(intervalMs, 1.0), 1.0)
        // PLV: 1 when normalized stddev = 0, 0 when normalized stddev = 1.
        // Then penalize drift magnitude (non-zero mean drift = lag/lead).
        let meanPenalty = min(abs(mean) / max(intervalMs, 1.0), 1.0)
        let rawPLV = (1.0 - normalized) * (1.0 - meanPenalty)
        // Too-perfect lock is a degenerate case (flatlined). Slight penalty.
        let flatlinePenalty = rawPLV > 0.995 ? 0.05 : 0.0
        let plv = max(0.0, min(1.0, rawPLV - flatlinePenalty))

        let regulated: TernarySignal
        if plv >= config.healthyBandLower && plv <= config.healthyBandUpper {
            regulated = .reinforce
        } else if plv >= config.marginalBand {
            regulated = .neutral
        } else {
            regulated = .repel
        }

        return PhaseLockScore(
            subscriberID: subscriberID,
            sampleCount: window.count,
            meanDriftMilliseconds: mean,
            stddevDriftMilliseconds: stddev,
            plv: plv,
            regulated: regulated,
            lastSequence: window.last?.sequence ?? 0,
            timestamp: Date()
        )
    }
}
