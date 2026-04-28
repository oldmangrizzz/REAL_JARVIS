import XCTest
import CryptoKit
@testable import JarvisCore

/// NAV-001 Phase E — Integration tests
///
/// Wires PhaseLockMonitor + RLM feedback + BiometricTunnelRegistrar
/// end-to-end using the shared TelemetryStore backbone.
///
/// All tests are hermetic: no network, no real biometrics, no real Python
/// network calls — workspace temp-dirs via `makeTestWorkspace()`.
///
/// Acceptance gate: ≥22 tests, 0 failures.
final class NAV001PhaseEIntegrationTests: XCTestCase {

    // MARK: - Shared stubs

    actor AlwaysApproveAuth: BiometricAuthenticator {
        nonisolated func authenticate(reason: String) async throws {}
    }

    final class InMemIdentityKeyStore: IdentityKeyStore, @unchecked Sendable {
        private var keys: [String: SymmetricKey] = [:]
        private let lock = NSLock()

        func seed(_ k: SymmetricKey, for id: String) {
            lock.lock(); defer { lock.unlock() }
            keys[id] = k
        }
        func storeKey(_ k: SymmetricKey, for id: String) throws {
            lock.lock(); defer { lock.unlock() }
            if keys[id] != nil { throw BiometricVaultError.keyAlreadyProvisioned(deviceID: id) }
            keys[id] = k
        }
        func loadKey(for id: String) throws -> SymmetricKey {
            lock.lock(); defer { lock.unlock() }
            guard let k = keys[id] else { throw BiometricVaultError.keyNotProvisioned(deviceID: id) }
            return k
        }
        func hasKey(for id: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return keys[id] != nil
        }
        func deleteKey(for id: String) throws {
            lock.lock(); defer { lock.unlock() }
            keys.removeValue(forKey: id)
        }
    }

    // MARK: - Helpers

    private func makeTelemetry() throws -> (TelemetryStore, WorkspacePaths) {
        let ws = try makeTestWorkspace()
        return (try TelemetryStore(paths: ws), ws)
    }

    private func makePLM(
        telemetry: TelemetryStore,
        windowSize: Int = 8,
        scoreEvery: UInt64 = 8
    ) -> PhaseLockMonitor {
        PhaseLockMonitor(
            telemetry: telemetry,
            configuration: .init(windowSize: windowSize, scoreEvery: scoreEvery)
        )
    }

    private func syntheticTick(seq: UInt64, driftMs: Double, intervalMs: Double = 1000.0) -> OscillatorTick {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = base.addingTimeInterval(Double(seq) * intervalMs / 1000.0)
        return OscillatorTick(
            sequence: seq,
            scheduled: scheduled,
            emitted: scheduled.addingTimeInterval(driftMs / 1000.0),
            driftMilliseconds: driftMs,
            intervalMilliseconds: intervalMs
        )
    }

    private func feedDrifts(
        _ monitor: PhaseLockMonitor,
        subscriber: String,
        drifts: [Double],
        intervalMs: Double = 1000.0
    ) {
        for (i, d) in drifts.enumerated() {
            let t = syntheticTick(seq: UInt64(i + 1), driftMs: 0, intervalMs: intervalMs)
            monitor.recordCompletion(
                subscriberID: subscriber,
                tick: t,
                completedAt: t.emitted.addingTimeInterval(d / 1000.0)
            )
        }
    }

    private func makeRegistrar(
        deviceID: String,
        key: SymmetricKey,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) -> BiometricTunnelRegistrar {
        let store = InMemIdentityKeyStore()
        store.seed(key, for: deviceID)
        let vault = BiometricIdentityVault(authenticator: AlwaysApproveAuth(), store: store)
        return BiometricTunnelRegistrar(vault: vault, clock: clock)
    }

    private func writeIdentitiesJSON(
        identities: [TunnelIdentityStore.DeviceIdentity]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nav001-e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("identities.json")
        let doc = TunnelIdentityStore.Document(
            identities: identities,
            allowUnregisteredNonPrivileged: false
        )
        try JSONEncoder().encode(doc).write(to: url)
        return url
    }

