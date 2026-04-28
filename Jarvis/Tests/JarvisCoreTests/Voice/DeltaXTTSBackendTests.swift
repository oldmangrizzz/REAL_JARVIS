import XCTest
@testable import JarvisCore

final class DeltaXTTSBackendTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        unsetenv("JARVIS_CANON_TTS_HOST")
        unsetenv("JARVIS_CANON_TTS_PORT")
        unsetenv("JARVIS_CANON_TTS_SCHEME")
        unsetenv("JARVIS_CANON_TTS_PATH")
        unsetenv("JARVIS_TTS_BEARER")
        super.tearDown()
    }

    func testSynthesizeUsesCanonSpeakEndpointAndBearer() throws {
        setenv("JARVIS_CANON_TTS_HOST", "127.0.0.1", 1)
        setenv("JARVIS_CANON_TTS_PORT", "8787", 1)
        setenv("JARVIS_CANON_TTS_SCHEME", "http", 1)
        setenv("JARVIS_CANON_TTS_PATH", "/speak", 1)
        setenv("JARVIS_TTS_BEARER", "test-token", 1)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("delta-xtts-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let refURL = tempRoot.appendingPathComponent("ref.wav")
        let outURL = tempRoot.appendingPathComponent("out.wav")
        try Data("reference".utf8).write(to: refURL)

        let sawRequest = LockedBox(false)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.scheme, "http")
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.url?.port, 8787)
            XCTAssertEqual(request.url?.path, "/speak")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            let body = Self.readBody(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["text"] as? String, "Hello")
            sawRequest.set(true)

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/wav"]
            )!
            return (response, Data("RIFF-test".utf8))
        }

        let backend = try DeltaXTTSBackend(refClipSHA: "ref-sha", session: MockURLProtocol.makeSession())
        try backend.synthesize(
            text: "Hello",
            referenceAudioURL: refURL,
            referenceTranscript: "reference",
            parameters: .xttsLocked,
            outputURL: outURL
        )

        XCTAssertTrue(sawRequest.get())
        XCTAssertEqual(try Data(contentsOf: outURL), Data("RIFF-test".utf8))
    }

    private static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = (request as NSURLRequest).httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func set(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
