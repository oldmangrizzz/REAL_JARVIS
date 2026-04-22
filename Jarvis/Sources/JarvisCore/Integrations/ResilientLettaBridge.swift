import Foundation

/// Wraps `LettaBridge` with circuit breaker + retry policy for fault tolerance.
public final class ResilientLettaBridge: Sendable {
    private let inner: LettaBridge
    private let breaker: CircuitBreaker
    private let retryPolicy: RetryPolicy

    public init(
        inner: LettaBridge,
        breaker: CircuitBreaker = CircuitBreaker(),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.inner = inner
        self.breaker = breaker
        self.retryPolicy = retryPolicy
    }

    public func health(timeout: TimeInterval = 10) async throws -> [String: Any] {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.health(timeout: timeout)
            }
        }
    }

    public func listAgents(timeout: TimeInterval = 15) async throws -> [[String: Any]] {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.listAgents(timeout: timeout)
            }
        }
    }

    @discardableResult
    public func createAgent(payload: [String: Any], timeout: TimeInterval = 30) async throws -> [String: Any] {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.createAgent(payload: payload, timeout: timeout)
            }
        }
    }

    public func sendMessage(
        agentID: String,
        message: String,
        role: String = "user",
        timeout: TimeInterval = 60
    ) async throws -> [String: Any] {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.sendMessage(agentID: agentID, message: message, role: role, timeout: timeout)
            }
        }
    }

    @discardableResult
    public func appendCoreMemory(
        agentID: String,
        blockLabel: String,
        text: String,
        timeout: TimeInterval = 30
    ) async throws -> [String: Any] {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.appendCoreMemory(agentID: agentID, blockLabel: blockLabel, text: text, timeout: timeout)
            }
        }
    }
}
