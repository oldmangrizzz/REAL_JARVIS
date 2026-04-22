import Foundation

/// Circuit breaker pattern implementation for fault tolerance.
/// Prevents cascading failures by stopping requests to failing services.
public final class CircuitBreaker {
    /// Circuit state
    public enum State: Equatable {
        case closed      // Normal operation; requests allowed
        case open        // Service failing; all requests rejected
        case halfOpen    // Testing if service recovered
    }
    
    private let failureThreshold: Int
    private let cooldownDuration: TimeInterval
    
    private let queue = DispatchQueue(label: "com.jarvis.circuit-breaker")
    
    private var state: State = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    
    /// Initializes a circuit breaker with failure and cooldown thresholds.
    /// - Parameters:
    ///   - failureThreshold: Number of consecutive failures before opening (default: 5)
    ///   - cooldownDuration: Seconds to wait in open state before attempting half-open (default: 30)
    public init(
        failureThreshold: Int = 5,
        cooldownDuration: TimeInterval = 30
    ) {
        self.failureThreshold = failureThreshold
        self.cooldownDuration = cooldownDuration
    }
    
    /// Executes an operation with circuit breaker protection.
    /// - Parameter op: Async operation to execute
    /// - Returns: Result of operation if successful
    /// - Throws: CircuitBreakerError.open if breaker is open, or operation error
    public func run<T>(_ op: () async throws -> T) async throws -> T {
        let shouldExecute = await queue.sync {
            switch state {
            case .closed:
                return true
            case .open:
                // Check if cooldown has elapsed
                if let lastFailure = lastFailureTime,
                   Date().timeIntervalSince(lastFailure) >= cooldownDuration {
                    state = .halfOpen
                    return true
                }
                return false
            case .halfOpen:
                return true
            }
        }
        
        guard shouldExecute else {
            throw CircuitBreakerError.open
        }
        
        do {
            let result = try await op()
            await recordSuccess()
            return result
        } catch {
            await recordFailure()
            throw error
        }
    }
    
    private func recordSuccess() async {
        queue.sync {
            if state == .halfOpen {
                state = .closed
                failureCount = 0
            }
        }
    }
    
    private func recordFailure() async {
        queue.sync {
            failureCount += 1
            lastFailureTime = Date()
            
            switch state {
            case .closed:
                if failureCount >= failureThreshold {
                    state = .open
                }
            case .halfOpen:
                state = .open
            case .open:
                break
            }
        }
    }
    
    /// Returns the current state (for testing/monitoring)
    public var currentState: State {
        queue.sync { state }
    }
}

public enum CircuitBreakerError: LocalizedError {
    case open
    
    public var errorDescription: String? {
        switch self {
        case .open:
            return "Circuit breaker is open; service is unavailable"
        }
    }
}
