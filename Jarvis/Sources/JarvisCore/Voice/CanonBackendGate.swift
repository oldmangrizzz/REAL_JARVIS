import Foundation

/// CanonBackend defines the canonical TTS backend(s) permitted under
/// PRINCIPLES.md CANON LAW — VOICE (locked 2026-04-21). Only one backend
/// is currently canonical: Coqui XTTS v2 on Delta:8787.
public enum CanonBackend {
    case deltaXTTSv2
}

/// CanonBackendIdentity wraps the verified identity of a TTS backend.
/// This must match the env-configured Delta service exactly.
public struct CanonBackendIdentity: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let model: String
    public let refClipSHA: String

    public init(host: String, port: Int, model: String, refClipSHA: String) {
        self.host = host
        self.port = port
        self.model = model
        self.refClipSHA = refClipSHA
    }
}

/// CanonVerifiedBackend is a marker protocol that TTS backends MUST
/// conform to in order to pass the CanonBackendGate. Conforming backends
/// expose their canonical identity for gating verification.
public protocol CanonVerifiedBackend {
    var canonIdentity: CanonBackendIdentity { get }
}

/// CanonGateError enumerates all ways a TTS backend can fail the canon gate.
/// Per PRINCIPLES.md, any gate failure results in silent refusal (no fallback,
/// no substitution, no voice output).
public enum CanonGateError: Error {
    case backendNotCanonical(String)
    case missingIdentity
    case identityDrift(expected: CanonBackendIdentity, got: CanonBackendIdentity)
    case missingRefClipSHA
    case refClipSHAMismatch(expected: String, got: String)
}

/// CanonBackendGate enforces voice canon law at the speak boundary.
/// All audio synthesis must pass this gate before any waveform is generated.
public struct CanonBackendGate {
    /// Verify that the given TTS backend conforms to canon law.
    ///
    /// Verification checks:
    /// 1. Backend must conform to CanonVerifiedBackend protocol.
    /// 2. Backend's canonIdentity.host must match JARVIS_CANON_TTS_HOST env
    ///    (default: delta.grizzlymedicine.icu) or the env-configured Delta IP.
    /// 3. Backend's canonIdentity.port must match JARVIS_CANON_TTS_PORT env
    ///    (default: 8787).
    /// 4. Backend's canonIdentity.model must be exactly "xtts-v2".
    /// 5. Backend's canonIdentity.refClipSHA must match the SHA stored in
    ///    ~/.jarvis/voice/canon_ref.sha256.
    ///
    /// On any mismatch, throws CanonGateError. The caller MUST NOT attempt
    /// fallback, substitution, or any audio generation. Per PRINCIPLES.md,
    /// canon failure = silent.
    ///
    /// - Parameter backend: The TTS backend to verify.
    /// - Returns: The same backend, upcast to CanonVerifiedBackend, if verification passes.
    /// - Throws: CanonGateError if verification fails.
    public static func verify(_ backend: TTSBackend) throws -> CanonVerifiedBackend {
        guard let canonical = backend as? CanonVerifiedBackend else {
            throw CanonGateError.backendNotCanonical(
                "Backend \(type(of: backend)) does not conform to CanonVerifiedBackend"
            )
        }

        let env = ProcessInfo.processInfo.environment
        let expectedHost = env["JARVIS_CANON_TTS_HOST"] ?? "delta.grizzlymedicine.icu"
        let expectedPort = Int(env["JARVIS_CANON_TTS_PORT"] ?? "8787") ?? 8787
        let expectedModel = "xtts-v2"

        let identity = canonical.canonIdentity

        // Check host
        if identity.host != expectedHost {
            throw CanonGateError.identityDrift(
                expected: CanonBackendIdentity(
                    host: expectedHost,
                    port: expectedPort,
                    model: expectedModel,
                    refClipSHA: "<pending SHA verification>"
                ),
                got: identity
            )
        }

        // Check port
        if identity.port != expectedPort {
            throw CanonGateError.identityDrift(
                expected: CanonBackendIdentity(
                    host: expectedHost,
                    port: expectedPort,
                    model: expectedModel,
                    refClipSHA: "<pending SHA verification>"
                ),
                got: identity
            )
        }

        // Check model
        if identity.model != expectedModel {
            throw CanonGateError.identityDrift(
                expected: CanonBackendIdentity(
                    host: expectedHost,
                    port: expectedPort,
                    model: expectedModel,
                    refClipSHA: "<pending SHA verification>"
                ),
                got: identity
            )
        }

        // Load and verify reference clip SHA
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sha256File = homeDir.appendingPathComponent(".jarvis/voice/canon_ref.sha256")
        
        guard FileManager.default.fileExists(atPath: sha256File.path) else {
            throw CanonGateError.missingRefClipSHA
        }

        let expectedSHA: String
        do {
            let sha = try String(contentsOf: sha256File, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else {
                throw CanonGateError.missingRefClipSHA
            }
            expectedSHA = sha
        } catch {
            throw CanonGateError.missingRefClipSHA
        }

        // Check reference clip SHA
        if identity.refClipSHA != expectedSHA {
            throw CanonGateError.refClipSHAMismatch(
                expected: expectedSHA,
                got: identity.refClipSHA
            )
        }

        return canonical
    }
}
