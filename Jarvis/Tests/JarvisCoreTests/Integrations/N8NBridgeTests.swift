import XCTest
@testable import JarvisCore

final class N8NBridgeTests: XCTestCase {

    final class MockTransport: N8NTransport, @unchecked Sendable {
        var response: (Data, HTTPURLResponse)!
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        var shouldThrow: Error?

        func post(_ request: URLRequest, body: Data) async throws -> (Data, HTTPURLResponse) {
            capturedRequest = request
            capturedBody = body
            if let err = shouldThrow { throw err }
            return response
        }
    }

    private func makeHTTPResponse(
        url: URL = URL(string: "http://192.168.4.119:5678/webhook/x")!,
        status: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testRunWorkflow_success_returnsDecodedJSON() async throws {
        let transport = MockTransport()
        let body = try JSONSerialization.data(withJSONObject: ["status": "ok", "id": 42])
        transport.response = (body, makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        let result = try await bridge.runWorkflow(webhookPath: "jarvis/test", payload: ["x": 1])
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(result["id"] as? Int, 42)
    }

    func testRunWorkflow_buildsWebhookURLWithPath() async throws {
        let transport = MockTransport()
        transport.response = (Data("{}".utf8), makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        _ = try await bridge.runWorkflow(webhookPath: "jarvis/scene/lights")
        XCTAssertEqual(
            transport.capturedRequest?.url?.absoluteString,
            "http://192.168.4.119:5678/webhook/jarvis/scene/lights"
        )
    }

    func testRunWorkflow_stripsLeadingSlashInPath() async throws {
        let transport = MockTransport()
        transport.response = (Data("{}".utf8), makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        _ = try await bridge.runWorkflow(webhookPath: "/jarvis/x")
        XCTAssertEqual(
            transport.capturedRequest?.url?.absoluteString,
            "http://192.168.4.119:5678/webhook/jarvis/x"
        )
    }

    func testRunWorkflow_setsBasicAuthHeader() async throws {
        let transport = MockTransport()
        transport.response = (Data("{}".utf8), makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            basicAuthUser: "admin",
            basicAuthPassword: "secret",
            transport: transport
        )
        _ = try await bridge.runWorkflow(webhookPath: "x")
        let header = transport.capturedRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(header)
        XCTAssertTrue(header?.hasPrefix("Basic ") ?? false)
        let expected = "admin:secret".data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(header, "Basic \(expected)")
    }

    func testRunWorkflow_unauthorizedThrows() async {
        let transport = MockTransport()
        transport.response = (Data(), makeHTTPResponse(status: 401))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        do {
            _ = try await bridge.runWorkflow(webhookPath: "x")
            XCTFail("Expected unauthorized")
        } catch N8NBridgeError.unauthorized {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRunWorkflow_httpErrorIncludesStatusAndBody() async {
        let transport = MockTransport()
        transport.response = (Data("boom".utf8), makeHTTPResponse(status: 500))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        do {
            _ = try await bridge.runWorkflow(webhookPath: "x")
            XCTFail("Expected httpStatus error")
        } catch N8NBridgeError.httpStatus(let code, let msg) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(msg, "boom")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRunWorkflow_emptyBodyReturnsEmptyDict() async throws {
        let transport = MockTransport()
        transport.response = (Data(), makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        let result = try await bridge.runWorkflow(webhookPath: "x")
        XCTAssertTrue(result.isEmpty)
    }

    func testRunWorkflow_encodesPayloadAsJSON() async throws {
        let transport = MockTransport()
        transport.response = (Data("{}".utf8), makeHTTPResponse(status: 200))

        let bridge = N8NBridge(
            baseURL: URL(string: "http://192.168.4.119:5678")!,
            transport: transport
        )
        _ = try await bridge.runWorkflow(
            webhookPath: "x",
            payload: ["room": "downstairs", "brightness": 80]
        )
        let body = transport.capturedBody ?? Data()
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(decoded?["room"] as? String, "downstairs")
        XCTAssertEqual(decoded?["brightness"] as? Int, 80)
    }
}
