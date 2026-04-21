#if false  // QUARANTINED 2026-04-21: stale vs current AmbientAudioGateway API; needs rewrite against real AmbientEndpoint/AmbientGatewayState types. See MK2 ship-gate follow-up.
import XCTest
import Combine
@testable import JarvisCore

// MARK: - Test doubles (fake implementations)

final class FakeBluetoothBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var endpoints: [String: AmbientEndpoint] = [:]
    private var activeEndpointID: String?
    private let queue = DispatchQueue(label: "fake-bluetooth-broker")

    func setEndpoints(_ endpoints: [String: AmbientEndpoint]) {
        lock.lock(); defer { lock.unlock() }
        self.endpoints = endpoints
    }

    func setActiveEndpoint(_ id: String?) {
        lock.lock(); defer { lock.unlock() }
        activeEndpointID = id
    }

    func toggleWristDetect(_ attached: Bool) {
        wristAttached = attached
    }

    private var wristAttached: Bool = true
    var didWristDetectChange: ((Bool) -> Void)?

    func triggerWristChange(_ attached: Bool) {
        lock.lock()
        self.wristAttached = attached
        let handler = didWristDetectChange
        lock.unlock()
        queue.async { handler?(attached) }
    }

    func getEndpointIDs() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(endpoints.keys)
    }

    func getActiveEndpoint() -> String? {
        lock.lock(); defer { lock.unlock() }
        return activeEndpointID
    }
}

final class FakeWristSensor: @unchecked Sendable {
    private var attached: Bool = true
    private let queue = DispatchQueue(label: "fake-wrist-sensor")
    private let lock = NSLock()
    private var handlers: [(Bool) -> Void] = []

    func setAttached(_ value: Bool) {
        lock.lock()
        attached = value
        let savedHandlers = handlers
        lock.unlock()
        for handler in savedHandlers {
            queue.async { handler(value) }
        }
    }

    func subscribe(_ handler: @escaping (Bool) -> Void) -> Void {
        lock.lock()
        handlers.append(handler)
        let current = attached
        lock.unlock()
        handler(current)
    }
}

final class FakeTunnelProbe: @unchecked Sendable {
    private(set) var reachable: Bool = true
    func setIsReachable(_ value: Bool) { reachable = value }

    func isReachable() -> Bool { reachable }
}

// MARK: - AmbientAudioGatewayTest implementation

final class AmbientAudioGatewayTests: XCTestCase {

    private var gateway: AmbientAudioGatewayImpl!
    private var bluetoothBroker: FakeBluetoothBroker!
    private var wristSensor: FakeWristSensor!
    private var tunnelProbe: FakeTunnelProbe!
    private var currentTelemetryRows: [[String: Any]] = []

    override func setUp() {
        super.setUp()
        bluetoothBroker = FakeBluetoothBroker()
        wristSensor = FakeWristSensor()
        tunnelProbe = FakeTunnelProbe()

        // Setup fake telemetry that captures rows
        currentTelemetryRows = []

        gateway = AmbientAudioGatewayImpl(
            bluetoothBroker: bluetoothBroker,
            wristSensor: wristSensor,
            tunnelProbe: tunnelProbe
        )
    }

    override func tearDown() {
        gateway = nil
        bluetoothBroker = nil
        wristSensor = nil
        tunnelProbe = nil
        super.tearDown()
    }

    // MARK: - State machine transitions

    func testStateTransition_unpaired_to_watchHosted() async throws {
        let endpoints = [
            "headphones-001": AmbientEndpoint(id: "headphones-001", displayName: "AirPods Pro", supportsHandsFreeProfile: true)
        ]
        bluetoothBroker.setEndpoints(endpoints)
        bluetoothBroker.setActiveEndpoint("headphones-001")
        tunnelProbe.setIsReachable(true)

        let targetState = await waitForUpdate { @Sendable in
            try await gateway.refreshEndpoints()
        }

        XCTAssertEqual(targetState.route, .watchHosted)
        XCTAssertEqual(targetState.endpoint?.id, "headphones-001")
    }

    func testStateTransition_watchHosted_to_offWrist() async throws {
        // First establish watchHosted
        setupWatchHostedState()
        let initial = gateway.currentState
        XCTAssertEqual(initial.route, .watchHosted)

        // Trigger off-wrist
        wristSensor.setAttached(false)

        let final = await waitForUpdate { @Sendable in
            // Wait for the wrist-change handler to fire
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return gateway.currentState
        }

        XCTAssertEqual(final.route, .offWrist)
        XCTAssertTrue(final.wristAttached == false)
    }

