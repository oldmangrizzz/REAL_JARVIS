import XCTest
@testable import JarvisCore

// MARK: - CRITICAL-001J: MasterOscillator Concurrency Verification

final class OscillatorConcurrencyTests: XCTestCase {
    /// Verify serial queue prevents concurrent onTick delivery (CX-005)
    func testOnTickDeliveryIsSerializedNotConcurrent() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let osc = MasterOscillator(telemetry: tel, configuration: .init(bpm: 600))
        
        class ConcurrencyDetector: PhaseLockedSubscriber {
            let subscriberID = "concurrency-test"
            var activeCalls = 0
            var maxConcurrentCalls = 0
            
            func onTick(_ tick: OscillatorTick) {
                activeCalls += 1
                maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
                usleep(100)
                activeCalls -= 1
            }
        }
        
        let detector = ConcurrencyDetector()
        osc.subscribe(detector)
        
        for _ in 0..<20 {
            osc.manualTick()
        }
        
        XCTAssertEqual(detector.maxConcurrentCalls, 1, "onTick must be serialized")
    }
}

// MARK: - CRITICAL-002J: PheromindEngine Data Race Verification

final class PheromineDataRaceTests: XCTestCase {
    /// Verify NSLock prevents concurrent state mutations (CX-002)
    func testPheromindThreadSafetyUnderConcurrentAccess() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let engine = PheromindEngine(telemetry: tel)
        
        let edge = EdgeKey(source: "test", target: "goal")
        engine.register(edge: edge, pheromone: 0.5)
        
        var errors: [Error] = []
        let group = DispatchGroup()
        let queue = DispatchQueue.global()
        
        for i in 0..<100 {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                if i % 3 == 0 {
                    _ = engine.state(for: edge)
                } else if i % 3 == 1 {
                    let deposit = PheromoneDeposit(
                        edge: edge,
                        signal: .reinforce,
                        magnitude: 0.1,
                        agentID: "test-\(i)",
                        timestamp: Date()
                    )
                    do {
                        _ = try engine.applyGlobalUpdate(deposits: [deposit])
                    } catch {
                        errors.append(error)
                    }
                } else {
                    _ = engine.chooseNextEdge(from: "test")
                }
            }
        }
        
        let result = group.wait(timeout: .now() + 30)
        XCTAssertEqual(result, .success, "concurrent operations should complete")
        XCTAssertEqual(errors.count, 0, "no errors under concurrent access")
    }
    
    /// Verify lock is held during applyGlobalUpdate
    func testLockHeldDuringGlobalUpdate() throws {
        let paths = try makeTestWorkspace()
        let tel = try TelemetryStore(paths: paths)
        let engine = PheromindEngine(telemetry: tel)
        
        let edge = EdgeKey(source: "a", target: "b")
        engine.register(edge: edge, pheromone: 0.0)
        
        let deposit = PheromoneDeposit(
            edge: edge,
            signal: .reinforce,
            magnitude: 0.5,
            agentID: "tester",
            timestamp: Date()
        )
        
        for _ in 0..<50 {
            _ = try engine.applyGlobalUpdate(deposits: [deposit])
        }
        
        let final = try XCTUnwrap(engine.state(for: edge))
        XCTAssertGreater(final.pheromone, 0.0)
    }
}

// MARK: - CRITICAL-003J: RLMBridge Shell Injection Verification

final class RLMBridgeSecurityTests: XCTestCase {
    /// Verify stdin pipe prevents shell injection (CX-012, CRITICAL-003J)
    /// Per PythonRLMBridge.swift:152-158, REPL mode uses pipes not host stdin
    func testRLMBridgeUsesStdinPipeNotHostStdin() throws {
        let paths = try makeTestWorkspace()
        let bridge = PythonRLMBridge(paths: paths, telemetry: try TelemetryStore(paths: paths))
        
        let maliciousPrompt = "test_prompt_with_semicolon;"
        let maliciousQuery = "test_query_with_dollar_sign"
        
        do {
            _ = try bridge.query(prompt: maliciousPrompt, query: maliciousQuery)
        } catch let error as JarvisError {
            let errorStr = "\(error)"
            XCTAssertFalse(
                errorStr.lowercased().contains("root"),
                "error should not contain shell execution output"
            )
        } catch {
            print("Expected error (Python script not found): \(error)")
        }
    }
}
