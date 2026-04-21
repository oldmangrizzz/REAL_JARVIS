import XCTest
@testable import JarvisCore

final class N8nWorkflowRunnerTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    fileprivate static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = (request as NSURLRequest).httpBodyStream else { return Data() }
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
    }

    private func bodyData(from request: URLRequest) -> Data {
        Self.readBody(from: request)
    }

    func testRunPostsJSONToWebhookPath() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://n8n.example.com/webhook/jarvis/ha/call-service")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"status":"ok"}"#.utf8))
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        let result = try await runner.run(
            workflowPath: "jarvis/ha/call-service",
            payload: ["domain": "light", "service": "turn_on"]
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.details["workflow"], "jarvis/ha/call-service")
        XCTAssertEqual(result.details["httpStatus"], "200")
        XCTAssertEqual(result.details["status"], "dispatched")
        XCTAssertEqual(result.details["agentResponse"], #"{"status":"ok"}"#)
    }

    func testRunStampsTsAndSourceWhenMissing() async throws {
        let session = MockURLProtocol.makeSession()
        let captured = Captured()
        MockURLProtocol.handler = { request in
            captured.body = Self.readBody(from: request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        _ = try await runner.run(workflowPath: "jarvis/scene/downstairs-on", payload: ["scene": "downstairs-on"])

        let json = try JSONSerialization.jsonObject(with: captured.body) as? [String: Any]
        XCTAssertEqual(json?["source"] as? String, "jarvis")
        XCTAssertEqual(json?["scene"] as? String, "downstairs-on")
        XCTAssertNotNil(json?["ts"] as? String)
    }

    func testRunPreservesCallerProvidedTsAndSource() async throws {
        let session = MockURLProtocol.makeSession()
        let captured = Captured()
        MockURLProtocol.handler = { request in
            captured.body = Self.readBody(from: request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        _ = try await runner.run(
            workflowPath: "jarvis/ha/call-service",
            payload: ["ts": "2020-01-01T00:00:00Z", "source": "test-harness", "k": "v"]
        )
        let json = try JSONSerialization.jsonObject(with: captured.body) as? [String: Any]
        XCTAssertEqual(json?["ts"] as? String, "2020-01-01T00:00:00Z")
        XCTAssertEqual(json?["source"] as? String, "test-harness")
    }

    func testRunSendsBasicAuthWhenConfigured() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { request in
            // base64("admin:secret") = YWRtaW46c2VjcmV0
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YWRtaW46c2VjcmV0")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: "admin",
            basicAuthPassword: "secret"
        )
        _ = try await runner.run(workflowPath: "jarvis/x", payload: [:])
    }

    func testRunStripsLeadingSlashAndWhitespaceFromPath() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://n8n.example.com/webhook/jarvis/ha/call-service")
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        _ = try await runner.run(workflowPath: "  /jarvis/ha/call-service/  ", payload: [:])
    }

    func testRunThrowsOnEmptyPath() async {
        let runner = N8nWorkflowRunner(
            session: MockURLProtocol.makeSession(),
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        do {
            _ = try await runner.run(workflowPath: "   /  ", payload: [:])
            XCTFail("expected throw on empty path")
        } catch {
            XCTAssertTrue("\(error)".contains("cannot be empty"))
        }
    }

    func testRunThrowsOnHTTPFailure() async {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("kaboom".utf8))
        }
        let runner = N8nWorkflowRunner(
            session: session,
            baseURL: URL(string: "https://n8n.example.com/")!,
            basicAuthUser: nil,
            basicAuthPassword: nil
        )
        do {
            _ = try await runner.run(workflowPath: "jarvis/ha/call-service", payload: [:])
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue("\(error)".contains("500"))
            XCTAssertTrue("\(error)".contains("kaboom"))
        }
    }

    // Simple captured-body holder so the MockURLProtocol closure (which can't
    // mutate test-local let bindings) can publish the request body out.
    private final class Captured: @unchecked Sendable {
        var body: Data = Data()
    }
}
