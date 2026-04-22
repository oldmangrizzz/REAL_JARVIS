import Foundation

/// Wraps `MeshDisplayDispatching` with circuit breaker + retry policy for fault tolerance.
public final class ResilientMeshDisplayDispatcher: MeshDisplayDispatching, @unchecked Sendable {
    private let inner: MeshDisplayDispatching
    private let breaker: CircuitBreaker
    private let retryPolicy: RetryPolicy

    public init(
        inner: MeshDisplayDispatching,
        breaker: CircuitBreaker = CircuitBreaker(),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.inner = inner
        self.breaker = breaker
        self.retryPolicy = retryPolicy
    }

    public func dispatch(
        display: DisplayEndpoint,
        action: String,
        parameters: [String: String]
    ) async throws -> ExecutionResult {
        try await breaker.run {
            try await retryPolicy.execute {
                try await inner.dispatch(display: display, action: action, parameters: parameters)
            }
        }
    }
}
