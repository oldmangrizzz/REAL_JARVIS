import Foundation

/// Mutable box for thread-safe value passing between sync and async contexts
private class MutableBox<T>: @unchecked Sendable {
    var value: T
    private let lock = NSLock()
    
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

/// DeltaXTTSBackend is the canonical TTS backend conforming to both TTSBackend
/// and CanonVerifiedBackend. It communicates with the XTTS v2 service running
/// on Delta (default: delta.grizzlymedicine.icu:8787) using bearer auth.
///
/// All network operations use async/await with proper timeouts and exponential
/// backoff. Per PRINCIPLES.md, if the canonical service is unreachable,
/// audio synthesis fails silently — there is no fallback.
public final class DeltaXTTSBackend: TTSBackend, CanonVerifiedBackend, Sendable {
    public let identifier: String
    public let selectedVoiceLabel: String
    public let sampleRate: Int
    
    public let canonIdentity: CanonBackendIdentity
    
    private let host: String
    private let port: Int
    private let bearerToken: String
    private let session: URLSession
    private let connectTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let refClipSHA: String

    /// Create a DeltaXTTSBackend from environment variables and canonical settings.
    ///
    /// Environment variables:
    /// - JARVIS_CANON_TTS_HOST (default: delta.grizzlymedicine.icu)
    /// - JARVIS_CANON_TTS_PORT (default: 8787)
    /// - JARVIS_TTS_BEARER (required; will fail if missing)
    /// - JARVIS_TTS_VOICE_LABEL (default: xtts-v2-jarvis-canonical)
    /// - JARVIS_TTS_SAMPLE_RATE (default: 24000)
    /// - JARVIS_CANON_CONNECT_TIMEOUT (default: 10 seconds)
    /// - JARVIS_CANON_REQUEST_TIMEOUT (default: 45 seconds)
    public init(refClipSHA: String, session: URLSession = .shared) throws {
        let env = ProcessInfo.processInfo.environment
        
        self.host = env["JARVIS_CANON_TTS_HOST"] ?? "delta.grizzlymedicine.icu"
        self.port = Int(env["JARVIS_CANON_TTS_PORT"] ?? "8787") ?? 8787
        
        guard let bearer = env["JARVIS_TTS_BEARER"], !bearer.isEmpty else {
            throw JarvisError.invalidInput("JARVIS_TTS_BEARER not set")
        }
        self.bearerToken = bearer
        
        self.selectedVoiceLabel = env["JARVIS_TTS_VOICE_LABEL"] ?? "xtts-v2-jarvis-canonical"
        self.sampleRate = Int(env["JARVIS_TTS_SAMPLE_RATE"] ?? "24000") ?? 24_000
        self.connectTimeout = TimeInterval(env["JARVIS_CANON_CONNECT_TIMEOUT"] ?? "10") ?? 10
        self.requestTimeout = TimeInterval(env["JARVIS_CANON_REQUEST_TIMEOUT"] ?? "45") ?? 45
        self.refClipSHA = refClipSHA
        self.session = session
        
        self.identifier = "delta-xtts-v2-canonical"
        self.canonIdentity = CanonBackendIdentity(
            host: self.host,
            port: self.port,
            model: "xtts-v2",
            refClipSHA: refClipSHA
        )
    }

    /// Synthesize text to speech by hitting the Delta XTTS service.
    /// Uses async/await internally (wrapped in synchronous interface for TTSBackend).
    public func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        // Run async work synchronously using a semaphore. This is necessary
        // because the protocol requires a synchronous interface, but we want
        // to use async/await internally for proper timeout and cancellation handling.
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox: MutableBox<Result<Data, Error>> = MutableBox(.failure(JarvisError.processFailure("not set")))

        // Capture all needed properties on the sync side
        let host = self.host
        let port = self.port
        let requestTimeout = self.requestTimeout

        let task = Task.detached { @Sendable in
            do {
                let data = try await deltaTTSSynthesizeAsyncHelper(
                    text: text,
                    referenceAudioURL: referenceAudioURL,
                    referenceTranscript: referenceTranscript,
                    parameters: parameters,
                    host: host,
                    port: port,
                    requestTimeout: requestTimeout
                )
                resultBox.set(.success(data))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + requestTimeout + 30)
        guard waitResult == .success else {
            task.cancel()
            throw JarvisError.processFailure("DeltaXTTSBackend: request timed out after \(requestTimeout)s")
        }

        let result = resultBox.get()
        switch result {
        case let .success(data):
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
        case let .failure(error):
            throw error
        }
    }

    // MARK: - Async Implementation removed - see deltaTTSSynthesizeAsyncHelper() below class
}

// MARK: - Static helper for Delta async work (Sendable closure support)

private func deltaTTSSynthesizeAsyncHelper(
    text: String,
    referenceAudioURL: URL,
    referenceTranscript: String,
    parameters: TTSRenderParameters,
    host: String,
    port: Int,
    requestTimeout: TimeInterval
) async throws -> Data {
    let referenceData = try Data(contentsOf: referenceAudioURL)
    var payload: [String: Any] = [
        "text": text,
        "reference_audio_b64": referenceData.base64EncodedString(),
        "reference_text": referenceTranscript,
        "temperature": parameters.temperature,
        "top_p": parameters.topP
    ]
    if let maxTokens = parameters.maxNewTokens {
        payload["max_new_tokens"] = maxTokens
    }
    if let cfg = parameters.cfgScale {
        payload["cfg_scale"] = cfg
    }
    if let ddpm = parameters.ddpmSteps {
        payload["ddpm_steps"] = ddpm
    }

    let body = try JSONSerialization.data(withJSONObject: payload)
    let url = URL(string: "https://\(host):\(port)/tts")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = requestTimeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("audio/wav", forHTTPHeaderField: "Accept")
    request.httpBody = body

    // Exponential backoff: 500ms, 1s, 2s (max 3 retries)
    let maxRetries = 3
    var retryCount = 0
    var lastError: Error?

    while retryCount < maxRetries {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JarvisError.processFailure("DeltaXTTSBackend: response was not HTTP")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let bodyPreview = String(data: data.prefix(512), encoding: .utf8) ?? "<no body>"
                throw JarvisError.processFailure(
                    "DeltaXTTSBackend: \(httpResponse.statusCode) from \(url): \(bodyPreview)"
                )
            }

            // Try to parse as JSON with audio_b64, fall back to raw WAV bytes
            let wavBytes: Data
            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if contentType.contains("application/json") {
                let object = try JSONSerialization.jsonObject(with: data)
                guard
                    let dict = object as? [String: Any],
                    let b64 = dict["audio_b64"] as? String,
                    let decoded = Data(base64Encoded: b64)
                else {
                    throw JarvisError.serializationFailure("DeltaXTTSBackend: JSON response missing audio_b64")
                }
                wavBytes = decoded
            } else {
                wavBytes = data
            }

            return wavBytes
        } catch {
            lastError = error
            retryCount += 1

            if retryCount < maxRetries {
                let backoffMs = Int(pow(2.0, Double(retryCount - 1))) * 500
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            }
        }
    }

    throw lastError ?? JarvisError.processFailure("DeltaXTTSBackend: all retries exhausted")
}
