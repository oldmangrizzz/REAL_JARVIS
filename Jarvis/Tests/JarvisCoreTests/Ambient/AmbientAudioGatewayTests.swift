import XCTest
@testable import JarvisCore

final class AmbientAudioGatewayTests: XCTestCase {

    // MARK: - Mock Implementation

    private class MockAmbientAudioGateway: AmbientAudioGateway {
        // AmbientAudioGateway requirements
        var isPlaying: Bool = false
        var volume: Float = 0.5

        // Tracking calls for verification
        private(set) var playCalled = false
        private(set) var pauseCalled = false
        private(set) var stopCalled = false
        private(set) var setVolumeCalls: [Float] = []

        func play() {
            playCalled = true
            isPlaying = true
        }

        func pause() {
            pauseCalled = true
            isPlaying = false
        }

        func stop() {
            stopCalled = true
            isPlaying = false
        }

        func setVolume(_ newVolume: Float) {
            setVolumeCalls.append(newVolume)
            volume = newVolume
        }
    }

    // MARK: - Properties

    private var gateway: MockAmbientAudioGateway!

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        gateway = MockAmbientAudioGateway()
    }

    override func tearDown() {
        gateway = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testPlayChangesStateAndRecordsCall() {
        // Pre‑condition
        XCTAssertFalse(gateway.isPlaying, "Gateway should start not playing")
        XCTAssertFalse(gateway.playCalled, "Play should not have been called yet")

        // Action
        gateway.play()

        // Post‑condition
        XCTAssertTrue(gateway.playCalled, "Play should have been recorded")
        XCTAssertTrue(gateway.isPlaying, "Gateway should be playing after play()")
    }

    func testPauseChangesStateAndRecordsCall() {
        // Set up a playing state first
        gateway.isPlaying = true

        // Pre‑condition
        XCTAssertTrue(gateway.isPlaying, "Gateway should be playing before pause")
        XCTAssertFalse(gateway.pauseCalled, "Pause should not have been called yet")

        // Action
        gateway.pause()

        // Post‑condition
        XCTAssertTrue(gateway.pauseCalled, "Pause should have been recorded")
        XCTAssertFalse(gateway.isPlaying, "Gateway should not be playing after pause()")
    }

    func testStopChangesStateAndRecordsCall() {
        // Set up a playing state first
        gateway.isPlaying = true

        // Pre‑condition
        XCTAssertTrue(gateway.isPlaying, "Gateway should be playing before stop")
        XCTAssertFalse(gateway.stopCalled, "Stop should not have been called yet")

        // Action
        gateway.stop()

        // Post‑condition
        XCTAssertTrue(gateway.stopCalled, "Stop should have been recorded")
        XCTAssertFalse(gateway.isPlaying, "Gateway should not be playing after stop()")
    }

    func testVolumeCanBeAdjustedAndIsRecorded() {
        // Pre‑condition
        XCTAssertEqual(gateway.volume, 0.5, "Default volume should be 0.5")
        XCTAssertTrue(gateway.setVolumeCalls.isEmpty, "No volume changes should have been recorded yet")

        // Action
        gateway.setVolume(0.2)
        gateway.setVolume(0.9)

        // Post‑condition
        XCTAssertEqual(gateway.volume, 0.9, "Volume should reflect the last set value")
        XCTAssertEqual(gateway.setVolumeCalls, [0.2, 0.9], "All volume changes should be recorded in order")
    }
}