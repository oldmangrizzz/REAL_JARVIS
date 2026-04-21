import XCTest
@testable import JarvisCore

private final class MockLettaTransport: LettaTransport, @unchecked Sendable {
    struct Call: Sendable {
        let method: String
        let url: URL
        let body: Data?
        let authorization: String?
    }

    var nextStatus: Int = 200
    var nextBody: Data = Data()
    private(set) var calls: [Call] = []

    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let auth = request.value(forHTTPHeaderField: "Authorization")
        calls.append(Call(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            body: body,
            authorization: auth
        ))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: nextStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (nextBody, response)
    }
}

final class LettaBridgeTests: XCTestCase {
    private func bridge(_ t: MockLettaTransport, token: String? = "bearer-test") -> LettaBridge {
        LettaBridge(
            baseURL: URL(string: "http://192.168.7.200:8283")!,
            bearerToken: token,
            transport: t
        )
    }

    func testHealthReturnsDecodedStatus() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 200
        t.nextBody = #"{"version":"0.16.7","status":"ok"}"#.data(using: .utf8)!
        let result = try await bridge(t).health()
        XCTAssertEqual(result["status"] as? String, "ok")
        XCTAssertEqual(result["version"] as? String, "0.16.7")

        XCTAssertEqual(t.calls.count, 1)
        XCTAssertEqual(t.calls[0].method, "GET")
        XCTAssertTrue(t.calls[0].url.absoluteString.hasSuffix("/v1/health/"))
        XCTAssertEqual(t.calls[0].authorization, "Bearer bearer-test")
    }

    func testListAgentsDecodesArray() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 200
        t.nextBody = #"[{"id":"a1","name":"jarvis"}]"#.data(using: .utf8)!
        let agents = try await bridge(t).listAgents()
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0]["id"] as? String, "a1")
    }

    func testSendMessagePostsPayloadAndParses() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 200
        t.nextBody = #"{"messages":[{"role":"assistant","text":"ack"}]}"#.data(using: .utf8)!
        let reply = try await bridge(t).sendMessage(agentID: "a1", message: "hello")
        XCTAssertNotNil(reply["messages"])

        let call = t.calls[0]
        XCTAssertEqual(call.method, "POST")
        XCTAssertTrue(call.url.absoluteString.contains("/v1/agents/a1/messages"))
        let decoded = try JSONSerialization.jsonObject(with: call.body!) as? [String: Any]
        let msgs = decoded?["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.first?["text"] as? String, "hello")
        XCTAssertEqual(msgs?.first?["role"] as? String, "user")
    }

    func testUnauthorizedMapsToError() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 401
        t.nextBody = Data()
        do {
            _ = try await bridge(t).health()
            XCTFail("expected unauthorized")
        } catch let err as LettaBridgeError {
            XCTAssertEqual(err, .unauthorized)
        }
    }

    func testHTTPErrorStatusSurfacesBody() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 500
        t.nextBody = "boom".data(using: .utf8)!
        do {
            _ = try await bridge(t).listAgents()
            XCTFail("expected httpStatus error")
        } catch let err as LettaBridgeError {
            if case .httpStatus(let code, let msg) = err {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(msg, "boom")
            } else {
                XCTFail("wrong error: \(err)")
            }
        }
    }

    func testOmitsAuthorizationHeaderWhenTokenNil() async throws {
        let t = MockLettaTransport()
        t.nextStatus = 200
        t.nextBody = #"{"status":"ok"}"#.data(using: .utf8)!
        _ = try await bridge(t, token: nil).health()
        XCTAssertNil(t.calls[0].authorization)
    }
}
