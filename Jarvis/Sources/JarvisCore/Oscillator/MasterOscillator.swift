import Foundation

// MARK: - Master Oscillator (SA Node)
//
// System-wide "heartbeat" tick. All distributed subsystems phase-lock to
// this. Prevents temporal drift in subsystem choreography — the same role
// the SA node plays for the human heart.
//
// Ported concept-only across the NLB from PAPER_3 §1.1. No code, data, or
// config crosses the boundary — only the architectural pattern.
//
// Biomimetic mapping:
//   - Baseline rate   ≈ 60 bpm (1 Hz). Human resting HR.
//   - Tick            ≈ SA node depolarization.
//   - Phase-Locked Variability (PLV) ≈ healthy HRV. Flatlined PLV is
//                       pathological (autonomic death); pathologically
//                       dithered PLV is fibrillation.
//
// See: /PRINCIPLES.md §2, /VERIFICATION_PROTOCOL.md §1

public struct OscillatorTick: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let scheduled: Date
    public let emitted: Date
    public let driftMilliseconds: Double
    public let intervalMilliseconds: Double
}

public protocol PhaseLockedSubscriber: AnyObject {
    var subscriberID: String { get }
    func onTick(_ tick: OscillatorTick)
}

private struct WeakSubscriber {
    weak var value: PhaseLockedSubscriber?
}

public final class MasterOscillator {
    public struct Configuration: Sendable {
        public var bpm: Double
        public var minBPM: Double
        public var maxBPM: Double
        public var telemetryEvery: UInt64

        public init(bpm: Double = 60.0, minBPM: Double = 30.0, maxBPM: Double = 180.0, telemetryEvery: UInt64 = 30) {
            self.bpm = bpm
            self.minBPM = minBPM
            self.maxBPM = maxBPM
            self.telemetryEvery = telemetryEvery
        }

        public var intervalSeconds: TimeInterval { 60.0 / bpm }
    }

    private let telemetry: TelemetryStore
    private let queue = DispatchQueue(label: "jarvis.oscillator", qos: .userInitiated)
    private let lock = NSLock()
    private var config: Configuration
    private var subscribers: [String: WeakSubscriber] = [:]
    private var timer: DispatchSourceTimer?
    private var sequence: UInt64 = 0
    private var lastEmitted: Date?
    private var running = false
    private var epoch: UInt64 = 0  // CX-005: guards against stale timer callbacks

    public init(telemetry: TelemetryStore, configuration: Configuration = .init()) {
        self.telemetry = telemetry
        self.config = configuration
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    public var currentBPM: Double {
        lock.lock(); defer { lock.unlock() }
        return config.bpm
    }

    public func subscribe(_ subscriber: PhaseLockedSubscriber) {
        lock.lock(); defer { lock.unlock() }
        subscribers[subscriber.subscriberID] = WeakSubscriber(value: subscriber)
    }

    public func unsubscribe(_ subscriberID: String) {
        lock.lock(); defer { lock.unlock() }
        subscribers.removeValue(forKey: subscriberID)
    }

    public func setBPM(_ bpm: Double) {
        lock.lock()
        let clamped = min(max(bpm, config.minBPM), config.maxBPM)
        let changed = clamped != config.bpm
        config.bpm = clamped
        let wasRunning = running
        lock.unlock()
        if changed && wasRunning { restart() }
        try? telemetry.append(record: [
            "event": "bpm_set",
            "bpm": clamped
        ], to: "oscillator")
    }

    public func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        sequence = 0
        lastEmitted = nil
        let interval = config.intervalSeconds
        epoch &+= 1  // CX-005: new epoch invalidates any stale timer callbacks
        let currentEpoch = epoch  // CX-005: capture for event handler
        lock.unlock()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(Int(interval * 1000.0)),
                   repeating: .milliseconds(Int(interval * 1000.0)),
                   leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            self?.fire(epoch: currentEpoch)  // CX-005: only fire if epoch matches
        }
        lock.lock()  // CX-005: assign timer under lock to prevent race with stop()
        timer = t
        lock.unlock()
        t.resume()

        try? telemetry.append(record: [
            "event": "started",
            "bpm": config.bpm,
            "interval_ms": interval * 1000.0
        ], to: "oscillator")
    }

    public func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        let t = timer
        timer = nil
        lock.unlock()
        t?.cancel()
        try? telemetry.append(record: ["event": "stopped"], to: "oscillator")
    }

    public func restart() { stop(); start() }

    // Emit a tick synchronously; useful for deterministic tests.
    @discardableResult
    public func manualTick(at date: Date = Date()) -> OscillatorTick {
        lock.lock()
        let currentEpoch = epoch  // CX-005: capture current epoch
        lock.unlock()
        return fire(epoch: currentEpoch, manualDate: date, asyncOnTick: false)
    }

    @discardableResult
    private func fire(epoch handlerEpoch: UInt64, manualDate: Date? = nil, asyncOnTick: Bool = true) -> OscillatorTick {
        // CX-005: discard stale timer callbacks from previous epochs
        lock.lock()
        guard handlerEpoch == epoch else { lock.unlock(); return OscillatorTick(sequence: 0, scheduled: Date(), emitted: Date(), driftMilliseconds: 0, intervalMilliseconds: 0) }
        let emitted = manualDate ?? Date()
        sequence &+= 1
        let seq = sequence
        let interval = config.intervalSeconds
        let scheduled = lastEmitted.map { $0.addingTimeInterval(interval) } ?? emitted
        lastEmitted = emitted
        let live = subscribers.compactMapValues { $0.value }
        subscribers = subscribers.filter { $0.value.value != nil }
        let telemetryEvery = config.telemetryEvery
        lock.unlock()

        let drift = (emitted.timeIntervalSince1970 - scheduled.timeIntervalSince1970) * 1000.0
        let tick = OscillatorTick(
            sequence: seq,
            scheduled: scheduled,
            emitted: emitted,
            driftMilliseconds: drift,
            intervalMilliseconds: interval * 1000.0
        )

        // CX-001: dispatch onTick to serial queue for timer ticks to prevent
        // concurrent delivery; manualTick delivers synchronously for test determinism
        if asyncOnTick {
            for sub in live.values { queue.async { sub.onTick(tick) } }
        } else {
            for sub in live.values { sub.onTick(tick) }
        }

        if seq % telemetryEvery == 0 {
            try? telemetry.append(record: [
                "event": "tick",
                "sequence": seq,
                "drift_ms": drift,
                "interval_ms": interval * 1000.0,
                "subscriber_count": live.count
            ], to: "oscillator")
        }
        return tick
    }

    deinit { stop() }
}
