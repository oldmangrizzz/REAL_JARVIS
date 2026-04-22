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

/// HTTPTTSBackend ships text + reference audio (base64) + transcript +
/// render parameters to a remote VibeVoice (or other) service and writes
/// the returned WAV to outputURL. This is the production path on this
/// hardware — local TTS is unreliable in 8 GB.
///
/// Service contract (VibeVoice FastAPI on GCP):
/// POST {endpoint}
/// Authorization: Bearer {token}
/// Content-Type: application/json
/// {
///   "text": "...",
///   "reference_audio_b64": "<base64 wav>",
///   "reference_text": "...",
///   "temperature": 0.65,
///   "top_p": 0.92,
///   "max_new_tokens": null
/// }
/// → 200 audio/wav (raw bytes) OR application/json {"audio_b64": "..."}

// MARK: - Static helper for async work (Sendable closure support)

private func httpTTSSynthesizeAsyncHelper(
    text: String,
    referenceAudioURL: URL,
    referenceTranscript: String,
    parameters: TTSRenderParameters,
    endpoint: URL,
    bearerToken: String,
    session: URLSession,
    timeout: TimeInterval
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
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("audio/wav", forHTTPHeaderField: "Accept")
    request.httpBody = body

    let (data, response) = try await session.data(for: request)
        
    guard let httpResponse = response as? HTTPURLResponse else {
        throw JarvisError.processFailure("HTTPTTSBackend: response was not HTTP.")
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        let bodyPreview = String(data: data.prefix(512), encoding: .utf8) ?? "<no body>"
        throw JarvisError.processFailure("HTTPTTSBackend: \(httpResponse.statusCode) from \(endpoint): \(bodyPreview)")
    }

    let wavBytes: Data
    let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
    if contentType.contains("application/json") {
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let dict = object as? [String: Any],
            let b64 = dict["audio_b64"] as? String,
            let decoded = Data(base64Encoded: b64)
        else {
            throw JarvisError.serializationFailure("HTTPTTSBackend: JSON response missing audio_b64.")
        }
        wavBytes = decoded
    } else {
        wavBytes = data
    }

    return wavBytes
}

// MARK: - HTTPTTSBackend class

public final class HTTPTTSBackend: TTSBackend, Sendable {
    public let identifier: String
    public let selectedVoiceLabel: String
    public let sampleRate: Int

    private let endpoint: URL
    private let bearerToken: String
    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        endpoint: URL,
        bearerToken: String,
        identifier: String,
        selectedVoiceLabel: String = "xtts-v2-jarvis-canonical",
        sampleRate: Int = 24_000,
        session: URLSession = .shared,
        timeout: TimeInterval = 300
    ) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.identifier = identifier
        self.selectedVoiceLabel = selectedVoiceLabel
        self.sampleRate = sampleRate
        self.session = session
        self.timeout = timeout
    }

    public func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox: MutableBox<Result<Data, Error>> = MutableBox(.failure(JarvisError.processFailure("not set")))

        // Capture all needed properties on the sync side, so the async closure doesn't need self
        let endpoint = self.endpoint
        let bearerToken = self.bearerToken
        let session = self.session
        let timeout = self.timeout

        let task = Task.detached { @Sendable in
            do {
                let data = try await httpTTSSynthesizeAsyncHelper(
                    text: text,
                    referenceAudioURL: referenceAudioURL,
                    referenceTranscript: referenceTranscript,
                    parameters: parameters,
                    endpoint: endpoint,
                    bearerToken: bearerToken,
                    session: session,
                    timeout: timeout
                )
                resultBox.set(.success(data))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout + 30)
        guard waitResult == .success else {
            task.cancel()
            throw JarvisError.processFailure("HTTPTTSBackend: request timed out after \(timeout)s")
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
}

public enum HTTPTTSBackendFactory {
    /// Construct an HTTPTTSBackend from the standard JARVIS_TTS_* env vars.
    /// Returns nil if the URL or bearer token is missing — caller should
    /// fall back to the local backend in that case.
    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> HTTPTTSBackend? {
        guard
            let urlString = env["JARVIS_TTS_URL"],
            let url = URL(string: urlString),
            let token = env["JARVIS_TTS_BEARER"],
            !token.isEmpty
        else { return nil }
        let identifier = env["JARVIS_TTS_IDENTIFIER"] ?? "remote-tts"
        let label = env["JARVIS_TTS_VOICE_LABEL"] ?? "remote-clone"
        let rate = Int(env["JARVIS_TTS_SAMPLE_RATE"] ?? "") ?? 24_000
        let timeout = TimeInterval(env["JARVIS_TTS_TIMEOUT_SECONDS"] ?? "") ?? 300
        return HTTPTTSBackend(
            endpoint: url,
            bearerToken: token,
            identifier: identifier,
            selectedVoiceLabel: label,
            sampleRate: rate,
            timeout: timeout
        )
    }
}
