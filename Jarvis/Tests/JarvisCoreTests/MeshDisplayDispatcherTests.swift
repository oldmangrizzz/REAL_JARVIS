import XCTest
@testable import JarvisCore

final class MeshDisplayDispatcherTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeDisplay(address: String?) -> DisplayEndpoint {
        DisplayEndpoint(
            id: "alpha",
            displayName: "Alpha",
            aliases: ["alpha"],
            type: .meshNode,
            transport: .jarvisTunnel,
            address: address,
            capabilities: ["display-dashboard"],
            room: "server-closet",
            authority: .fullControl
        )
    }

    func testDispatchPostsJSONWithBearer() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "alpha.grizzlymedicine.icu")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://alpha.grizzlymedicine.icu:9455/display")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = request.httpBody ?? (request as NSURLRequest).httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }
                var data = Data()
                let bufSize = 4096
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buf, maxLength: bufSize)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                }
                return data
            } ?? Data()
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["display"] as? String, "alpha")
            XCTAssertEqual(json?["action"] as? String, "display-dashboard")
            XCTAssertEqual(json?["authority"] as? String, "full-control")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("ok".utf8))
        }

        let dispatcher = MeshDisplayDispatcher(session: session, bearerToken: "test-secret")
        let result = try await dispatcher.dispatch(display: display, action: "display-dashboard", parameters: ["content": "telemetry"])
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["transport"], "jarvis-tunnel")
        XCTAssertEqual(result.details["status"], "dispatched")
        XCTAssertEqual(result.details["httpStatus"], "200")
    }

    func testDispatchHandlesHostPortAddress() async throws {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "192.168.4.100:whatever")
        MockURLProtocol.handler = { request in
            // host portion is everything before first colon; port comes from config (9455)
            XCTAssertEqual(request.url?.host, "192.168.4.100")
            XCTAssertEqual(request.url?.port, 9455)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let dispatcher = MeshDisplayDispatcher(session: session, bearerToken: nil)
        let result = try await dispatcher.dispatch(display: display, action: "display-hud", parameters: [:])
        XCTAssertTrue(result.success)
    }

    func testDispatchThrowsOnHTTPFailure() async {
        let session = MockURLProtocol.makeSession()
        let display = makeDisplay(address: "alpha.local")
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("bad gateway".utf8))
        }
        let dispatcher = MeshDisplayDispatcher(session: session, bearerToken: "x")
        do {
            _ = try await dispatcher.dispatch(display: display, action: "display-dashboard", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("502"))
        }
    }

    func testDispatchThrowsOnMissingAddress() async {
        let dispatcher = MeshDisplayDispatcher(session: MockURLProtocol.makeSession(), bearerToken: "x")
        let display = makeDisplay(address: nil)
        do {
            _ = try await dispatcher.dispatch(display: display, action: "display-dashboard", parameters: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("no address"))
        }
    }
}
