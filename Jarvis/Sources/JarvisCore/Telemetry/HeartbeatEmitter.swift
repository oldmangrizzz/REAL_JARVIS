import Foundation

/// MK2-EPIC-07 §4. Jarvis host emits a `heartbeat` telemetry row on a
/// fixed cadence (default 30 s) summarizing the state the operator
/// dashboard uses to drive the GREEN/YELLOW/RED pill:
///
///   * voiceGateOK   — whether the approved fingerprint is currently
///                     resident and verified.
///   * tunnelClients — count of live JarvisHostTunnelServer peers.
///   * memoryVersion — monotonic version tag of the memory graph root.
///   * lastIntentAt  — ISO-8601 timestamp of the most recent operator
///                     intent the engine processed (nil if none yet).
///
/// The dashboard colour rules are:
///   - GREEN  : newest heartbeat younger than 60 s.
///   - YELLOW : 60 s ≤ age ≤ 300 s.
///   - RED    : older than 300 s (or no heartbeat).
///
/// Per PRINCIPLES §2 we do NOT include raw audio, raw canon content, or
/// private key material in the heartbeat body. Only coarse booleans /
/// counts / opaque version tags.
public protocol HeartbeatStateProvider: AnyObject, Sendable {
    func currentHeartbeat() -> HeartbeatSnapshot
}

public struct HeartbeatSnapshot: Equatable, Sendable {
    public let voiceGateOK: Bool
    public let tunnelClients: Int
    public let memoryVersion: String
    public let lastIntentAt: Date?

    public init(voiceGateOK: Bool,
                tunnelClients: Int,
                memoryVersion: String,
                lastIntentAt: Date?) {
        self.voiceGateOK = voiceGateOK
        self.tunnelClients = tunnelClients
        self.memoryVersion = memoryVersion
        self.lastIntentAt = lastIntentAt
    }
}

public final class HeartbeatEmitter: @unchecked Sendable {
    private let telemetry: TelemetryStore
    private let provider: HeartbeatStateProvider
    private let interval: TimeInterval
    private let iso8601: ISO8601DateFormatter
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var isRunning: Bool = false
    private let lock = NSLock()

    public init(telemetry: TelemetryStore,
                provider: HeartbeatStateProvider,
                interval: TimeInterval = 30.0,
                queue: DispatchQueue = DispatchQueue(label: "jarvis.heartbeat", qos: .utility)) {
        precondition(interval > 0, "heartbeat interval must be positive")
        self.telemetry = telemetry
        self.provider = provider
        self.interval = interval
        self.queue = queue
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = iso
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    /// Public for test harnesses that want to advance a heartbeat without
    /// running the timer. Production code uses `start()` / `stop()`.
    public func tick() {
        let snap = provider.currentHeartbeat()
        var record: [String: Any] = [
            "event": "heartbeat",
            "voiceGateOK": snap.voiceGateOK,
            "tunnelClients": snap.tunnelClients,
            "memoryVersion": snap.memoryVersion
        ]
        if let last = snap.lastIntentAt {
            record["lastIntentAt"] = iso8601.string(from: last)
        }
        do {
            try telemetry.append(record: record, to: "heartbeat")
        } catch {
            // Heartbeat is best-effort. A telemetry failure must never
            // bring down the host. We deliberately swallow and let the
            // next tick retry.
        }
    }
}
