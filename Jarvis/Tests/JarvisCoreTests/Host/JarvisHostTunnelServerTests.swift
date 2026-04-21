import XCTest
@testable import JarvisCore

final class JarvisHostTunnelServerTests: XCTestCase {
    
    func testDefaultAuthorizedSources() {
        let server = JarvisHostTunnelServer()
        XCTAssertTrue(server.authorizedSources.contains("ios"), "\"ios\" should be an authorized source")
        XCTAssertTrue(server.authorizedSources.contains("macos"), "\"macos\" should be an authorized source")
    }
    
    func testAuthorizedSourcesIncludesWatch() {
        let server = JarvisHostTunnelServer()
        XCTAssertTrue(server.authorizedSources.contains("watch"), "\"watch\" should be an authorized source")
    }
}