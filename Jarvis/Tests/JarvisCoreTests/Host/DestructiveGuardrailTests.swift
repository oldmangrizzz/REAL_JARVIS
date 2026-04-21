import XCTest
@testable import JarvisCore

// MARK: - MK2-EPIC-02: Destructive command guardrail tests

final class DestructiveGuardrailTests: XCTestCase {

    private var executor: DisplayCommandExecutor!
    private var registry: CapabilityRegistry!
    private var telemetry: TelemetryStore!

    override func setUp() async throws {
        let paths = try makeTestWorkspace()
        let runtime = try JarvisRuntime(paths: paths)
        registry = CapabilityRegistry(displays: [], accessories: [])
        telemetry = runtime.telemetry
        let controlPlane = runtime.controlPlane
        executor = DisplayCommandExecutor(registry: registry, controlPlane: controlPlane, telemetry: telemetry)
    }

    private var authorization: CommandAuthorization {
        CommandAuthorization(
            authority: .tunnelClient,
            allowedDisplays: [],
            allowedAccessories: [],
            allowedActions: Set(JarvisRemoteAction.allCases.map { $0.rawValue })
        )
    }

    // MARK: - 1. Destructive without confirm hash → rejected

    func testDestructiveActionWithoutConfirmHashIsRejected() async throws {
        let command = JarvisRemoteCommand(action: .displayWipe)
        await XCTAssertThrowsErrorAsync(
            try await executor.execute(tunnelCommand: command, confirmHash: nil, authorization: authorization)
        ) { error in
            guard let te = error as? TunnelError else {
                XCTFail("Expected TunnelError, got \(error)")
                return
            }
            XCTAssertTrue(
                te == .destructiveRequiresConfirm,
                "Expected .destructiveRequiresConfirm, got \(te)"
            )
        }
    }

    // MARK: - 2. Destructive with correct confirm hash → allowed

    func testDestructiveActionWithCorrectHashIsAllowed() async throws {
        let action = JarvisRemoteAction.memoryPurge
        let correctHash = action.canonicalHashHex
        let command = JarvisRemoteCommand(action: action)
        let result = try await executor.execute(
            tunnelCommand: command,
            confirmHash: correctHash,
            authorization: authorization
        )
        XCTAssertTrue(result.success, "Destructive action with correct hash must succeed.")
    }

    // MARK: - 3. Destructive with wrong hash → rejected

    func testDestructiveActionWithWrongHashIsRejected() async throws {
        let command = JarvisRemoteCommand(action: .voiceGateRevoke)
        let wrongHash = "deadbeef" + String(repeating: "0", count: 56)  // wrong 64-char hex
        await XCTAssertThrowsErrorAsync(
            try await executor.execute(tunnelCommand: command, confirmHash: wrongHash, authorization: authorization)
        ) { error in
            guard let te = error as? TunnelError else {
                XCTFail("Expected TunnelError, got \(error)")
                return
            }
            XCTAssertTrue(
                te == .confirmHashMismatch,
                "Expected .confirmHashMismatch, got \(te)"
            )
        }
    }

    // MARK: - 4. Non-destructive action unaffected by missing hash

    func testNonDestructiveActionAllowedWithoutConfirmHash() async throws {
        let command = JarvisRemoteCommand(action: .ping)
        XCTAssertFalse(JarvisRemoteAction.ping.isDestructive, "ping must not be destructive")
        let result = try await executor.execute(
            tunnelCommand: command,
            confirmHash: nil,
            authorization: authorization
        )
        XCTAssertTrue(result.success, "Non-destructive action must not require confirm hash.")
    }

    // MARK: - 5. isDestructive computed property correctness

    func testIsDestructiveReturnsTrueForAllDestructiveActions() {
        let destructive: [JarvisRemoteAction] = [
            .displayWipe, .capabilityDelete, .voiceGateRevoke, .memoryPurge, .soulAnchorRotate
        ]
        for action in destructive {
            XCTAssertTrue(action.isDestructive, "\(action.rawValue) must be destructive")
        }
    }

    func testIsDestructiveReturnsFalseForNonDestructiveActions() {
        let safe: [JarvisRemoteAction] = [.status, .ping, .listSkills, .homeKitStatus, .runSkill]
        for action in safe {
            XCTAssertFalse(action.isDestructive, "\(action.rawValue) must not be destructive")
        }
    }

    // MARK: - 6. canonicalHashHex is deterministic and action-unique

    func testCanonicalHashHexIsDeterministic() {
        let h1 = JarvisRemoteAction.displayWipe.canonicalHashHex
        let h2 = JarvisRemoteAction.displayWipe.canonicalHashHex
        XCTAssertEqual(h1, h2, "canonicalHashHex must be deterministic")
    }

    func testCanonicalHashHexDiffersAcrossDestructiveActions() {
        let hashes = [
            JarvisRemoteAction.displayWipe.canonicalHashHex,
            JarvisRemoteAction.capabilityDelete.canonicalHashHex,
            JarvisRemoteAction.voiceGateRevoke.canonicalHashHex,
            JarvisRemoteAction.memoryPurge.canonicalHashHex,
            JarvisRemoteAction.soulAnchorRotate.canonicalHashHex
        ]
        let unique = Set(hashes)
        XCTAssertEqual(unique.count, hashes.count, "Each destructive action must have a unique canonical hash")
    }

    // MARK: - 7. DestructiveNonceTracker: replay defense

    func testNonceTrackerRejectsReplay() async {
        let tracker = DestructiveNonceTracker()
        let nonce = "unique-nonce-\(UUID().uuidString)"
        let first = await tracker.insertAndValidate(nonce)
        let second = await tracker.insertAndValidate(nonce)
        XCTAssertTrue(first, "First use of nonce must be accepted")
        XCTAssertFalse(second, "Replay of same nonce must be rejected")
    }

    func testNonceTrackerAcceptsDifferentNonces() async {
        let tracker = DestructiveNonceTracker()
        let a = await tracker.insertAndValidate("nonce-A-\(UUID().uuidString)")
        let b = await tracker.insertAndValidate("nonce-B-\(UUID().uuidString)")
        XCTAssertTrue(a, "First nonce must be accepted")
        XCTAssertTrue(b, "Different nonce must be accepted")
    }

    func testNonceTrackerRejectsEmptyNonce() async {
        let tracker = DestructiveNonceTracker()
        let result = await tracker.insertAndValidate("")
        XCTAssertFalse(result, "Empty nonce must be rejected")
    }
}

// MARK: - Async XCTAssertThrowsError helper

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw, but it didn't. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
