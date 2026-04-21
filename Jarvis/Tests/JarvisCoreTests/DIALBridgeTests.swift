import XCTest
@testable import JarvisCore

final class DIALBridgeTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeDisplay(address: String?) -> DisplayEndpoint {
        DisplayEndpoint(
            id: "firetv-upstairs",
            displayName: "Fire TV Upstairs",
            aliases: ["firetv"],
            type: .tv,
            transport: .dial,
            address: address,
            capabilities: ["display-dashboard"],
            room: "upstairs",
            authority: .standard
        )
    }

    func testLaunchDefaultsToYouTubeForDashboard() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "192.168.7.50")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.7.50:8008/apps/YouTube")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let bridge = DIALBridge(session: session)
        let result = try await bridge.launchApp(display: display, action: "display-dashboard", parameters: [:])
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["app"], "YouTube")
        XCTAssertEqual(result.details["httpStatus"], "201")
    }

    func testLaunchHonorsContentParameterAndPort() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "192.168.7.50:8060")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.7.50:8060/apps/Netflix")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let bridge = DIALBridge(session: session)
        _ = try await bridge.launchApp(display: display, action: "display-content", parameters: ["content": "Netflix"])
    }

    func testLaunchAccepts206PartialContent() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "10.0.0.5")
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let bridge = DIALBridge(session: session)
        let result = try await bridge.launchApp(display: display, action: "display-dashboard", parameters: [:])
        XCTAssertTrue(result.success)
    }

    func testLaunchThrowsOn404() async {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "10.0.0.5")
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("not found".utf8))
        }
        let bridge = DIALBridge(session: session)
        do {
            _ = try await bridge.launchApp(display: display, action: "display-dashboard", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("404"))
        }
    }

    func testLaunchThrowsWithoutAddress() async {
        let bridge = DIALBridge(session: MockURLProtocol.makeSession())
        let display = makeDisplay(address: nil)
        do {
            _ = try await bridge.launchApp(display: display, action: "display-dashboard", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("no address"))
        }
    }
}
