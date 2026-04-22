import XCTest
@testable import JarvisCore

/// AMBIENT-002-FIX-01 §3.7 ambient gateway behavioral + telemetry suite.
///
/// The gateway protocol (`AmbientAudioGateway`) is intentionally abstract —
/// it exposes only `state`, `observe(handler:)`, and `cancel(token:)`. No
/// concrete production implementation has shipped yet. These tests exercise:
///   - The observer contract against a Sendable-clean fake gateway.
///   - The §3.6 `TelemetryStore` ambient helpers
///     (`logAmbientGatewayTransition`, `logAmbientGatewayLatencySLAMiss`)
///     including principal binding, endpoint-nil handling, and hash-chain
///     integrity via `verifyChain(table: "ambient_audio_gateway")`.
///
/// SPEC DEVIATION: spec §6.6 refers to a `.rowCount` field on the chain
/// report; the actual `TelemetryChainReport` type exposes `.totalRows`.
/// Assertions below use the real field name; the response doc calls out
/// the spec typo explicitly.
final class AmbientAudioGatewayTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() throws -> (TelemetryStore, WorkspacePaths) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ambient-gateway-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let paths = WorkspacePaths(root: tmp)
        let store = try TelemetryStore(paths: paths)
        return (store, paths)
    }

    private func readLines(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            }
    }

    private func makeEndpoint(id: String = "watch-primary",
                              name: String = "Apple Watch Ultra") -> AmbientEndpoint {
        AmbientEndpoint(id: id, displayName: name, supportsHandsFreeProfile: true)
    }

    // MARK: - Observer contract (fake gateway)

    func testFakeGatewayObserverReceivesInitialAndUpdatedState() {
        let gw = FakeAmbientAudioGateway(initial: .init(route: .unpaired,
                                                        endpoint: nil,
                                                        wristAttached: false,
                                                        tunnelReachable: false,
                                                        updatedAt: Date()))
        let box = ObservedBox()
        _ = gw.observe { state in box.append(state) }
        // handler fired once on subscription with current state
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box.last?.route, .unpaired)

        let ep = makeEndpoint()
        gw.drive(.init(route: .watchHosted,
                       endpoint: ep,
                       wristAttached: true,
                       tunnelReachable: true,
                       updatedAt: Date()))
        XCTAssertEqual(box.count, 2)
        XCTAssertEqual(box.last?.route, .watchHosted)
        XCTAssertEqual(box.last?.endpoint?.id, "watch-primary")
    }

    func testFakeGatewayCancelledObserverReceivesNoFurtherUpdates() {
        let gw = FakeAmbientAudioGateway(initial: .init(route: .unpaired,
                                                        endpoint: nil,
                                                        wristAttached: false,
                                                        tunnelReachable: false,
                                                        updatedAt: Date()))
        let box = ObservedBox()
        let token = gw.observe { state in box.append(state) }
        XCTAssertEqual(box.count, 1)
        gw.cancel(token)

        gw.drive(.init(route: .watchHosted,
                       endpoint: makeEndpoint(),
                       wristAttached: true,
                       tunnelReachable: true,
                       updatedAt: Date()))
        XCTAssertEqual(box.count, 1, "cancelled observer must not receive further updates")
    }

    func testFakeGatewayTwoObserversBothNotifiedAndIndependentlyCancellable() {
        let gw = FakeAmbientAudioGateway(initial: .init(route: .unpaired,
                                                        endpoint: nil,
                                                        wristAttached: false,
                                                        tunnelReachable: false,
                                                        updatedAt: Date()))
        let a = ObservedBox()
        let b = ObservedBox()
        let tokenA = gw.observe { state in a.append(state) }
        _ = gw.observe { state in b.append(state) }
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)

        gw.drive(.init(route: .watchHosted,
                       endpoint: makeEndpoint(),
                       wristAttached: true,
                       tunnelReachable: true,
                       updatedAt: Date()))
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(b.count, 2)

        gw.cancel(tokenA)
        gw.drive(.init(route: .offWrist,
                       endpoint: makeEndpoint(),
                       wristAttached: false,
                       tunnelReachable: true,
                       updatedAt: Date()))
        XCTAssertEqual(a.count, 2, "cancelled observer frozen at pre-cancel count")
        XCTAssertEqual(b.count, 3, "surviving observer keeps receiving")
    }

    // MARK: - Telemetry: single-transition shape

    func testLogTransitionWritesOneRowToAmbientTable() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["hostNode"] as? String, "alpha")
        XCTAssertEqual(rows[0]["eventType"] as? String, "transition")
        XCTAssertEqual(rows[0]["fromRoute"] as? String, "unpaired")
        XCTAssertEqual(rows[0]["toRoute"] as? String, "watchHosted")
        XCTAssertEqual(rows[0]["endpointID"] as? String, "watch-primary")
        XCTAssertEqual(rows[0]["tunnelReachable"] as? Bool, true)
        XCTAssertEqual(rows[0]["wristAttached"] as? Bool, true)
    }

    func testLogTransitionBindsOperatorPrincipal() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["principal"] as? String, "grizz")
    }

    func testLogTransitionBindsResponderPrincipalForWatchTier() throws {
        // Signed watch responder session — the watch-tier trust path from
        // JarvisHostTunnelServer authorizedSources + privilegedRoles.
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .phoneFallback,
            endpointID: "watch-primary",
            tunnelReachable: false,
            wristAttached: true,
            principal: .responder(role: .emt)
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["principal"] as? String, "responder:emt")
    }

    func testLogTransitionBindsCompanionPrincipal() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .degraded,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .companion(memberID: "melissa")
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["principal"] as? String, "companion:melissa")
    }

    func testLogTransitionOmitsEndpointIDWhenNil() throws {
        // Unpaired route has no endpoint bound — endpointID must be absent
        // in the row body (not written as null string).
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .unpaired,
            endpointID: nil,
            tunnelReachable: false,
            wristAttached: false,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertNil(rows[0]["endpointID"], "nil endpointID must not be serialized")
        XCTAssertEqual(rows[0]["toRoute"] as? String, "unpaired")
    }

    func testLogTransitionIncludesEndpointIDWhenProvided() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "beta",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "airpods-pro",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["endpointID"] as? String, "airpods-pro")
    }

    func testLogTransitionAcceptsExplicitTimestamp() throws {
        let (store, _) = try makeStore()
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier,
            at: pinned
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["timestamp"] as? String,
                       ISO8601DateFormatter().string(from: pinned))
    }

    // MARK: - Telemetry: hash chain across multiple transitions

    func testTenTransitionsWriteTenChainedRowsWithIntactChain() throws {
        let (store, _) = try makeStore()
        let sequence: [(AmbientGatewayRoute, AmbientGatewayRoute, Bool, Bool)] = [
            (.unpaired, .watchHosted, true, true),
            (.watchHosted, .offWrist, false, true),
            (.offWrist, .watchHosted, true, true),
            (.watchHosted, .phoneFallback, true, false),
            (.phoneFallback, .watchHosted, true, true),
            (.watchHosted, .degraded, true, true),
            (.degraded, .watchHosted, true, true),
            (.watchHosted, .cellularTether, true, false),
            (.cellularTether, .watchHosted, true, true),
            (.watchHosted, .unpaired, false, false)
        ]
        for (from, to, tunnel, wrist) in sequence {
            try store.logAmbientGatewayTransition(
                hostNode: "alpha",
                fromRoute: from,
                toRoute: to,
                endpointID: "watch-primary",
                tunnelReachable: tunnel,
                wristAttached: wrist,
                principal: .operatorTier
            )
        }
        let report = try store.verifyChain(table: "ambient_audio_gateway")
        XCTAssertEqual(report.totalRows, 10, "ten transitions → ten rows")
        XCTAssertEqual(report.hashedRows, 10, "every row carries a rowHash")
        XCTAssertEqual(report.legacyRows, 0)
        XCTAssertNil(report.brokenAt, "chain must be intact across all ten transitions")
    }

    func testOffWristFreezeTransitionLogsAndChainsCleanly() throws {
        // Off-wrist is the security-critical freeze state — watchHosted →
        // offWrist must be recorded with wristAttached=false and keep the
        // chain intact even if the principal changes across the boundary.
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .offWrist,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: false,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1]["toRoute"] as? String, "offWrist")
        XCTAssertEqual(rows[1]["wristAttached"] as? Bool, false)
        let report = try store.verifyChain(table: "ambient_audio_gateway")
        XCTAssertEqual(report.totalRows, 2)
        XCTAssertNil(report.brokenAt)
    }

    func testPrevRowHashThreadsAcrossAmbientTransitions() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .degraded,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows.count, 2)
        let firstHash = rows[0]["rowHash"] as? String
        XCTAssertNotNil(firstHash)
        XCTAssertEqual(rows[1]["prevRowHash"] as? String, firstHash,
                       "row 2 prevRowHash must reference row 1 rowHash")
    }

    // MARK: - Telemetry: latency SLA miss

    func testLogLatencySLAMissWritesDiscriminatedRow() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayLatencySLAMiss(
            hostNode: "alpha",
            hopName: "watch→phone-fallback",
            measuredMs: 820.0,
            ceilingMs: 500.0,
            principal: .operatorTier
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["eventType"] as? String, "latencySLAMiss")
        XCTAssertEqual(rows[0]["hopName"] as? String, "watch→phone-fallback")
        XCTAssertEqual(rows[0]["measuredMs"] as? Double, 820.0)
        XCTAssertEqual(rows[0]["ceilingMs"] as? Double, 500.0)
        XCTAssertEqual(rows[0]["principal"] as? String, "grizz")
    }

    func testLogLatencySLAMissInterleavesWithTransitionsInSameChain() throws {
        // Both helpers target `ambient_audio_gateway`; the chain must stay
        // intact across mixed event types distinguished by `eventType`.
        let (store, _) = try makeStore()
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .unpaired,
            toRoute: .watchHosted,
            endpointID: "watch-primary",
            tunnelReachable: true,
            wristAttached: true,
            principal: .operatorTier
        )
        try store.logAmbientGatewayLatencySLAMiss(
            hostNode: "alpha",
            hopName: "watch-hosted",
            measuredMs: 640.0,
            ceilingMs: 500.0,
            principal: .operatorTier
        )
        try store.logAmbientGatewayTransition(
            hostNode: "alpha",
            fromRoute: .watchHosted,
            toRoute: .phoneFallback,
            endpointID: "watch-primary",
            tunnelReachable: false,
            wristAttached: true,
            principal: .operatorTier
        )
        let report = try store.verifyChain(table: "ambient_audio_gateway")
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertEqual(report.hashedRows, 3)
        XCTAssertNil(report.brokenAt)

        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["eventType"] as? String, "transition")
        XCTAssertEqual(rows[1]["eventType"] as? String, "latencySLAMiss")
        XCTAssertEqual(rows[2]["eventType"] as? String, "transition")
    }

    func testLogLatencySLAMissBindsResponderWatchPrincipal() throws {
        let (store, _) = try makeStore()
        try store.logAmbientGatewayLatencySLAMiss(
            hostNode: "alpha",
            hopName: "watch-to-host-auth",
            measuredMs: 410.0,
            ceilingMs: 250.0,
            principal: .responder(role: .emt)
        )
        let rows = try readLines(store.tableURL("ambient_audio_gateway"))
        XCTAssertEqual(rows[0]["principal"] as? String, "responder:emt")
    }

    // MARK: - Telemetry: gateway observer wired to store

    func testFakeGatewayTransitionsDrivenThroughObserverAreFullyLogged() throws {
        // Canon pattern: subscribe, mutate state, log the diff in the
        // observer, verify chain integrity. Guarantees the observer→store
        // wiring remains testable without a concrete gateway impl.
        let (store, _) = try makeStore()
        let gw = FakeAmbientAudioGateway(initial: .init(route: .unpaired,
                                                        endpoint: nil,
                                                        wristAttached: false,
                                                        tunnelReachable: false,
                                                        updatedAt: Date()))
        let loggerBox = TransitionLogger(store: store, hostNode: "alpha")
        _ = gw.observe { state in loggerBox.record(state) }

        gw.drive(.init(route: .watchHosted,
                       endpoint: makeEndpoint(),
                       wristAttached: true,
                       tunnelReachable: true,
                       updatedAt: Date()))
        gw.drive(.init(route: .offWrist,
                       endpoint: makeEndpoint(),
                       wristAttached: false,
                       tunnelReachable: true,
                       updatedAt: Date()))
        gw.drive(.init(route: .watchHosted,
                       endpoint: makeEndpoint(),
                       wristAttached: true,
                       tunnelReachable: true,
                       updatedAt: Date()))

        // Three driven updates → three transition rows (initial subscription
        // delivery is priming only and does not log).
        let report = try store.verifyChain(table: "ambient_audio_gateway")
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertNil(report.brokenAt)
    }
}

