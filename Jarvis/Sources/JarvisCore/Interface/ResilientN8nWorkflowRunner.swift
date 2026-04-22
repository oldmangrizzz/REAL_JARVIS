import Foundation

/// Wraps `N8nWorkflowRunning` with circuit breaker + retry policy for fault tolerance.
public final class ResilientN8nWorkflowRunner: N8nWorkflowRunning, @unchecked Sendable {
    private let inner: N8nWorkflowRunning
    private let breaker: CircuitBreaker
    private let retryPolicy: RetryPolicy

    public init(
        inner: N8nWorkflowRunning,
        breaker: CircuitBreaker = CircuitBreaker(),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.inner = inner
        self.breaker = breaker
        self.retryPolicy = retryPolicy
    }

    public func run(workflowPath: String, payload: [String: Any]) async throws -> ExecutionResult {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.run(workflowPath: workflowPath, payload: payload)
            }
        }
    }
}
