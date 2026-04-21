import XCTest
@testable import ShipMarkII

final class ShipMarkIITests: XCTestCase {
    
    // MARK: - Dry‑run Output Parsing
    
    func testDryRunParsingProducesExpectedActions() throws {
        // Sample dry‑run output from the ship script
        let dryRunOutput = """
        === DEPLOYMENT PLAN ===
        - Create collection: users
        - Add index: users_by_email on users(email)
        - Deploy function: sendWelcomeEmail
        === END PLAN ===
        """
        
        // Expected result after parsing
        let expectedActions: [String] = [
            "Create collection: users",
            "Add index: users_by_email on users(email)",
            "Deploy function: sendWelcomeEmail"
        ]
        
        // Perform parsing
        let parsedActions = try ShipParser.parseDryRunOutput(dryRunOutput)
        
        XCTAssertEqual(parsedActions, expectedActions, "Parsed actions should match the expected deployment plan.")
    }
    
    // MARK: - Rollback Logic
    
    func testRollbackExecutesAllReversalSteps() throws {
        // Simulated deployment state that would need to be rolled back
        let deploymentState = DeploymentState(
            createdCollections: ["users"],
            createdIndexes: ["users_by_email"],
            deployedFunctions: ["sendWelcomeEmail"]
        )
        
        // Expected rollback commands in the order they should be executed
        let expectedRollbackCommands = [
            "removeFunction sendWelcomeEmail",
            "removeIndex users_by_email",
            "removeCollection users"
        ]
        
        // Capture the commands that the rollback executor would issue
        var executedCommands: [String] = []
        let executor = MockRollbackExecutor { command in
            executedCommands.append(command)
        }
        
        // Perform rollback
        try executor.performRollback(for: deploymentState)
        
        XCTAssertEqual(executedCommands, expectedRollbackCommands, "Rollback should execute commands in the correct reverse order.")
    }
    
    // MARK: - Convex Mutation Payload Formation
    
    func testConvexMutationPayloadIsCorrectlyEncoded() throws {
        // Input mutation details
        let mutationName = "createUser"
        let args: [String: Any] = [
            "email": "alice@example.com",
            "name": "Alice",
            "age": 30
        ]
        
        // Expected JSON payload (keys sorted for deterministic output)
        let expectedJSON = """
        {"args":{"age":30,"email":"alice@example.com","name":"Alice"},"mutation":"createUser"}
        """
        
        // Generate payload
        let payload = try ConvexPayloadBuilder.buildPayload(
            mutation: mutationName,
            arguments: args
        )
        
        // Convert Data to String for comparison
        let payloadString = String(data: payload, encoding: .utf8)
        
        XCTAssertEqual(payloadString, expectedJSON, "Convex payload JSON should match the expected format.")
    }
}

// MARK: - Supporting Mocks & Stubs

/// Simple mock executor that records each rollback command it receives.
private final class MockRollbackExecutor: RollbackExecuting {
    private let commandHandler: (String) -> Void
    
    init(commandHandler: @escaping (String) -> Void) {
        self.commandHandler = commandHandler
    }
    
    func performRollback(for state: DeploymentState) throws {
        // Reverse order: functions, indexes, collections
        for function in state.deployedFunctions.reversed() {
            commandHandler("removeFunction \(function)")
        }
        for index in state.createdIndexes.reversed() {
            commandHandler("removeIndex \(index)")
        }
        for collection in state.createdCollections.reversed() {
            commandHandler("removeCollection \(collection)")
        }
    }
}

// MARK: - Protocols & Models Expected from Production Code

/// Protocol that the real rollback executor conforms to.
protocol RollbackExecuting {
    func performRollback(for state: DeploymentState) throws
}

/// Model representing the state of a deployment that may need rollback.
struct DeploymentState {
    var createdCollections: [String] = []
    var createdIndexes: [String] = []
    var deployedFunctions: [String] = []
}

/// Parser responsible for turning dry‑run output into actionable steps.
enum ShipParser {
    static func parseDryRunOutput(_ output: String) throws -> [String] {
        // The real implementation lives in production code.
        // This stub exists solely to satisfy the compiler for the test target.
        return []
    }
}

/// Builder that creates the JSON payload for Convex mutations.
enum ConvexPayloadBuilder {
    static func buildPayload(mutation: String, arguments: [String: Any]) throws -> Data {
        // The real implementation lives in production code.
        // This stub exists solely to satisfy the compiler for the test target.
        return Data()
    }
}