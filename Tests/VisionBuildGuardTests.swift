#if canImport(RealityKit) && os(visionOS)
import XCTest
@testable import VisionOSClient

final class VisionBuildGuardTests: XCTestCase {
    func testCompile() {
        // This test exists solely to verify that the VisionOS client target
        // compiles successfully when the RealityKit SDK and visionOS platform
        // are available. No runtime assertions are required.
    }
}
#endif