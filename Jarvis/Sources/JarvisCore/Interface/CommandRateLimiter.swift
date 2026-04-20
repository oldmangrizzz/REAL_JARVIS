import Foundation

/// SPEC-008.2: token-bucket rate limiter for display/HomeKit voice commands.
/// Caps dispatch at `capacity` tokens per `window` seconds. Exceeding the cap
/// yields a spoken refusal via `limitExceededResponse()` and should be logged
/// as a `command_refused` telemetry event by the caller.
public final class CommandRateLimiter: @unchecked Sendable {
    public let capacity: Int
    public let window: TimeInterval

    private let lock = NSLock()
    private var timestamps: [Date] = []

    public init(capacity: Int = 5, window: TimeInterval = 60) {
        self.capacity = max(1, capacity)
        self.window = max(0.1, window)
    }

    /// Returns true if a new command may be dispatched now. Consumes a token on success.
    public func allow(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-window)
        timestamps.removeAll(where: { $0 < cutoff })
        guard timestamps.count < capacity else { return false }
        timestamps.append(now)
        return true
    }

    /// Standard spoken refusal when the limit is exceeded.
    public static let limitExceededResponse = "I'm receiving too many commands too quickly. Give me a moment."
}
