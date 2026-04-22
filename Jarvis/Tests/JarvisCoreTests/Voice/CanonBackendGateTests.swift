import XCTest
@testable import JarvisCore

final class CanonBackendGateTests: XCTestCase {
    
    func test_verify_rejects_non_conforming_backend() throws {
        let nonConformingBackend = FakeTTSBackend()
        
        XCTAssertThrowsError(
            try CanonBackendGate.verify(nonConformingBackend)
        ) { error in
            if let gateError = error as? CanonGateError {
                switch gateError {
                case .backendNotCanonical:
                    break
                default:
                    XCTFail("Expected .backendNotCanonical, got \(gateError)")
                }
            } else {
                XCTFail("Expected CanonGateError, got \(type(of: error))")
            }
        }
    }
    
    func test_verify_rejects_wrong_host() throws {
        let backend = FakeCanonBackend(
            host: "wrong-host.invalid",
            port: 8787,
            model: "xtts-v2"
        )
        
        XCTAssertThrowsError(
            try CanonBackendGate.verify(backend)
        ) { error in
            if let gateError = error as? CanonGateError {
                switch gateError {
                case .identityDrift:
                    break
                default:
                    XCTFail("Expected .identityDrift, got \(gateError)")
                }
            } else {
                XCTFail("Expected CanonGateError, got \(type(of: error))")
            }
        }
    }
    
    func test_verify_rejects_wrong_port() throws {
        let backend = FakeCanonBackend(
            host: "delta.grizzlymedicine.icu",
            port: 9999,
            model: "xtts-v2"
        )
        
        XCTAssertThrowsError(
            try CanonBackendGate.verify(backend)
        ) { error in
            if let gateError = error as? CanonGateError {
                switch gateError {
                case .identityDrift:
                    break
                default:
                    XCTFail("Expected .identityDrift, got \(gateError)")
                }
            } else {
                XCTFail("Expected CanonGateError, got \(type(of: error))")
            }
        }
    }
    
    func test_verify_rejects_wrong_model() throws {
        let backend = FakeCanonBackend(
            host: "delta.grizzlymedicine.icu",
            port: 8787,
            model: "wrong-model"
        )
        
        XCTAssertThrowsError(
            try CanonBackendGate.verify(backend)
        ) { error in
            if let gateError = error as? CanonGateError {
                switch gateError {
                case .identityDrift:
                    break
                default:
                    XCTFail("Expected .identityDrift, got \(gateError)")
                }
            } else {
                XCTFail("Expected CanonGateError, got \(type(of: error))")
            }
        }
    }
    
    func test_verify_rejects_missing_refclip_sha() throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sha256File = homeDir.appendingPathComponent(".jarvis/voice/canon_ref.sha256")
        let originalContent: String? = (try? String(contentsOf: sha256File, encoding: .utf8))
        
        defer {
            if let content = originalContent {
                try? content.write(toFile: sha256File.path, atomically: true, encoding: .utf8)
            }
        }
        
        try? FileManager.default.removeItem(at: sha256File)
        
        let backend = FakeCanonBackend(
            host: "delta.grizzlymedicine.icu",
            port: 8787,
            model: "xtts-v2"
        )
        
        XCTAssertThrowsError(
            try CanonBackendGate.verify(backend)
        ) { error in
            if let gateError = error as? CanonGateError {
                switch gateError {
                case .missingRefClipSHA:
                    break
                default:
                    XCTFail("Expected .missingRefClipSHA, got \(gateError)")
                }
            } else {
                XCTFail("Expected CanonGateError, got \(type(of: error))")
            }
        }
    }
    
    func test_verify_accepts_delta_xtts_with_matching_env() throws {
        let backend = FakeCanonBackend(
            host: "delta.grizzlymedicine.icu",
            port: 8787,
            model: "xtts-v2"
        )
        
        let verified = try CanonBackendGate.verify(backend)
        XCTAssertNotNil(verified)
        XCTAssertEqual(verified.canonIdentity.host, "delta.grizzlymedicine.icu")
        XCTAssertEqual(verified.canonIdentity.port, 8787)
        XCTAssertEqual(verified.canonIdentity.model, "xtts-v2")
    }
}

// MARK: - Test Doubles

private final class FakeTTSBackend: TTSBackend {
    let identifier: String = "test-backend"
    let selectedVoiceLabel: String = "test-voice"
    let sampleRate: Int = 24_000
    
    func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        // No-op
    }
}

private final class FakeCanonBackend: TTSBackend, CanonVerifiedBackend {
    let identifier: String = "fake-canonical"
    let selectedVoiceLabel: String = "test-canonical"
    let sampleRate: Int = 24_000
    
    let canonIdentity: CanonBackendIdentity
    
    init(host: String, port: Int, model: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sha256File = homeDir.appendingPathComponent(".jarvis/voice/canon_ref.sha256")
        let sha = (try? String(contentsOf: sha256File, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "fake-sha"
        
        self.canonIdentity = CanonBackendIdentity(
            host: host,
            port: port,
            model: model,
            refClipSHA: sha
        )
    }
    
    func synthesize(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        parameters: TTSRenderParameters,
        outputURL: URL
    ) throws {
        // No-op
    }
}
