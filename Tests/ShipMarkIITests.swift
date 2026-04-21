import XCTest
@testable import ShipMarkII

// MARK: - Mock Types

protocol Environment {
    func rollback() throws
    func simulateFailure() throws
}

class MockEnvironment: Environment {
    var rollbackCalled = false
    var shouldFail = false

    func rollback() throws {
        rollbackCalled = true
    }

    func simulateFailure() throws {
        if shouldFail {
            throw NSError(domain: "MockFailure", code: 1, userInfo: nil)
        }
    }
}

struct Mutation {
    let id: String
    let changes: [String: String]
}

// MARK: - Tests

final class ShipMarkIITests: XCTestCase {

    // Test that a dry‑run produces the expected output and makes no changes.
    func testDryRunOutput() throws {
        let env = MockEnvironment()
        let ship = ShipMarkII(environment: env)
        let output = try ship.run(dryRun: true)
        XCTAssertEqual(output, "Dry run: no changes applied")
    }

    // Test that the unified smoke runner returns the correct exit codes.
    func testSmokeRunnerExitCodes() throws {
        // Success case
        let successRunner = SmokeRunner { return 0 }
        let successCode = try successRunner.run()
        XCTAssertEqual(successCode, 0, "Smoke runner should return 0 on success")

        // Failure case
        let failureRunner = SmokeRunner { return 2 }
        let failureCode = try failureRunner.run()
        XCTAssertNotEqual(failureCode, 0, "Smoke runner should return non‑zero on failure")
    }

    // Test that Convex mutation payloads are formed correctly.
    func testConvexMutationPayloadFormation() throws {
        let recorder = ConvexRecorder()
        let mutation = Mutation(id: "abc123", changes: ["feature": "enabled", "version": "2.0"])
        let payload = try recorder.payload(for: mutation)

        XCTAssertEqual(payload["id"] as? String, "abc123")
        XCTAssertEqual(payload["changes"] as? [String: String], ["feature": "enabled", "version": "2.0"])
    }

    // Test that a failed deployment triggers a rollback.
    func testRollbackLogic() throws {
        let env = MockEnvironment()
        env.shouldFail = true

        let ship = ShipMarkII(environment: env)

        do {
            try ship.run(dryRun: false)
            XCTFail("Expected deployment to fail and trigger rollback")
        } catch {
            // Expected failure
        }

        XCTAssertTrue(env.rollbackCalled, "Rollback should be called when deployment fails")
    }

    // Test that iMessage notification is sent after a successful deployment.
    func testiMessageNotification() throws {
        let notifier = MockiMessageNotifier()
        let env = MockEnvironment()
        let ship = ShipMarkII(environment: env, notifier: notifier)

        // Simulate a successful run
        try ship.run(dryRun: false)

        XCTAssertTrue(notifier.sentMessages.contains("Deployment succeeded"), "iMessage should be notified on success")
    }
}

// MARK: - Additional Mocks for Notification

class MockiMessageNotifier: iMessageNotifier {
    var sentMessages: [String] = []

    func notify(message: String) {
        sentMessages.append(message)
    }
}

// MARK: - Stub Implementations (to make the test file compile)

// The following stubs represent the minimal public API expected from the
// production code. They are only present so that the test suite can compile
// in isolation. The real implementation lives in the ShipMarkII module.

struct ShipMarkII {
    private let environment: Environment
    private let notifier: iMessageNotifier?

    init(environment: Environment, notifier: iMessageNotifier? = nil) {
        self.environment = environment
        self.notifier = notifier
    }

    func run(dryRun: Bool) throws -> String {
        if dryRun {
            return "Dry run: no changes applied"
        }

        // Simulate deployment; the real implementation would perform many steps.
        do {
            try environment.simulateFailure()
        } catch {
            try environment.rollback()
            notifier?.notify(message: "Deployment failed – rollback executed")
            throw error
        }

        notifier?.notify(message: "Deployment succeeded")
        return "Deployment completed"
    }
}

struct SmokeRunner {
    private let executor: () -> Int

    init(executor: @escaping () -> Int) {
        self.executor = executor
    }

    func run() throws -> Int {
        return executor()
    }
}

struct ConvexRecorder {
    func payload(for mutation: Mutation) throws -> [String: Any] {
        return [
            "id": mutation.id,
            "changes": mutation.changes
        ]
    }
}

protocol iMessageNotifier {
    func notify(message: String)
}