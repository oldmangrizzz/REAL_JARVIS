import Foundation
import Network

/// Minimal HTTP server exposing Jarvis-ratified TTS to local Obsidian plugins
/// (desktop + mobile) on the LAN. Not part of the primary encrypted tunnel;
/// this is a narrow, audited surface that does ONE thing: take text, return
/// a WAV rendered through the approved voice pipeline.
///
/// Security posture:
///  - Bearer token required on every request (shared secret from env var
///    `JARVIS_VOICE_BRIDGE_SECRET`, fall-back random per-launch).
///  - POST /speak with JSON {"text": "..."} up to 16 KB → `audio/wav`.
///  - GET  /health → 200 "ok" (no auth).
///  - Every synthesis hits `runtime.voice.speak()` which enforces the
///    VoiceApprovalGate (SOUL_ANCHOR.md). If the gate is not green, the
///    request fails 503 and no bytes go back.
public final class JarvisVoiceHTTPBridge: @unchecked Sendable {
    private let runtime: JarvisRuntime
    private let port: UInt16
    private let sharedSecret: String
    private let queue = DispatchQueue(label: "ai.realjarvis.voice-http-bridge")
    private var listener: NWListener?
    private var buffers: [ObjectIdentifier: Data] = [:]

    public init(runtime: JarvisRuntime, port: UInt16 = 8787, sharedSecret: String? = nil) {
        self.runtime = runtime
        self.port = port
        if let provided = sharedSecret {
            self.sharedSecret = provided
        } else if let env = ProcessInfo.processInfo.environment["JARVIS_VOICE_BRIDGE_SECRET"], !env.isEmpty {
            self.sharedSecret = env
        } else {
            var bytes = [UInt8](repeating: 0, count: 24)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            self.sharedSecret = bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    public var bearerToken: String { sharedSecret }

    public func start() throws {
        guard listener == nil else { return }
        let listenerPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener = try NWListener(using: .tcp, on: listenerPort)
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.receive(on: conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        buffers.removeAll()
    }

    // MARK: - Receive loop
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let id = ObjectIdentifier(connection)
                self.buffers[id, default: Data()].append(data)
                self.tryHandle(on: connection)
            }
            if isComplete || error != nil {
                self.buffers.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }

    private func tryHandle(on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard let buffer = buffers[id] else { return }
        guard let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else { return }
        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            respond(status: "400 Bad Request", body: Data("bad headers".utf8), contentType: "text/plain", on: connection)
            return
        }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            respond(status: "400 Bad Request", body: Data("bad request".utf8), contentType: "text/plain", on: connection)
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(status: "400 Bad Request", body: Data("bad request line".utf8), contentType: "text/plain", on: connection)
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let bodyBytesAvailable = buffer.count - bodyStart
        if bodyBytesAvailable < contentLength { return }  // wait for rest
        let body = buffer[bodyStart..<(bodyStart + contentLength)]
        buffers[id] = Data()  // one request per connection; close after response

        handle(method: method, path: path, headers: headers, body: Data(body), on: connection)
    }

    // MARK: - Routing
    private func handle(method: String, path: String, headers: [String: String], body: Data, on connection: NWConnection) {
        // CORS preflight for Obsidian mobile WebView fetch.
        if method == "OPTIONS" {
            respond(status: "204 No Content", body: Data(), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }
        if method == "GET" && path == "/health" {
            respond(status: "200 OK", body: Data("ok".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }

        // Auth: Bearer <secret> OR ?token=<secret> query param (mobile convenience).
        let auth = headers["authorization"] ?? ""
        let expected = "Bearer " + sharedSecret
        let tokenQuery = extractQueryValue(from: path, key: "token")
        guard auth == expected || tokenQuery == sharedSecret else {
            respond(status: "401 Unauthorized", body: Data("unauthorized".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }

        let pathOnly = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        if method == "POST" && pathOnly == "/speak" {
            serveSpeak(body: body, on: connection)
            return
        }
        respond(status: "404 Not Found", body: Data("not found".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
    }

    private func serveSpeak(body: Data, on connection: NWConnection) {
        guard body.count <= 16 * 1024 else {
            respond(status: "413 Payload Too Large", body: Data("text too long".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }
        struct SpeakRequest: Decodable { let text: String }
        let decoded: SpeakRequest
        do {
            decoded = try JSONDecoder().decode(SpeakRequest.self, from: body)
        } catch {
            respond(status: "400 Bad Request", body: Data("expected JSON {\"text\": ...}".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            respond(status: "400 Bad Request", body: Data("text empty".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }

        // Render to a temp WAV via the ratified pipeline. `speak` plays locally
        // too — that's fine; the host can echo the read. For silent-server
        // behavior we could add a dedicated synthesize-only method later.
        let outURL = runtime.paths.voiceCacheDirectory.appendingPathComponent("obsidian-\(UUID().uuidString).wav")
        do {
            _ = try runtime.voice.renderApproved(text: trimmed, persistAs: outURL, workflowID: "obsidian-voice-bridge")
        } catch {
            respond(status: "503 Service Unavailable", body: Data("voice gate: \(error.localizedDescription)".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }
        guard let wav = try? Data(contentsOf: outURL) else {
            respond(status: "500 Internal Server Error", body: Data("render failed".utf8), contentType: "text/plain", on: connection, extraHeaders: corsHeaders())
            return
        }
        respond(status: "200 OK", body: wav, contentType: "audio/wav", on: connection, extraHeaders: corsHeaders())
    }

    // MARK: - Helpers
    private func corsHeaders() -> [String: String] {
        return [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Authorization, Content-Type",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
        ]
    }

    private func extractQueryValue(from path: String, key: String) -> String? {
        guard let q = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 && kv[0] == key { return kv[1].removingPercentEncoding ?? kv[1] }
        }
        return nil
    }

    private func respond(status: String, body: Data, contentType: String, on connection: NWConnection, extraHeaders: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
