import XCTest
@testable import JarvisCore

final class TunnelIdentityStoreTests: XCTestCase {

    func testWatchPlatformRegistrationRoundTrip() throws {
        // Arrange: create a fresh store and a watch platform identity
        let store = TunnelIdentityStore()
        let testID = UUID()
        let testToken = "watch-test-token"
        let identity = TunnelIdentity(id: testID, platform: .watch, token: testToken)

        // Act: register the identity and then retrieve it
        try store.register(identity: identity)
        let retrieved = try store.identity(for: testID)

        // Assert: the retrieved identity matches the original
        XCTAssertEqual(retrieved, identity, "The retrieved identity should match the one that was registered for the watch platform.")
    }
}