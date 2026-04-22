import XCTest
@testable import JarvisCore

final class CircuitBreakerTests: XCTestCase {
    func testCircuitBreakerInitiallyClosedAllowsRequests() async throws {
        let breaker = CircuitBreaker()
        var executed = false
        
        try await breaker.run {
            executed = true
        }
        
        XCTAssertTrue(executed)
        XCTAssertEqual(breaker.currentState, .closed)
    }
    
    func testCircuitBreakerOpensAfterThresholdFailures() async throws {
        let breaker = CircuitBreaker(failureThreshold: 2)
        
        // First failure
        do {
            try await breaker.run {
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            // Expected
        }
        XCTAssertEqual(breaker.currentState, .closed)
        
        // Second failure opens circuit
        do {
            try await breaker.run {
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            // Expected
        }
        XCTAssertEqual(breaker.currentState, .open)
    }
    
    func testCircuitBreakerRejectsRequestsWhenOpen() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1)
        
        // Trigger open state
        do {
            try await breaker.run {
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            // Expected
        }
        
        // Further requests are rejected
        do {
            try await breaker.run {
                XCTFail("Should not execute when open")
            }
        } catch let error as CircuitBreakerError {
            XCTAssertEqual(error, .open)
        }
    }
}

final class RetryPolicyTests: XCTestCase {
    func testRetryPolicySingleSuccess() async throws {
        let policy = RetryPolicy(maxAttempts: 3)
        var attempts = 0
        
        let result = try await policy.execute {
            attempts += 1
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 1)
    }
    
    func testRetryPolicyRetriesOnFailure() async throws {
        let policy = RetryPolicy(maxAttempts: 3, initialDelayMs: 1)
        var attempts = 0
        
        let result = try await policy.execute {
            attempts += 1
            if attempts < 3 {
                throw NSError(domain: "test", code: 1)
            }
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 3)
    }
    
    func testRetryPolicyThrowsAfterMaxAttempts() async throws {
        let policy = RetryPolicy(maxAttempts: 2, initialDelayMs: 1)
        var attempts = 0
        
        do {
            try await policy.execute {
                attempts += 1
                throw NSError(domain: "test", code: 1)
            }
        } catch {
            XCTAssertEqual(attempts, 2)
        }
    }
}