// MARK: - Test doubles

/// Sendable-clean fake conforming to `AmbientAudioGateway`. Drives
/// observer callbacks synchronously on `drive(_:)` — deterministic for
/// chain-ordered assertions.
final class FakeAmbientAudioGateway: AmbientAudioGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: AmbientGatewayState
    private var handlers: [AmbientObserverToken: @Sendable (AmbientGatewayState) -> Void] = [:]

    init(initial: AmbientGatewayState) {
        self._state = initial
    }

    var state: AmbientGatewayState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken {
        lock.lock()
        let token = AmbientObserverToken()
        handlers[token] = handler
        let snapshot = _state
        lock.unlock()
        handler(snapshot)
        return token
    }

    func cancel(_ token: AmbientObserverToken) {
        lock.lock(); defer { lock.unlock() }
        handlers.removeValue(forKey: token)
    }

    /// Test-only helper — advance state and notify every active observer.
    func drive(_ next: AmbientGatewayState) {
        lock.lock()
        _state = next
        let snapshot = handlers.values
        lock.unlock()
        for handler in snapshot { handler(next) }
    }
}

/// Sendable-clean collector for observer state snapshots.
final class ObservedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AmbientGatewayState] = []

    func append(_ state: AmbientGatewayState) {
        lock.lock(); defer { lock.unlock() }
        states.append(state)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return states.count
    }

    var last: AmbientGatewayState? {
        lock.lock(); defer { lock.unlock() }
        return states.last
    }
}

/// Observer-side logger that emits ambient transitions into the hash chain
/// as the gateway's route changes. Treats the priming call (initial state
/// on subscription) as a no-op to avoid spurious rows.
final class TransitionLogger: @unchecked Sendable {
    private let store: TelemetryStore
    private let hostNode: String
    private let lock = NSLock()
    private var previous: AmbientGatewayState?

    init(store: TelemetryStore, hostNode: String) {
        self.store = store
        self.hostNode = hostNode
    }

    func record(_ next: AmbientGatewayState) {
        lock.lock()
        let prev = previous
        previous = next
        lock.unlock()
        guard let prev else { return }
        guard prev.route != next.route else { return }
        try? store.logAmbientGatewayTransition(
            hostNode: hostNode,
            fromRoute: prev.route,
            toRoute: next.route,
            endpointID: next.endpoint?.id,
            tunnelReachable: next.tunnelReachable,
            wristAttached: next.wristAttached,
            principal: .operatorTier
        )
    }
}
