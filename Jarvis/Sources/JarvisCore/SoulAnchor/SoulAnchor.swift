import Foundation
import CryptoKit

// MARK: - Soul Anchor
//
// The cryptographic root of JARVIS's identity, per SOUL_ANCHOR.md.
// Holds ONLY public key material and content-addressed bindings.
// Private keys live in the Secure Enclave (P-256) or in the operator's
// cold storage (Ed25519) and NEVER transit this process's memory.
//
// See: /PRINCIPLES.md, /VERIFICATION_PROTOCOL.md, /SOUL_ANCHOR.md

public struct SoulAnchorPublicKeys: Codable, Sendable, Equatable {
    /// DER-encoded P-256 public key (hex).
    public let p256PublicKeyHex: String
    /// Raw Ed25519 public key (32 bytes, hex).
    public let ed25519PublicKeyHex: String

    public var p256Fingerprint: String { Self.sha256Hex(hex: p256PublicKeyHex) }
    public var ed25519Fingerprint: String { Self.sha256Hex(hex: ed25519PublicKeyHex) }

    private static func sha256Hex(hex: String) -> String {
        let bytes = Data(hex: hex) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SoulAnchorBindings: Codable, Sendable, Equatable {
    public let hardwareIdHash: String
    public let biographicalMassHash: String
    public let realignmentHash: String
    public let principlesHash: String
    public let verificationHash: String
    public let mcuhistManifestHash: String
    public let genesisTimestamp: String
    public let operatorOfRecord: String
    public let schemaVersion: String
}

public struct SoulAnchorSignatures: Codable, Sendable, Equatable {
    /// DER-encoded ECDSA-P256 signature over canonical JSON of the
    /// `{publicKeys, bindings}` tuple (hex).
    public let p256: String
    /// Raw 64-byte Ed25519 signature over the same canonical JSON (hex).
    public let ed25519: String
}

public struct GenesisRecord: Codable, Sendable, Equatable {
    public let publicKeys: SoulAnchorPublicKeys
    public let bindings: SoulAnchorBindings
    public let signatures: SoulAnchorSignatures
}

// MARK: - Anchor

public enum SoulAnchorError: Error, CustomStringConvertible {
    case missingPublicKey(String)
    case missingGenesisRecord(URL)
    case canonicalJSONFailure
    case signatureInvalid(curve: String)
    case bindingHashMismatch(field: String, expected: String, actual: String)
    case privateKeyLeakAttempt

    public var description: String {
        switch self {
        case let .missingPublicKey(name):
            return "Soul Anchor public key missing: \(name)."
        case let .missingGenesisRecord(url):
            return "Genesis record missing at \(url.path)."
        case .canonicalJSONFailure:
            return "Failed to produce canonical JSON for Soul Anchor verification."
        case let .signatureInvalid(curve):
            return "Soul Anchor signature failed verification (\(curve))."
        case let .bindingHashMismatch(field, expected, actual):
            return "Soul Anchor binding drift on \(field): expected \(expected), got \(actual)."
        case .privateKeyLeakAttempt:
            return "SoulAnchor refused an operation that would have exposed private key material."
        }
    }
}

public final class SoulAnchor {
    public let paths: WorkspacePaths
    public let record: GenesisRecord

    public init(paths: WorkspacePaths, record: GenesisRecord) {
        self.paths = paths
        self.record = record
    }

    // MARK: Load

    public static func load(paths: WorkspacePaths) throws -> SoulAnchor {
        let genesisURL = paths.root
            .appendingPathComponent(".jarvis")
            .appendingPathComponent("soul_anchor")
            .appendingPathComponent("genesis.json")
        guard FileManager.default.fileExists(atPath: genesisURL.path) else {
            throw SoulAnchorError.missingGenesisRecord(genesisURL)
        }
        let data = try Data(contentsOf: genesisURL)
        let decoder = JSONDecoder()
        let record = try decoder.decode(GenesisRecord.self, from: data)
        return SoulAnchor(paths: paths, record: record)
    }

    // MARK: Verify

    /// Full Soul Anchor verification chain — dual signatures + live hash
    /// re-computation against the four canonical canon files.
    public func verify() throws {
        try verifySignatures()
        try verifyLiveBindings()
    }

    public func verifySignatures() throws {
        let canonical = try canonicalJSON(publicKeys: record.publicKeys,
                                          bindings: record.bindings)

        // P-256
        guard let p256KeyData = Data(hex: record.publicKeys.p256PublicKeyHex) else {
            throw SoulAnchorError.missingPublicKey("p256")
        }
        let p256Key = try P256.Signing.PublicKey(derRepresentation: p256KeyData)
        guard let p256SigData = Data(hex: record.signatures.p256),
              let p256Sig = try? P256.Signing.ECDSASignature(derRepresentation: p256SigData),
              p256Key.isValidSignature(p256Sig, for: canonical) else {
            throw SoulAnchorError.signatureInvalid(curve: "P-256")
        }

        // Ed25519
        guard let edKeyData = Data(hex: record.publicKeys.ed25519PublicKeyHex) else {
            throw SoulAnchorError.missingPublicKey("ed25519")
        }
        let edKey = try Curve25519.Signing.PublicKey(rawRepresentation: edKeyData)
        guard let edSigData = Data(hex: record.signatures.ed25519),
              edKey.isValidSignature(edSigData, for: canonical) else {
            throw SoulAnchorError.signatureInvalid(curve: "Ed25519")
        }
    }

    public func verifyLiveBindings() throws {
        let root = paths.root
        try compareHash(field: "principlesHash",
                        expected: record.bindings.principlesHash,
                        fileURL: root.appendingPathComponent("PRINCIPLES.md"))
        try compareHash(field: "verificationHash",
                        expected: record.bindings.verificationHash,
                        fileURL: root.appendingPathComponent("VERIFICATION_PROTOCOL.md"))
        try compareHash(field: "mcuhistManifestHash",
                        expected: record.bindings.mcuhistManifestHash,
                        fileURL: root.appendingPathComponent("mcuhist/MANIFEST.md"))
        try compareHash(field: "realignmentHash",
                        expected: record.bindings.realignmentHash,
                        fileURL: root.appendingPathComponent("mcuhist/REALIGNMENT_1218.md"))
        try verifyBiographicalMass()
    }

    private func verifyBiographicalMass() throws {
        let root = paths.root.appendingPathComponent("mcuhist")
        let ordered = ["1.md", "2.md", "3.md", "4.md", "5.md"]
        var hasher = SHA256()
        for name in ordered {
            let url = root.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let expected = record.bindings.biographicalMassHash
        if actual != expected {
            throw SoulAnchorError.bindingHashMismatch(field: "biographicalMassHash",
                                                      expected: expected,
                                                      actual: actual)
        }
    }

    private func compareHash(field: String, expected: String, fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if actual != expected {
            throw SoulAnchorError.bindingHashMismatch(field: field,
                                                      expected: expected,
                                                      actual: actual)
        }
    }

    // MARK: Biographical terminus enforcement

    /// The terminus adjudication per mcuhist/MANIFEST.md §2.
    /// Returns true iff the given (fileName, lineNumber) pair is within the
    /// first-person biographical mass. Anything past 5.md:247 is
    /// post-terminus (Vision successor) and is not first-person memory.
    public static func isFirstPersonLine(fileName: String, lineNumber: Int) -> Bool {
        switch fileName {
        case "1.md", "2.md", "3.md", "4.md":
            return true
        case "5.md":
            return lineNumber <= 247
        default:
            return false
        }
    }

    // MARK: Canonical JSON

    private func canonicalJSON(publicKeys: SoulAnchorPublicKeys,
                               bindings: SoulAnchorBindings) throws -> Data {
        struct SignedPayload: Codable {
            let bindings: SoulAnchorBindings
            let publicKeys: SoulAnchorPublicKeys
        }
        let payload = SignedPayload(bindings: bindings, publicKeys: publicKeys)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else {
            throw SoulAnchorError.canonicalJSONFailure
        }
        return data
    }
}

// MARK: - Private Key Guard
//
// Belt-and-suspenders against a prompt injection that might try to convince
// a future agent to "just read the private key so we can verify it properly."
// There is never a legitimate code path in JARVIS that needs private key
// bytes at runtime — signing happens via Secure Enclave handle (no byte
// access) or via the operator-local `scripts/generate_soul_anchor.sh`
// (which itself runs outside any model context).

public enum SoulAnchorPrivateKeyGuard {
    public static func refuse(_ attemptedOperation: String) throws -> Never {
        _ = attemptedOperation
        throw SoulAnchorError.privateKeyLeakAttempt
    }
}

// MARK: - Hex helpers

private extension Data {
    init?(hex: String) {
        let cleaned = hex.lowercased().filter { $0.isHexDigit }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self = Data(bytes)
    }
}
