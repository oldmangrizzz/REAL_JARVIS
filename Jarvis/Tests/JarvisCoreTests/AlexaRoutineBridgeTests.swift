import XCTest
@testable import JarvisCore

final class AlexaRoutineBridgeTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeDisplay(address: String?) -> DisplayEndpoint {
        DisplayEndpoint(
            id: "echo-show-kitchen",
            displayName: "Echo Show Kitchen",
            aliases: ["kitchen"],
            type: .tablet,
            transport: .alexaRoutine,
            address: address,
            capabilities: ["display-camera"],
            room: "downstairs",
            authority: .standard
        )
    }

    func testTriggerPostsJSONToWebhook() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "https://n8n.grizzlymedicine.icu/webhook/jarvis-routine")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://n8n.grizzlymedicine.icu/webhook/jarvis-routine")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let bridge = AlexaRoutineBridge(session: session)
        let result = try await bridge.trigger(display: display, action: "display-camera", parameters: ["routine": "Show Front Door"])
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["routine"], "Show Front Door")
        XCTAssertEqual(result.details["transport"], "alexa-routine")
    }

    func testTriggerAutoPrefixesHTTPSWhenSchemeMissing() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "example.com/webhook/xyz")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "example.com")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let bridge = AlexaRoutineBridge(session: session)
        _ = try await bridge.trigger(display: display, action: "display-dashboard", parameters: [:])
    }

    func testTriggerThrowsOnServerError() async {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "https://example.com/webhook")
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("boom".utf8))
        }
        let bridge = AlexaRoutineBridge(session: session)
        do {
            _ = try await bridge.trigger(display: display, action: "display-camera", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("500"))
        }
    }

    func testTriggerThrowsWithoutAddress() async {
        let bridge = AlexaRoutineBridge(session: MockURLProtocol.makeSession())
        let display = makeDisplay(address: nil)
        do {
            _ = try await bridge.trigger(display: display, action: "display-camera", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("no webhook"))
        }
    }
}