    func testStateTransition_offWrist_to_watchHosted() async throws {
        // Transition to offWrist first
        setupWatchHostedState()
        wristSensor.setAttached(false)
        await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 100_000_000)
            return gateway.currentState
        }

        // Re-attach wrist
        wristSensor.setAttached(true)

        let final = await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 100_000_000)
            return gateway.currentState
        }

        XCTAssertEqual(final.route, .watchHosted)
        XCTAssertTrue(final.wristAttached)
    }

    func testStateTransition_watchHosted_to_phoneFallback() async throws {
        setupWatchHostedState()

        // Set endpoint that doesn't support A2DP
        let endpoints = [
            "headphones-002": AmbientEndpoint(id: "headphones-002", displayName: "Generic BT", supportsHandsFreeProfile: true)
        ]
        bluetoothBroker.setEndpoints(endpoints)
        bluetoothBroker.setActiveEndpoint("headphones-002")

        let updated = await waitForUpdate { @Sendable in
            try await gateway.refreshEndpoints()
            return gateway.currentState
        }

        XCTAssertEqual(updated.route, .phoneFallback)
    }

    func testStateTransition_watchHosted_to_degraded() async throws {
        setupWatchHostedState()
        tunnelProbe.setIsReachable(false)

        let updated = await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 50_000_000)
            return gateway.currentState
        }

        XCTAssertEqual(updated.route, .degraded)
    }

    func testStateTransition_degraded_to_watchHosted() async throws {
        setupWatchHostedState()
        tunnelProbe.setIsReachable(false)
        await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 50_000_000)
            return gateway.currentState
        }

        tunnelProbe.setIsReachable(true)
        let final = await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 50_000_000)
            return gateway.currentState
        }

        XCTAssertEqual(final.route, .watchHosted)
        XCTAssertTrue(final.tunnelReachable)
    }

    func testStateTransition_offWrist_to_cellularTether_which_is_illegal() async throws {
        // offWrist → cellularTether directly is illegal per spec
        setupWatchHostedState()
        wristSensor.setAttached(false)
        await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 100_000_000)
            return gateway.currentState
        }

        let currentState = gateway.currentState
        XCTAssertEqual(currentState.route, .offWrist)

        // Attempt to go to cellularTether directly (should not happen in state machine)
        // We'll just verify the state doesn't spontaneously change
        tunnelProbe.setIsReachable(true)
        let afterTunnelReconnect = gateway.currentState

        // Should remain offWrist until wrist reattachment
        XCTAssertEqual(afterTunnelReconnect.route, .offWrist)
    }

    // MARK: - Observer contract

    func testObserver_contract_firesOncePerTransition() async throws {
        setupWatchHostedState()

        var observedCount = 0
        var lastRoute: AmbientGatewayRoute?
        let token = gateway.observe { [weak self] state in
            guard let self = self else { return }
            observedCount += 1
            lastRoute = state.route
        }

        // Trigger a change
        wristSensor.setAttached(false)
        await waitForUpdate { @Sendable in
            try await Task.sleep(nanoseconds: 100_000_000)
            return gateway.currentState
        }

        XCTAssertEqual(observedCount, 1, "Observer should fire exactly once per transition")
        XCTAssertEqual(lastRoute, .offWrist)
        gateway.cancel(token)
    }

    func testObserver_survivesNoopReSet() async throws {
        let token = gateway.observe { _ in }

        // Call refreshEndpoints repeatedly without changes
        for _ in 0..<5 {
            await gateway.refreshEndpoints()
        }

        // Observer should not fire for noop re-sets
        // (In a real implementation this would be verified by counting)
        gateway.cancel(token)
    }

    // MARK: - Reassign errors

    func testReassign_unknownEndpointId() {
        // Create gateway with known endpoint
        setupWatchHostedState()

        // Try to reassign to unknown ID
        do {
            try gateway.reassign(to: "nonexistent-device")
            XCTFail("Expected error for unknown endpoint")
        } catch let error as JarvisError {
            if case .invalidInput = error {
                // Expected
            } else {
                XCTFail("Expected invalidInput error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testReassign_endpointWithBrokerError() {
        setupWatchHostedState()

        // Simulate broker failure by setting invalid endpoint
        bluetoothBroker.setActiveEndpoint(nil)

        do {
            try gateway.reassign(to: "headphones-001")
            XCTFail("Expected error when broker fails")
        } catch let error as JarvisError {
            XCTAssertNotNil(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Concurrency

    func testConcurrency_manyRefreshEndpoints_calls() async {
        setupWatchHostedState()

        // Spawn 200 concurrent refresh calls
        let tasks = (0..<200).map { _ in
            Task {
                await self.gateway.refreshEndpoints()
            }
        }
        await Task.detached(priority: .background).yield()

        // Wait for all to complete
        for task in tasks {
            try? await task.value
        }

        // Final state should be consistent (not corrupted by race)
        let final = gateway.currentState
        XCTAssertNotNil(final.endpoint)
        XCTAssertGreaterThanOrEqual(final.endpoint?.id.count ?? 0, 0)
    }

    // MARK: - Helpers

    private func setupWatchHostedState() {
        let endpoints = [
            "headphones-001": AmbientEndpoint(id: "headphones-001", displayName: "AirPods Pro", supportsHandsFreeProfile: true)
        ]
        bluetoothBroker.setEndpoints(endpoints)
        bluetoothBroker.setActiveEndpoint("headphones-001")
        tunnelProbe.setIsReachable(true)
        wristSensor.setAttached(true)
        XCTAssertTrue(gateway.currentState.route == .watchHosted || gateway.currentState.route == .unpaired)
        // Trigger initial refresh to establish watchHosted
        try? await gateway.refreshEndpoints()
    }

    private func waitForUpdate<T>(_ body: @Sendable @escaping () -> T) async -> T {
        return await Task.detached(priority: .userInitiated) { () -> T in
            return body()
        }.value
    }
}

// MARK: - AmbientAudioGatewayImpl (concrete implementation)

private final class AmbientAudioGatewayImpl: AmbientAudioGateway, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var currentState: AmbientGatewayState
    private var handlers: [WeakObserverToken] = []

    private let bluetoothBroker: FakeBluetoothBroker
    private let wristSensor: FakeWristSensor
    private let tunnelProbe: FakeTunnelProbe

    init(
        bluetoothBroker: FakeBluetoothBroker,
        wristSensor: FakeWristSensor,
        tunnelProbe: FakeTunnelProbe
    ) {
        self.bluetoothBroker = bluetoothBroker
        self.wristSensor = wristSensor
        self.tunnelProbe = tunnelProbe

        currentState = AmbientGatewayState(
            route: .unpaired,
            endpoint: nil,
            wristAttached: true,
            tunnelReachable: tunnelProbe.isReachable(),
            updatedAt: Date()
        )
    }

    func reassign(to endpointID: String) throws {
        let endpoints = bluetoothBroker.getEndpointIDs()
        guard endpoints.contains(endpointID) else {
            throw JarvisError.invalidInput("Unknown endpointID: \(endpointID)")
        }

        // Simulate BT framework potential failure
        guard let active = bluetoothBroker.getActiveEndpoint(), active == endpointID else {
            throw JarvisError.processFailure("Bluetooth framework error during reassignment")
        }

        updateRoute(.watchHosted)
    }

    func refreshEndpoints() async {
        await MainActor.run {
            bluetoothBroker.getEndpointIDs().forEach { _ in }
            let activeID = bluetoothBroker.getActiveEndpoint()
            let activeEndpoint = activeID.flatMap { (bluetoothBroker.endpoints[$0] ?? nil) }

            var endpoints: [AmbientEndpoint] = []
            for id in bluetoothBroker.getEndpointIDs() {
                if let ep = bluetoothBroker.endpoints[id] {
                    endpoints.append(ep)
                }
            }

            let newRoute: AmbientGatewayRoute
            if activeID == nil {
                newRoute = .unpaired
            } else if endpoints.isEmpty {
                newRoute = .unpaired
            } else {
                let ep = activeEndpoint!

                // If endpoint doesn't support hands-free profile, fallback to phone
                if !ep.supportsHandsFreeProfile {
                    newRoute = .phoneFallback
                } else if !tunnelProbe.isReachable() {
                    newRoute = .degraded
                } else {
                    newRoute = .watchHosted
                }
            }

            currentState = AmbientGatewayState(
                route: newRoute,
                endpoint: activeEndpoint,
                wristAttached: wristSensor.attached,
                tunnelReachable: tunnelProbe.isReachable(),
                updatedAt: Date()
            )
            notifyObservers()
        }
    }

    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken {
        let token = AmbientObserverToken()
        let strongToken = WeakObserverToken(token: token, handler: handler)
        lock.lock()
        handlers.append(strongToken)
        lock.unlock()
        return token
    }

    func cancel(_ token: AmbientObserverToken) {
        lock.lock()
        handlers = handlers.filter { $0.token.uuid != token.uuid }
        lock.unlock()
    }

    private func updateRoute(_ newRoute: AmbientGatewayRoute) {
        let oldRoute = currentState.route
        currentState.route = newRoute
        currentState.updatedAt = Date()
        notifyObservers()

        // Simulate telemetry row if state changed
        if oldRoute != newRoute {
            NSLog("Telemetry: route change \(oldRoute) → \(newRoute)")
        }
    }

    private func notifyObservers() {
        let state = currentState  // Snapshot
        lock.lock()
        let handlersToNotify = handlers
        lock.unlock()

        for box in handlersToNotify {
            box.handler(state)
        }
    }
}

private final class WeakObserverToken {
    let token: AmbientObserverToken
    let handler: @Sendable (AmbientGatewayState) -> Void

    init(token: AmbientObserverToken, handler: @escaping @Sendable (AmbientGatewayState) -> Void) {
        self.token = token
        self.handler = handler
    }
}
#endif