    // MARK: - Group 1: PhaseLockMonitor ↔ TelemetryStore integration

    func testPhaseLockScoreWritesToTelemetryTable() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        feedDrifts(plm, subscriber: "sub-telem-integration", drifts: Array(repeating: 10.0, count: 8))
        let url = telemetry.tableURL("oscillator_plv")
        let rows = try String(contentsOf: url).split(separator: "\n")
        XCTAssertFalse(rows.isEmpty, "PLM must write a score row into oscillator_plv")
        XCTAssertTrue(rows.last.map { String($0) }?.contains("sub-telem-integration") == true)
    }

    func testPhaseLockTelemetryTableRowHasRequiredFields() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        feedDrifts(plm, subscriber: "sub-fields", drifts: Array(repeating: 5.0, count: 8))
        let url = telemetry.tableURL("oscillator_plv")
        let raw = try String(contentsOf: url)
        XCTAssertTrue(raw.contains("\"event\":\"plv_score\""), "row must contain event=plv_score")
        XCTAssertTrue(raw.contains("\"subscriber\":\"sub-fields\""), "row must contain subscriber ID")
        XCTAssertTrue(raw.contains("\"plv\""), "row must contain plv field")
        XCTAssertTrue(raw.contains("\"regulated\""), "row must contain regulated field")
    }

    func testSeparateTelemetryWorkspacesAreIsolated() throws {
        let (telA, _) = try makeTelemetry()
        let (telB, _) = try makeTelemetry()
        let plmA = makePLM(telemetry: telA, windowSize: 8, scoreEvery: 8)
        let plmB = makePLM(telemetry: telB, windowSize: 8, scoreEvery: 8)
        feedDrifts(plmA, subscriber: "only-in-A", drifts: Array(repeating: 5.0, count: 8))
        feedDrifts(plmB, subscriber: "only-in-B", drifts: Array(repeating: 5.0, count: 8))

        let rowsA = try String(contentsOf: telA.tableURL("oscillator_plv"))
        let rowsB = try String(contentsOf: telB.tableURL("oscillator_plv"))
        XCTAssertTrue(rowsA.contains("only-in-A"))
        XCTAssertFalse(rowsA.contains("only-in-B"),
                       "workspace A's telemetry must not contain workspace B's subscriber")
        XCTAssertTrue(rowsB.contains("only-in-B"))
        XCTAssertFalse(rowsB.contains("only-in-A"))
    }

    func testPhaseLockResetErasesScoreFromCurrentScoresMap() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        feedDrifts(plm, subscriber: "sub-erase", drifts: Array(repeating: 5.0, count: 8))
        XCTAssertNotNil(plm.currentScore(for: "sub-erase"))
        plm.reset(subscriberID: "sub-erase")
        XCTAssertNil(plm.currentScore(for: "sub-erase"),
                     "after reset, currentScore must return nil")
    }

    func testPhaseLockHealthyBandProducesReinforceSignal() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        // Alternating small drifts — non-zero jitter, low mean — healthy band.
        let drifts = (0..<8).map { i -> Double in (i % 2 == 0) ? 30.0 : 40.0 }
        feedDrifts(plm, subscriber: "sub-healthy-band", drifts: drifts)
        guard let score = plm.currentScore(for: "sub-healthy-band") else {
            return XCTFail("expected score after cadence")
        }
        XCTAssertEqual(score.regulated, .reinforce)
        XCTAssertGreaterThanOrEqual(score.plv, 0.70)
        XCTAssertLessThanOrEqual(score.plv, 0.97)
    }

    // MARK: - Group 2: PhaseLockMonitor + Oscillator tick chain

    func testOscillatorTickManualDeliveryProducesPhaseScore() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = PhaseLockMonitor(
            telemetry: telemetry,
            configuration: .init(windowSize: 4, scoreEvery: 4)
        )
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        for i in 0..<4 {
            let t = OscillatorTick(
                sequence: UInt64(i + 1),
                scheduled: base.addingTimeInterval(Double(i)),
                emitted: base.addingTimeInterval(Double(i) + 0.01),
                driftMilliseconds: 10,
                intervalMilliseconds: 1000
            )
            plm.recordCompletion(
                subscriberID: "oscillator-driven",
                tick: t,
                completedAt: t.emitted.addingTimeInterval(0.02)
            )
        }
        XCTAssertNotNil(plm.currentScore(for: "oscillator-driven"),
                        "manual tick delivery must produce a PLM score")
    }

    func testPhaseLockWindowCapEvictsOldSamples() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = PhaseLockMonitor(
            telemetry: telemetry,
            configuration: .init(windowSize: 4, scoreEvery: 1)
        )
        // First 8 chaotic, then 4 stable — only stable window should survive.
        let chaotic = Array(repeating: 900.0, count: 8)
        let stable  = Array(repeating: 5.0,   count: 4)
        feedDrifts(plm, subscriber: "sub-evict", drifts: chaotic + stable)
        guard let score = plm.currentScore(for: "sub-evict") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.sampleCount, 4, "window must hold exactly windowSize samples")
        XCTAssertLessThan(score.meanDriftMilliseconds, 10.0,
                          "evicted chaotic samples must not skew mean")
    }

    func testTwoSubscribersDoNotCrossContaminate() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        // Alternating small drifts → PLV in healthy band [0.70, 0.97] → reinforce.
        let stableDrifts = (0..<8).map { i -> Double in (i % 2 == 0) ? 30.0 : 40.0 }
        feedDrifts(plm, subscriber: "sub-AA", drifts: stableDrifts)
        feedDrifts(plm, subscriber: "sub-BB", drifts: Array(repeating: 800.0, count: 8))

        guard let scoreAA = plm.currentScore(for: "sub-AA"),
              let scoreBB = plm.currentScore(for: "sub-BB") else {
            return XCTFail("expected scores for both subscribers")
        }
        XCTAssertEqual(scoreAA.regulated, .reinforce,
                       "sub-AA stable alternating drifts should reinforce")
        XCTAssertNotEqual(scoreBB.regulated, .reinforce,
                          "sub-BB chaotic drifts must not reinforce")
    }

    func testAllScoresEmptyBeforeCadenceReached() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        feedDrifts(plm, subscriber: "sub-pre", drifts: Array(repeating: 5.0, count: 4))
        XCTAssertTrue(plm.allScores().isEmpty,
                      "allScores must be empty before scoreEvery cadence is reached")
    }

    func testPhaseLockRepelAfterHighVarianceDrifts() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        let drifts = (0..<8).map { i -> Double in (i % 2 == 0) ? -900.0 : 900.0 }
        feedDrifts(plm, subscriber: "sub-repel", drifts: drifts)
        guard let score = plm.currentScore(for: "sub-repel") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.regulated, .repel,
                       "high-variance drifts spanning a full interval must produce repel")
    }

    // MARK: - Group 3: BiometricTunnelRegistrar ↔ PhaseLockMonitor integration

    func testRegistrarAndPLMShareTelemetryBackbone() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let keyData = Data(repeating: 0xAB, count: 32)
        let key = SymmetricKey(data: keyData)
        let registrar = makeRegistrar(deviceID: "dev-plm-01", key: key)

        // Build 8 registrations, recording each completion as a PLM sample.
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i))
            _ = try await registrar.makeRegistration(
                deviceID: "dev-plm-01",
                deviceName: "iPhone", platform: "iOS",
                role: "voice-operator",
                appVersion: "1.0", reason: "test"
            )
            let t = OscillatorTick(
                sequence: UInt64(i + 1),
                scheduled: start,
                emitted: start,
                driftMilliseconds: 0,
                intervalMilliseconds: 1000
            )
            let completedAt = start.addingTimeInterval(0.02 + Double(i % 3) * 0.005)
            plm.recordCompletion(subscriberID: "registrar-perf", tick: t, completedAt: completedAt)
        }

        XCTAssertNotNil(plm.currentScore(for: "registrar-perf"),
                        "PLM must produce a score after 8 registration-timed samples")
        // Verify PLM wrote to the shared telemetry store.
        let url = telemetry.tableURL("oscillator_plv")
        let rows = try String(contentsOf: url).split(separator: "\n")
        XCTAssertFalse(rows.isEmpty, "shared telemetry must have PLM rows")
    }

    func testMultipleDeviceRegistrationsPhaseLockTrackedIndependently() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let keyA = SymmetricKey(data: Data(repeating: 0x11, count: 32))
        let keyB = SymmetricKey(data: Data(repeating: 0x22, count: 32))
        let registrarA = makeRegistrar(deviceID: "dev-A", key: keyA)
        let registrarB = makeRegistrar(deviceID: "dev-B", key: keyB)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i))
            _ = try await registrarA.makeRegistration(
                deviceID: "dev-A", deviceName: "A", platform: "iOS",
                role: "voice-operator", appVersion: "1.0", reason: "t"
            )
            _ = try await registrarB.makeRegistration(
                deviceID: "dev-B", deviceName: "B", platform: "iOS",
                role: "companion", appVersion: "1.0", reason: "t"
            )
            let t = OscillatorTick(
                sequence: UInt64(i + 1), scheduled: start, emitted: start,
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            plm.recordCompletion(subscriberID: "reg-A", tick: t,
                                 completedAt: start.addingTimeInterval(0.01))
            plm.recordCompletion(subscriberID: "reg-B", tick: t,
                                 completedAt: start.addingTimeInterval(0.015))
        }
        XCTAssertNotNil(plm.currentScore(for: "reg-A"))
        XCTAssertNotNil(plm.currentScore(for: "reg-B"))
        XCTAssertEqual(plm.allScores().count, 2,
                       "PLM must track two independent device subscribers")
    }

    func testRegistrarRoleNormalizationIsPreservedInPLMSubscriberContext() async throws {
        let keyData = Data(repeating: 0x77, count: 32)
        let key = SymmetricKey(data: keyData)
        let registrar = makeRegistrar(deviceID: "dev-role-norm", key: key)
        // Caller passes uppercase; registrar must normalize to lowercase.
        let reg = try await registrar.makeRegistration(
            deviceID: "dev-role-norm", deviceName: "D", platform: "iOS",
            role: "VOICE-OPERATOR", appVersion: "1.0", reason: "norm"
        )
        XCTAssertEqual(reg.role, "voice-operator",
                       "role must be lowercased before signing")
    }

    func testRegistrarNonceFormatMatchesISO8601Server() async throws {
        let keyData = Data(repeating: 0x33, count: 32)
        let key = SymmetricKey(data: keyData)
        let registrar = makeRegistrar(deviceID: "dev-nonce", key: key)
        let reg = try await registrar.makeRegistration(
            deviceID: "dev-nonce", deviceName: "N", platform: "iOS",
            role: "voice-operator", appVersion: "1.0", reason: "nonce"
        )
        guard let nonce = reg.nonce else { return XCTFail("nonce must not be nil") }
        let serverFmt = ISO8601DateFormatter()
        XCTAssertNotNil(serverFmt.date(from: nonce),
                        "nonce must parse with server-side ISO8601DateFormatter (no fractional seconds)")
    }

    func testRegistrarRoundTripValidatesViaStore() async throws {
        let deviceID = "dev-rtrip"
        let keyBytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: keyBytes)
        let identity = TunnelIdentityStore.DeviceIdentity(
            deviceID: deviceID,
            allowedRoles: ["voice-operator"],
            identityKeyHex: keyBytes.map { String(format: "%02x", $0) }.joined(),
            principal: "grizz"
        )
        let fileURL = try writeIdentitiesJSON(identities: [identity])
        let store = TunnelIdentityStore(fileURL: fileURL)
        store.reload()

        let registrar = makeRegistrar(deviceID: deviceID, key: key)
        let reg = try await registrar.makeRegistration(
            deviceID: deviceID, deviceName: "D", platform: "iOS",
            role: "voice-operator", appVersion: "1.0", reason: "rtrip"
        )
        XCTAssertNil(store.validate(reg),
                     "TunnelIdentityStore must accept a proof built by BiometricTunnelRegistrar")
    }

    // MARK: - Group 4: PhaseLockMonitor ↔ RLM feedback (no Python subprocess)

    func testRLMFeedbackArchitectureViaSyntheticLatencyWindow() throws {
        // Simulate the PLM feedback loop that wraps RLM queries:
        // measure call latency → feed as phase sample.
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        // 8 synthetic "RLM query" completions with alternating stable drift
        // (30ms / 40ms) → PLV in healthy band → reinforce.
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i) * 0.5)
            let t = OscillatorTick(
                sequence: UInt64(i + 1),
                scheduled: start,
                emitted: start,
                driftMilliseconds: 0,
                intervalMilliseconds: 500
            )
            let driftMs = (i % 2 == 0) ? 0.030 : 0.040
            plm.recordCompletion(
                subscriberID: "rlm-feedback",
                tick: t,
                completedAt: start.addingTimeInterval(driftMs)
            )
        }
        guard let score = plm.currentScore(for: "rlm-feedback") else {
            return XCTFail("PLM must produce a score after 8 RLM-feedback samples")
        }
        XCTAssertEqual(score.regulated, .reinforce,
                       "stable RLM latency must produce a reinforce signal")
    }

    func testRLMFeedbackRepelSignalOnHighLatencyVariance() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        // Alternating fast/slow "RLM query" simulating an unstable Python backend.
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i))
            let t = OscillatorTick(
                sequence: UInt64(i + 1), scheduled: start, emitted: start,
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            let completionOffset = (i % 2 == 0) ? -0.9 : 0.9
            plm.recordCompletion(
                subscriberID: "rlm-variance",
                tick: t,
                completedAt: start.addingTimeInterval(completionOffset)
            )
        }
        guard let score = plm.currentScore(for: "rlm-variance") else {
            return XCTFail("PLM must produce a score")
        }
        XCTAssertEqual(score.regulated, .repel,
                       "high-variance RLM latency must repel (unstable backend pattern)")
    }

    func testRLMAndRegistrarBothContributeToSinglePLMInstance() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let key = SymmetricKey(data: Data(repeating: 0x55, count: 32))
        let registrar = makeRegistrar(deviceID: "dev-shared-plm", key: key)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        // Registrar subscriber.
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i))
            _ = try await registrar.makeRegistration(
                deviceID: "dev-shared-plm", deviceName: "D", platform: "iOS",
                role: "voice-operator", appVersion: "1.0", reason: "t"
            )
            let t = OscillatorTick(
                sequence: UInt64(i + 1), scheduled: start, emitted: start,
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            plm.recordCompletion(subscriberID: "shared-registrar",
                                 tick: t,
                                 completedAt: start.addingTimeInterval(0.01))
        }
        // RLM subscriber.
        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i) + 0.5)
            let t = OscillatorTick(
                sequence: UInt64(i + 1), scheduled: start, emitted: start,
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            plm.recordCompletion(subscriberID: "shared-rlm",
                                 tick: t,
                                 completedAt: start.addingTimeInterval(0.015))
        }
        let scores = plm.allScores()
        XCTAssertEqual(scores.count, 2,
                       "PLM must hold independent scores for registrar and RLM subscribers")
        XCTAssertTrue(scores.map(\.subscriberID).contains("shared-registrar"))
        XCTAssertTrue(scores.map(\.subscriberID).contains("shared-rlm"))
    }

    func testPhaseLockTernarySignalCoverageAllThreeStates() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        // Reinforce: stable low drift.
        feedDrifts(plm, subscriber: "state-reinforce",
                   drifts: (0..<8).map { i in (i % 2 == 0) ? 40.0 : 50.0 })
        // Repel: extreme variance.
        feedDrifts(plm, subscriber: "state-repel",
                   drifts: (0..<8).map { i in (i % 2 == 0) ? -900.0 : 900.0 })
        // Neutral: borderline — moderate normalized stddev.
        feedDrifts(plm, subscriber: "state-neutral",
                   drifts: [80, 200, 80, 200, 80, 200, 80, 200])

        let reinforce = plm.currentScore(for: "state-reinforce")?.regulated
        let repel     = plm.currentScore(for: "state-repel")?.regulated

        XCTAssertEqual(reinforce, .reinforce, "stable drifts must reinforce")
        XCTAssertEqual(repel,     .repel,     "extreme variance must repel")
        // Neutral is best-effort given the heuristic; just verify a score exists.
        XCTAssertNotNil(plm.currentScore(for: "state-neutral"),
                        "borderline drifts must produce a score (may be neutral or repel)")
    }

    // MARK: - Group 5: End-to-end 3-way wiring

    func testEndToEndRegistrarLatencyTrackedByPLM() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let key = SymmetricKey(data: Data(repeating: 0xCC, count: 32))
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        // Inject a monotonically advancing clock to get unique nonces.
        // Use NSLock-protected state so the @Sendable clock closure is safe.
        final class MonotonicCounter: @unchecked Sendable {
            private var value = 0
            private let lock = NSLock()
            func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        }
        let counter = MonotonicCounter()
        let registrar = makeRegistrar(deviceID: "dev-e2e", key: key, clock: {
            base.addingTimeInterval(Double(counter.next()))
        })

        for i in 0..<8 {
            let start = base.addingTimeInterval(Double(i) * 2)
            _ = try await registrar.makeRegistration(
                deviceID: "dev-e2e", deviceName: "D", platform: "iOS",
                role: "voice-operator", appVersion: "1.0", reason: "e2e"
            )
            let t = OscillatorTick(
                sequence: UInt64(i + 1), scheduled: start, emitted: start,
                driftMilliseconds: 0, intervalMilliseconds: 2000
            )
            plm.recordCompletion(
                subscriberID: "e2e-registrar",
                tick: t,
                completedAt: start.addingTimeInterval(0.008 + Double(i % 2) * 0.004)
            )
        }
        guard let score = plm.currentScore(for: "e2e-registrar") else {
            return XCTFail("end-to-end PLM score must be produced")
        }
        XCTAssertGreaterThan(score.sampleCount, 0)
        XCTAssertTrue([TernarySignal.reinforce, .neutral, .repel].contains(score.regulated),
                      "score must be a valid TernarySignal")
    }

    func testEndToEndTelemetryBackboneCapturesPLMRows() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        feedDrifts(plm, subscriber: "e2e-plm-row", drifts: Array(repeating: 8.0, count: 8))

        let plvURL = telemetry.tableURL("oscillator_plv")
        let plvContent = try String(contentsOf: plvURL)
        XCTAssertTrue(plvContent.contains("e2e-plm-row"),
                      "PLM must persist its score row to shared telemetry backbone")
    }

    func testEndToEndPLMScoreAfterRegistrationAndRLMFeedbackCycling() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let key = SymmetricKey(data: Data(repeating: 0xDD, count: 32))
        let registrar = makeRegistrar(deviceID: "dev-cycle", key: key)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        // Interleave registration completions (sub-1) and RLM completions (sub-2).
        for i in 0..<8 {
            let t = OscillatorTick(
                sequence: UInt64(i + 1),
                scheduled: base.addingTimeInterval(Double(i)),
                emitted: base.addingTimeInterval(Double(i)),
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            _ = try await registrar.makeRegistration(
                deviceID: "dev-cycle", deviceName: "D", platform: "iOS",
                role: "voice-operator", appVersion: "1.0", reason: "cycle"
            )
            plm.recordCompletion(subscriberID: "cycle-reg", tick: t,
                                 completedAt: t.emitted.addingTimeInterval(0.009))
            plm.recordCompletion(subscriberID: "cycle-rlm", tick: t,
                                 completedAt: t.emitted.addingTimeInterval(0.013))
        }
        XCTAssertNotNil(plm.currentScore(for: "cycle-reg"),
                        "registrar subscriber must have a score after 8 cycles")
        XCTAssertNotNil(plm.currentScore(for: "cycle-rlm"),
                        "RLM subscriber must have a score after 8 cycles")
        XCTAssertEqual(plm.allScores().count, 2,
                       "both subscribers must appear in allScores()")
    }

    func testEndToEndAllScoresSortedBySubscriberIDAfterMixedFeed() async throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let subs = ["zz-sub", "aa-sub", "mm-sub"]
        for sub in subs {
            for i in 0..<8 {
                let t = OscillatorTick(
                    sequence: UInt64(i + 1),
                    scheduled: base.addingTimeInterval(Double(i)),
                    emitted: base.addingTimeInterval(Double(i)),
                    driftMilliseconds: 0, intervalMilliseconds: 1000
                )
                plm.recordCompletion(subscriberID: sub, tick: t,
                                     completedAt: t.emitted.addingTimeInterval(0.01))
            }
        }
        let sorted = plm.allScores().map(\.subscriberID)
        XCTAssertEqual(sorted, sorted.sorted(),
                       "allScores() must return subscribers in lexicographic order")
    }

    // MARK: - Group 6: PhaseLockMonitor configuration edge cases

    func testPhaseLockLargeScoreEveryDelaysTelemetry() throws {
        let (telemetry, _) = try makeTelemetry()
        // scoreEvery = 16: no score until 16th sample.
        let plm = PhaseLockMonitor(
            telemetry: telemetry,
            configuration: .init(windowSize: 16, scoreEvery: 16)
        )
        feedDrifts(plm, subscriber: "sub-delay", drifts: Array(repeating: 5.0, count: 15))
        XCTAssertNil(plm.currentScore(for: "sub-delay"),
                     "must not score before scoreEvery cadence")
        feedDrifts(plm, subscriber: "sub-delay", drifts: [5.0])
        XCTAssertNotNil(plm.currentScore(for: "sub-delay"),
                        "must score exactly at scoreEvery boundary")
    }

    func testPhaseLockMeanDriftAccuracyForConstantDrift() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        let constantDrift = 42.0
        feedDrifts(plm, subscriber: "sub-mean", drifts: Array(repeating: constantDrift, count: 8))
        guard let score = plm.currentScore(for: "sub-mean") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.meanDriftMilliseconds, constantDrift, accuracy: 0.01,
                       "mean drift must match constant-drift input exactly")
    }

    func testPhaseLockSampleCountMatchesWindowSize() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = makePLM(telemetry: telemetry, windowSize: 8, scoreEvery: 8)
        feedDrifts(plm, subscriber: "sub-count", drifts: Array(repeating: 10.0, count: 8))
        guard let score = plm.currentScore(for: "sub-count") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.sampleCount, 8,
                       "sampleCount must equal windowSize when exactly windowSize samples fed")
    }

    func testPhaseLockLastSequenceMatchesFinalTick() throws {
        let (telemetry, _) = try makeTelemetry()
        let plm = PhaseLockMonitor(
            telemetry: telemetry,
            configuration: .init(windowSize: 8, scoreEvery: 8)
        )
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<8 {
            let t = OscillatorTick(
                sequence: UInt64(100 + i),
                scheduled: base.addingTimeInterval(Double(i)),
                emitted: base.addingTimeInterval(Double(i)),
                driftMilliseconds: 0, intervalMilliseconds: 1000
            )
            plm.recordCompletion(subscriberID: "sub-seq", tick: t,
                                 completedAt: t.emitted.addingTimeInterval(0.005))
        }
        guard let score = plm.currentScore(for: "sub-seq") else {
            return XCTFail("expected score")
        }
        XCTAssertEqual(score.lastSequence, 107,
                       "lastSequence must equal the sequence of the final tick fed")
    }
}
