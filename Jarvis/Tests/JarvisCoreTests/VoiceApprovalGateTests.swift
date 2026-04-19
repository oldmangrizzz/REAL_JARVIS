import XCTest
@testable import JarvisCore

final class VoiceApprovalGateTests: XCTestCase {
    private func writeTempAudio(_ paths: WorkspacePaths, name: String, payload: String) throws -> URL {
        let dir = paths.storageRoot.appendingPathComponent("voice-test", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try payload.data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeSession(paths: WorkspacePaths,
                             modelRepo: String = "mlx-community/fish-audio-s2-pro-8bit",
                             transcript: String = "hello this is grizz",
                             audioPayload: String = "SYNTHETIC-REF-AUDIO-BLOB-A") throws -> VoiceSessionConfiguration {
        let audioURL = try writeTempAudio(paths, name: "ref-\(UUID().uuidString).wav", payload: audioPayload)
        let profile = VoiceReferenceProfile(sampleCount: 1, averageDuration: 2.0, averageEnergy: 0.1, averageSampleRate: 44_100)
        return VoiceSessionConfiguration(
            selectedVoice: "mlx-fish-audio-s2-pro-clone",
            rate: 44_100,
            profile: profile,
            modelRepository: modelRepo,
            referenceAudioURL: audioURL,
            referenceTranscript: transcript
        )
    }

    func testNotApprovedByDefault() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        XCTAssertFalse(gate.isApproved(for: session, personaFramingVersion: "v1"))
        XCTAssertThrowsError(try gate.requireApproved(for: session, personaFramingVersion: "v1")) { error in
            guard case VoiceApprovalError.notApproved = error else {
                return XCTFail("Expected .notApproved, got \(error)")
            }
        }
    }

    func testApproveThenRequireApprovedPasses() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        let record = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        XCTAssertEqual(record.operatorLabel, "grizz@gmri")
        XCTAssertTrue(gate.isApproved(for: session, personaFramingVersion: "v1"))
        XCTAssertNoThrow(try gate.requireApproved(for: session, personaFramingVersion: "v1"))
    }

    func testDriftOnModelChangeInvalidatesApproval() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let approved = try makeSession(paths: paths, modelRepo: "model-A")
        _ = try gate.approve(session: approved, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")

        let drifted = VoiceSessionConfiguration(
            selectedVoice: approved.selectedVoice,
            rate: approved.rate,
            profile: approved.profile,
            modelRepository: "model-B-DIFFERENT",
            referenceAudioURL: approved.referenceAudioURL,
            referenceTranscript: approved.referenceTranscript
        )
        XCTAssertFalse(gate.isApproved(for: drifted, personaFramingVersion: "v1"))
        XCTAssertThrowsError(try gate.requireApproved(for: drifted, personaFramingVersion: "v1")) { error in
            guard case VoiceApprovalError.drift = error else {
                return XCTFail("Expected .drift, got \(error)")
            }
        }
    }

    func testDriftOnTranscriptChangeInvalidatesApproval() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let a = try makeSession(paths: paths, transcript: "one two three")
        _ = try gate.approve(session: a, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        let b = VoiceSessionConfiguration(
            selectedVoice: a.selectedVoice, rate: a.rate, profile: a.profile,
            modelRepository: a.modelRepository,
            referenceAudioURL: a.referenceAudioURL,
            referenceTranscript: "DIFFERENT TRANSCRIPT"
        )
        XCTAssertThrowsError(try gate.requireApproved(for: b, personaFramingVersion: "v1"))
    }

