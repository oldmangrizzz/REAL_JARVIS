import Foundation

/// Retry policy with exponential backoff and jitter.
public struct RetryPolicy {
    let maxAttempts: Int
    let initialDelayMs: UInt64
    let maxDelayMs: UInt64
    let backoffMultiplier: Double
    
    /// Initializes a retry policy.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3)
    ///   - initialDelayMs: Initial delay in milliseconds (default: 100)
    ///   - maxDelayMs: Maximum delay in milliseconds (default: 10000)
    ///   - backoffMultiplier: Exponential backoff multiplier (default: 2.0)
    public init(
        maxAttempts: Int = 3,
        initialDelayMs: UInt64 = 100,
        maxDelayMs: UInt64 = 10000,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelayMs = initialDelayMs
        self.maxDelayMs = maxDelayMs
        self.backoffMultiplier = backoffMultiplier
    }
    
    /// Executes an operation with retries and exponential backoff.
    /// - Parameter op: Async operation to execute
    /// - Returns: Result of operation if successful
    /// - Throws: Last error if all attempts fail
    public func execute<T>(_ op: () async throws -> T) async throws -> T {
        var lastError: Error?
        var delay: UInt64 = initialDelayMs
        
        for attempt in 0..<maxAttempts {
            do {
                return try await op()
            } catch {
                lastError = error
                
                // Don't delay after last attempt
                if attempt < maxAttempts - 1 {
                    // Add jitter: 0-25% random variance
                    let jitter = UInt64(Double(delay) * Double.random(in: 0...0.25))
                    let delayWithJitter = delay + jitter
                    
                    // Sleep with nanosecond precision
                    try await Task.sleep(nanoseconds: delayWithJitter * 1_000_000)
                    
                    // Exponential backoff with cap
                    delay = min(UInt64(Double(delay) * backoffMultiplier), maxDelayMs)
                }
            }
        }
        
        if let error = lastError {
            throw error
        }
        throw RetryPolicyError.allAttemptsFailed
    }
}

public enum RetryPolicyError: LocalizedError {
    case allAttemptsFailed
    
    public var errorDescription: String? {
        switch self {
        case .allAttemptsFailed:
            return "All retry attempts failed"
        }
    }
}
