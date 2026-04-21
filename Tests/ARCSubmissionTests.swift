import XCTest
@testable import ARCSubmission

// MARK: - Mock Services

/// A mock Remote Language Model (RLM) service that can be configured to simulate various behaviours.
final class MockRLMService: RLMService {
    enum Behaviour {
        case success(response: String)
        case delay(seconds: TimeInterval)
        case failure(error: Error)
    }
    
    var behaviour: Behaviour = .success(response: "{}")
    
    func generateResponse(for prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        switch behaviour {
        case .success(let response):
            completion(.success(response))
        case .delay(let seconds):
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                // After the delay we still succeed with a dummy response.
                completion(.success("{}"))
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

// MARK: - Test Suite

final class ARCSubmissionTests: XCTestCase {
    
    // Helper to create a minimal valid task.
    private func makeValidTask() -> ARCSubmissionTask {
        let inputJSON = """
        {
            "prompt": "Translate the following to French:",
            "data": "Hello, world!"
        }
        """
        let witness = ARCSubmissionWitness(
            signature: Data([0xAA, 0xBB, 0xCC]),
            publicKey: Data([0x01, 0x02, 0x03])
        )
        let shape = ARCSubmissionShape(
            width: 640,
            height: 480,
            channels: 3
        )
        return ARCSubmissionTask(
            inputJSON: inputJSON,
            witness: witness,
            shape: shape,
            timeout: 5.0
        )
    }
    
    // MARK: - Happy Path
    
    func testOrchestratorHappyPath() {
        let expectation = self.expectation(description: "Successful submission")
        let mockRLM = MockRLMService()
        mockRLM.behaviour = .success(response: """
        {
            "result": "Bonjour, le monde!"
        }
        """)
        let orchestrator = ARCOrchestrator(rlmService: mockRLM)
        let task = makeValidTask()
        
        orchestrator.submit(task: task) { result in
            switch result {
            case .success(let submissionResult):
                XCTAssertEqual(submissionResult.output, "Bonjour, le monde!")
                XCTAssertNotNil(submissionResult.witnessVerification)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    // MARK: - Invalid JSON Handling
    
    func testInvalidJSONHandling() {
        let expectation = self.expectation(description: "Invalid JSON should fail")
        let mockRLM = MockRLMService()
        let orchestrator = ARCOrchestrator(rlmService: mockRLM)
        
        var task = makeValidTask()
        task.inputJSON = "{ invalid json }" // malformed
        
        orchestrator.submit(task: task) { result in
            switch result {
            case .success:
                XCTFail("Expected failure due to invalid JSON")
            case .failure(let error):
                if let arcError = error as? ARCSubmissionError,
                   case .invalidJSON = arcError {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected ARCSubmissionError.invalidJSON, got \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    // MARK: - RLM Timeout
    
    func testRLMTImeout() {
        let expectation = self.expectation(description: "RLM timeout should be reported")
        let mockRLM = MockRLMService()
        // Simulate a delay longer than the task timeout.
        mockRLM.behaviour = .delay(seconds: 3.0)
        let orchestrator = ARCOrchestrator(rlmService: mockRLM)
        
        var task = makeValidTask()
        task.timeout = 1.0 // very short timeout
        
        orchestrator.submit(task: task) { result in
            switch result {
            case .success:
                XCTFail("Expected timeout failure")
            case .failure(let error):
                if let arcError = error as? ARCSubmissionError,
                   case .timeout = arcError {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected ARCSubmissionError.timeout, got \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 4.0, handler: nil)
    }
    
    // MARK: - Shape Mismatch
    
    func testShapeMismatchDetection() {
        let expectation = self.expectation(description: "Shape mismatch should be detected")
        let mockRLM = MockRLMService()
        mockRLM.behaviour = .success(response: "{}")
        let orchestrator = ARCOrchestrator(rlmService: mockRLM)
        
        var task = makeValidTask()
        // Intentionally set an impossible shape (e.g., zero width)
        task.shape = ARCSubmissionShape(width: 0, height: 480, channels: 3)
        
        orchestrator.submit(task: task) { result in
            switch result {
            case .success:
                XCTFail("Expected shape mismatch failure")
            case .failure(let error):
                if let arcError = error as? ARCSubmissionError,
                   case .shapeMismatch = arcError {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected ARCSubmissionError.shapeMismatch, got \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
    
    // MARK: - Witness Tamper Detection
    
    func testWitnessTamperDetection() {
        let expectation = self.expectation(description: "Witness tampering should be detected")
        let mockRLM = MockRLMService()
        mockRLM.behaviour = .success(response: "{}")
        let orchestrator = ARCOrchestrator(rlmService: mockRLM)
        
        var task = makeValidTask()
        // Simulate tampering by altering the witness after it was supposedly signed.
        var tamperedWitness = task.witness
        tamperedWitness.signature = Data([0xFF, 0xEE, 0xDD]) // corrupt signature
        task.witness = tamperedWitness
        
        orchestrator.submit(task: task) { result in
            switch result {
            case .success:
                XCTFail("Expected witness tamper detection failure")
            case .failure(let error):
                if let arcError = error as? ARCSubmissionError,
                   case .witnessTampered = arcError {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected ARCSubmissionError.witnessTampered, got \(error)")
                }
            }
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
}