    func testDriftOnPersonaFramingVersion() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        _ = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        XCTAssertThrowsError(try gate.requireApproved(for: session, personaFramingVersion: "v2"))
    }

    func testDriftOnReferenceAudioContentInvalidatesApproval() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths, audioPayload: "ORIGINAL-A")
        _ = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        // Overwrite the reference audio file with different bytes; the
        // path is the same but the digest moves.
        try "MUTATED-B".data(using: .utf8)!.write(to: session.referenceAudioURL)
        XCTAssertFalse(gate.isApproved(for: session, personaFramingVersion: "v1"))
    }

    func testRevokeClearsApproval() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        _ = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        XCTAssertTrue(gate.isApproved(for: session, personaFramingVersion: "v1"))
        try gate.revoke()
        XCTAssertFalse(gate.isApproved(for: session, personaFramingVersion: "v1"))
    }

    func testGateFileWrittenWithRestrictivePermissions() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        _ = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizz@gmri")
        let attrs = try FileManager.default.attributesOfItem(atPath: gate.gateFileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o600)
    }

    func testMalformedGateFileIsRejected() throws {
        let paths = try makeTestWorkspace()
        let gate = VoiceApprovalGate(paths: paths)
        let session = try makeSession(paths: paths)
        try FileManager.default.createDirectory(
            at: gate.gateFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not-json-at-all".write(to: gate.gateFileURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(gate.isApproved(for: session, personaFramingVersion: "v1"))
        XCTAssertThrowsError(try gate.requireApproved(for: session, personaFramingVersion: "v1"))
    }

    func testTelemetryFiresOnApproveRevokeAndDrift() throws {
        let paths = try makeTestWorkspace()
        let recorder = SpyVoiceGateTelemetry()
        let gate = VoiceApprovalGate(paths: paths, telemetry: recorder, hostNode: "test-host")
        let session = try makeSession(paths: paths)

        // Refused before approval — should emit playback_refused + absent state.
        XCTAssertThrowsError(try gate.requireApproved(for: session, personaFramingVersion: "v1"))
        XCTAssertEqual(recorder.events.last?.eventType, "playback_refused")
        XCTAssertEqual(recorder.states.last?.state, "absent")

        // Approve — should emit approved + green state.
        let approved = try gate.approve(session: session, personaFramingVersion: "v1", operatorLabel: "grizzly")
        XCTAssertEqual(recorder.events.last?.eventType, "approved")
        XCTAssertEqual(recorder.events.last?.composite, approved.composite)
        XCTAssertEqual(recorder.states.last?.state, "green")
        XCTAssertEqual(recorder.states.last?.composite, approved.composite)
        XCTAssertEqual(recorder.states.last?.hostNode, "test-host")

        // Drift — change transcript and require approval should emit drift_detected.
        let driftedSession = try makeSession(paths: paths, transcript: "different transcript")
        // Re-approve original first so the gate file exists; then immediately
        // attempt drift detection by checking against drifted fingerprint.
        XCTAssertThrowsError(try gate.requireApproved(for: driftedSession, personaFramingVersion: "v1")) { error in
            guard case VoiceApprovalError.drift = error else {
                return XCTFail("Expected .drift, got \(error)")
            }
        }
        XCTAssertEqual(recorder.events.last?.eventType, "drift_detected")
        XCTAssertEqual(recorder.states.last?.state, "drifted")
        XCTAssertNotNil(recorder.events.last?.expectedComposite)

        // Revoke — should emit revoked + revoked state.
        try gate.revoke()
        XCTAssertEqual(recorder.events.last?.eventType, "revoked")
        XCTAssertEqual(recorder.states.last?.state, "revoked")
    }
}

// MARK: - Test fixtures

private final class SpyVoiceGateTelemetry: VoiceGateTelemetryRecording {
    struct EventCall {
        let hostNode: String
        let eventType: String
        let composite: String?
        let expectedComposite: String?
        let operatorLabel: String?
        let notes: String?
    }
    struct StateCall {
        let hostNode: String
        let state: String
        let composite: String?
        let expectedComposite: String?
        let operatorLabel: String?
    }

    private(set) var events: [EventCall] = []
    private(set) var states: [StateCall] = []

    func logVoiceGateEvent(hostNode: String,
                           eventType: String,
                           composite: String?,
                           expectedComposite: String?,
                           operatorLabel: String?,
                           notes: String?) throws {
        events.append(EventCall(hostNode: hostNode,
                                eventType: eventType,
                                composite: composite,
                                expectedComposite: expectedComposite,
                                operatorLabel: operatorLabel,
                                notes: notes))
    }

    func syncVoiceGateState(hostNode: String,
                            state: String,
                            composite: String?,
                            expectedComposite: String?,
                            referenceAudioDigest: String?,
                            referenceTranscriptDigest: String?,
                            modelRepository: String?,
                            personaFramingVersion: String?,
                            operatorLabel: String?,
                            approvedAtISO8601: String?,
                            notes: String?) throws {
        states.append(StateCall(hostNode: hostNode,
                                state: state,
                                composite: composite,
                                expectedComposite: expectedComposite,
                                operatorLabel: operatorLabel))
    }
}
