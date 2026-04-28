import Foundation
import CryptoKit

// MARK: - Soul Anchor
//
// The cryptographic root of JARVIS's identity, per SOUL_ANCHOR.md.
// Holds ONLY public verifier material. Private keys live outside runtime:
// P-256 in Secure Enclave / operator-controlled storage, and Ed25519 on the
// operator's cold medium. Private bytes never transit this process.

public struct SoulAnchorPublicKeys: Codable, Sendable, Equatable {
    public let p256PublicKeyHex: String
    public let ed25519PublicKeyHex: String

    public var p256Fingerprint: String { Self.sha256Hex(hex: p256PublicKeyHex) }
    public var ed25519Fingerprint: String { Self.sha256Hex(hex: ed25519PublicKeyHex) }

    private static func sha256Hex(hex: String) -> String {
        let bytes = Data(hex: hex) ?? Data()
        return SHA256.hash(data: bytes).hexString
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
    public let p256: String
    public let ed25519: String
}

public struct GenesisRecord: Codable, Sendable, Equatable {
    public let publicKeys: SoulAnchorPublicKeys
    public let bindings: SoulAnchorBindings
    public let signatures: SoulAnchorSignatures
}

public struct RatifiedSoulAnchorGenesis: Codable, Sendable, Equatable {
    public let version: String
    public let ratifiedUTC: String?
    public let operatorRecord: SoulAnchorOperatorRecord?
    public let canon: [String: String]
    public let signingPacketSHA256: String
    public let signingPacketFile: String?
    public let keys: SoulAnchorKeySet
    public let status: String

    enum CodingKeys: String, CodingKey {
        case version
        case ratifiedUTC = "ratified_utc"
        case operatorRecord = "operator"
        case canon
        case signingPacketSHA256 = "signing_packet_sha256"
        case signingPacketFile = "signing_packet_file"
        case keys
        case status
    }
}

public struct SoulAnchorOperatorRecord: Codable, Sendable, Equatable {
    public let legalName: String?
    public let callsign: String?
    public let credentials: String?

    enum CodingKeys: String, CodingKey {
        case legalName = "legal_name"
        case callsign
        case credentials
    }
}

public struct SoulAnchorKeySet: Codable, Sendable, Equatable {
    public let ed25519ColdRoot: SoulAnchorKeyRecord?
    public let p256Operational: SoulAnchorKeyRecord?

    enum CodingKeys: String, CodingKey {
        case ed25519ColdRoot = "ed25519_cold_root"
        case p256Operational = "p256_operational"
    }
}

public struct SoulAnchorKeyRecord: Codable, Sendable, Equatable {
    public let pubkeySHA256Fingerprint: String
    public let privateLocation: String?
    public let handleFile: String?
    public let signatureFile: String
    public let signatureSHA256: String?
    public let signatureFormat: String
    public let verifyIdentity: String?

    enum CodingKeys: String, CodingKey {
        case pubkeySHA256Fingerprint = "pubkey_sha256_fingerprint"
        case privateLocation = "private_location"
        case handleFile = "handle_file"
        case signatureFile = "signature_file"
        case signatureSHA256 = "signature_sha256"
        case signatureFormat = "signature_format"
        case verifyIdentity = "verify_identity"
    }
}

public enum SoulAnchorError: Error, CustomStringConvertible {
    case missingPublicKey(String)
    case missingGenesisRecord(URL)
    case missingSigningPacket(URL)
    case missingSignature(URL)
    case invalidGenesisStatus(String)
    case signingPacketHashMismatch(expected: String, actual: String)
    case keyFingerprintMismatch(field: String, expected: String, actual: String)
    case signatureHashMismatch(field: String, expected: String, actual: String)
    case unsupportedCanonBinding(String)
    case unsupportedSignatureFormat(String)
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
        case let .missingSigningPacket(url):
            return "Soul Anchor signing packet missing at \(url.path)."
        case let .missingSignature(url):
            return "Soul Anchor signature missing at \(url.path)."
        case let .invalidGenesisStatus(status):
            return "Soul Anchor genesis status is not RATIFIED: \(status)."
        case let .signingPacketHashMismatch(expected, actual):
            return "Soul Anchor signing packet hash mismatch: expected \(expected), got \(actual)."
        case let .keyFingerprintMismatch(field, expected, actual):
            return "Soul Anchor key fingerprint drift on \(field): expected \(expected), got \(actual)."
        case let .signatureHashMismatch(field, expected, actual):
            return "Soul Anchor signature hash drift on \(field): expected \(expected), got \(actual)."
        case let .unsupportedCanonBinding(name):
            return "Soul Anchor canon binding is not runtime-verifiable: \(name)."
        case let .unsupportedSignatureFormat(format):
            return "Soul Anchor signature format is unsupported: \(format)."
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
    public let record: GenesisRecord?
    public let ratifiedRecord: RatifiedSoulAnchorGenesis?

    public init(paths: WorkspacePaths, record: GenesisRecord) {
        self.paths = paths
        self.record = record
        self.ratifiedRecord = nil
    }

    public init(paths: WorkspacePaths, ratifiedRecord: RatifiedSoulAnchorGenesis) {
        self.paths = paths
        self.record = nil
        self.ratifiedRecord = ratifiedRecord
    }

    public static func load(paths: WorkspacePaths) throws -> SoulAnchor {
        let genesisURL = paths.root
            .appendingPathComponent(".jarvis", isDirectory: true)
            .appendingPathComponent("soul_anchor", isDirectory: true)
            .appendingPathComponent("genesis.json")
        guard FileManager.default.fileExists(atPath: genesisURL.path) else {
            throw SoulAnchorError.missingGenesisRecord(genesisURL)
        }

        let data = try Data(contentsOf: genesisURL)
        let decoder = JSONDecoder()
        if let record = try? decoder.decode(GenesisRecord.self, from: data) {
            return SoulAnchor(paths: paths, record: record)
        }
        let ratified = try decoder.decode(RatifiedSoulAnchorGenesis.self, from: data)
        return SoulAnchor(paths: paths, ratifiedRecord: ratified)
    }

    public func verify() throws {
        if let record {
            try verifyEmbeddedSignatures(record)
            try verifyEmbeddedLiveBindings(record)
            return
        }
        if let ratifiedRecord {
            try verifyRatifiedGenesis(ratifiedRecord)
            return
        }
        throw SoulAnchorError.canonicalJSONFailure
    }

    public func verifySignatures() throws {
        if let record {
            try verifyEmbeddedSignatures(record)
            return
        }
        if let ratifiedRecord {
            let packet = try loadSigningPacket(for: ratifiedRecord)
            try verifyRatifiedSignatures(ratifiedRecord, signingPacket: packet)
            return
        }
        throw SoulAnchorError.canonicalJSONFailure
    }

    public func verifyLiveBindings() throws {
        if let record {
            try verifyEmbeddedLiveBindings(record)
            return
        }
        if let ratifiedRecord {
            try verifyCanonBindings(ratifiedRecord.canon)
            return
        }
        throw SoulAnchorError.canonicalJSONFailure
    }

    private func verifyEmbeddedSignatures(_ record: GenesisRecord) throws {
        let canonical = try canonicalJSON(publicKeys: record.publicKeys, bindings: record.bindings)

        guard let p256KeyData = Data(hex: record.publicKeys.p256PublicKeyHex) else {
            throw SoulAnchorError.missingPublicKey("p256")
        }
        let p256Key = try P256.Signing.PublicKey(derRepresentation: p256KeyData)
        guard let p256SigData = Data(hex: record.signatures.p256),
              let p256Sig = try? P256.Signing.ECDSASignature(derRepresentation: p256SigData),
              p256Key.isValidSignature(p256Sig, for: canonical) else {
            throw SoulAnchorError.signatureInvalid(curve: "P-256")
        }

        guard let edKeyData = Data(hex: record.publicKeys.ed25519PublicKeyHex) else {
            throw SoulAnchorError.missingPublicKey("ed25519")
        }
        let edKey = try Curve25519.Signing.PublicKey(rawRepresentation: edKeyData)
        guard let edSigData = Data(hex: record.signatures.ed25519),
              edKey.isValidSignature(edSigData, for: canonical) else {
            throw SoulAnchorError.signatureInvalid(curve: "Ed25519")
        }
    }

    private func verifyEmbeddedLiveBindings(_ record: GenesisRecord) throws {
        try compareHash(field: "principlesHash",
                        expected: record.bindings.principlesHash,
                        actual: fileHash("PRINCIPLES.md"))
        try compareHash(field: "verificationHash",
                        expected: record.bindings.verificationHash,
                        actual: fileHash("VERIFICATION_PROTOCOL.md"))
        try compareHash(field: "mcuhistManifestHash",
                        expected: record.bindings.mcuhistManifestHash,
                        actual: fileHash("mcuhist/MANIFEST.md"))
        try compareHash(field: "realignmentHash",
                        expected: record.bindings.realignmentHash,
                        actual: fileHash("mcuhist/REALIGNMENT_1218.md"))
        try compareHash(field: "biographicalMassHash",
                        expected: record.bindings.biographicalMassHash,
                        actual: try biographicalMassHash())
    }

    private func verifyRatifiedGenesis(_ genesis: RatifiedSoulAnchorGenesis) throws {
        guard genesis.status.uppercased() == "RATIFIED" else {
            throw SoulAnchorError.invalidGenesisStatus(genesis.status)
        }
        let packet = try loadSigningPacket(for: genesis)
        let actualPacketHash = SHA256.hash(data: packet).hexString
        if actualPacketHash != genesis.signingPacketSHA256.lowercased() {
            throw SoulAnchorError.signingPacketHashMismatch(
                expected: genesis.signingPacketSHA256.lowercased(),
                actual: actualPacketHash
            )
        }
        try verifyRatifiedPublicKeyFingerprints(genesis)
        try verifyRatifiedSignatures(genesis, signingPacket: packet)
        try verifyCanonBindings(genesis.canon)
    }

    private func loadSigningPacket(for genesis: RatifiedSoulAnchorGenesis) throws -> Data {
        let packetPath = genesis.signingPacketFile ?? ".jarvis/soul_anchor/signing/canon_genesis.txt"
        let url = resolveRootRelative(packetPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoulAnchorError.missingSigningPacket(url)
        }
        return try Data(contentsOf: url)
    }

    private func verifyRatifiedPublicKeyFingerprints(_ genesis: RatifiedSoulAnchorGenesis) throws {
        if let p256 = genesis.keys.p256Operational {
            let actual = try SHA256.hash(data: Data(contentsOf: p256PublicKeyURL())).hexString
            try compareFingerprint(field: "p256_operational", expected: p256.pubkeySHA256Fingerprint, actual: actual)
        }
        if let ed = genesis.keys.ed25519ColdRoot {
            let actual = try SHA256.hash(data: Data(contentsOf: ed25519RawPublicKeyURL())).hexString
            try compareFingerprint(field: "ed25519_cold_root", expected: ed.pubkeySHA256Fingerprint, actual: actual)
        }
    }

    private func verifyRatifiedSignatures(_ genesis: RatifiedSoulAnchorGenesis, signingPacket: Data) throws {
        guard let p256 = genesis.keys.p256Operational else {
            throw SoulAnchorError.missingPublicKey("p256_operational")
        }
        guard let ed = genesis.keys.ed25519ColdRoot else {
            throw SoulAnchorError.missingPublicKey("ed25519_cold_root")
        }

        try verifySignatureFileHash(p256, field: "p256_operational")
        try verifySignatureFileHash(ed, field: "ed25519_cold_root")
        try verifyP256Signature(signatureURL: resolveRootRelative(p256.signatureFile), signingPacket: signingPacket)
        try verifyEd25519Signature(ed, signingPacket: signingPacket)
    }

    private func verifySignatureFileHash(_ key: SoulAnchorKeyRecord, field: String) throws {
        guard let expected = key.signatureSHA256?.lowercased(), !expected.isEmpty else { return }
        let url = resolveRootRelative(key.signatureFile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoulAnchorError.missingSignature(url)
        }
        let actual = try SHA256.hash(data: Data(contentsOf: url)).hexString
        if actual != expected {
            throw SoulAnchorError.signatureHashMismatch(field: field, expected: expected, actual: actual)
        }
    }

    private func verifyP256Signature(signatureURL: URL, signingPacket: Data) throws {
        guard FileManager.default.fileExists(atPath: signatureURL.path) else {
            throw SoulAnchorError.missingSignature(signatureURL)
        }
        let key = try P256.Signing.PublicKey(derRepresentation: Data(contentsOf: p256PublicKeyURL()))
        let signatureData = try Data(contentsOf: signatureURL)
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              key.isValidSignature(signature, for: signingPacket) else {
            throw SoulAnchorError.signatureInvalid(curve: "P-256")
        }
    }

    private func verifyEd25519Signature(_ key: SoulAnchorKeyRecord, signingPacket: Data) throws {
        let signatureURL = resolveRootRelative(key.signatureFile)
        guard FileManager.default.fileExists(atPath: signatureURL.path) else {
            throw SoulAnchorError.missingSignature(signatureURL)
        }
        let format = key.signatureFormat.lowercased()
        if format.contains("sshsig") {
            try verifySSHSignature(
                signatureURL: signatureURL,
                identity: key.verifyIdentity ?? "grizz@gmri",
                namespace: "jarvis-soul-anchor",
                signingPacket: signingPacket
            )
            return
        }
        if format.contains("raw") || format.contains("ed25519") {
            let edKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(contentsOf: ed25519RawPublicKeyURL()))
            let signature = try Data(contentsOf: signatureURL)
            guard edKey.isValidSignature(signature, for: signingPacket) else {
                throw SoulAnchorError.signatureInvalid(curve: "Ed25519")
            }
            return
        }
        throw SoulAnchorError.unsupportedSignatureFormat(key.signatureFormat)
    }

    private func verifySSHSignature(signatureURL: URL, identity: String, namespace: String, signingPacket: Data) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-Y", "verify",
            "-f", allowedSignersURL().path,
            "-I", identity,
            "-n", namespace,
            "-s", signatureURL.path
        ]
        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(signingPacket)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SoulAnchorError.signatureInvalid(curve: "Ed25519 SSHSIG")
        }
    }

    private func verifyCanonBindings(_ canon: [String: String]) throws {
        for (field, expected) in canon {
            let actual = try liveCanonHash(for: field)
            try compareHash(field: field, expected: expected, actual: actual)
        }
    }

    private func liveCanonHash(for field: String) throws -> String {
        switch field {
        case "PRINCIPLES.md":
            return try fileHash("PRINCIPLES.md")
        case "VERIFICATION_PROTOCOL.md":
            return try fileHash("VERIFICATION_PROTOCOL.md")
        case "SOUL_ANCHOR.md":
            return try fileHash("SOUL_ANCHOR.md")
        case "MANIFEST.md", "mcuhist/MANIFEST.md":
            return try fileHash("mcuhist/MANIFEST.md")
        case "REALIGNMENT_1218.md", "mcuhist/REALIGNMENT_1218.md":
            return try fileHash("mcuhist/REALIGNMENT_1218.md")
        case "biographical_mass_hash", "biographical_mass":
            return try biographicalMassHash()
        case "aragorn_class_designation":
            return try aragornClassDesignationHash()
        default:
            throw SoulAnchorError.unsupportedCanonBinding(field)
        }
    }

    private func fileHash(_ relativePath: String) throws -> String {
        let data = try Data(contentsOf: paths.root.appendingPathComponent(relativePath))
        return SHA256.hash(data: data).hexString
    }

    private func biographicalMassHash() throws -> String {
        let mcuRoot = paths.root.appendingPathComponent("mcuhist", isDirectory: true)
        var hasher = SHA256()
        for name in ["1.md", "2.md", "3.md", "4.md", "5.md"] {
            let data = try Data(contentsOf: mcuRoot.appendingPathComponent(name))
            hasher.update(data: data)
        }
        return hasher.finalize().hexString
    }

    private func aragornClassDesignationHash() throws -> String {
        let text = try String(contentsOf: paths.root.appendingPathComponent("SOUL_ANCHOR.md"), encoding: .utf8)
        guard let start = text.range(of: "## 8. Identity Lineage & Aragorn Class Binding") else {
            throw SoulAnchorError.unsupportedCanonBinding("aragorn_class_designation")
        }
        let tail = text[start.lowerBound...]
        let section: String
        if let end = tail.range(of: "\n---", range: tail.index(after: start.lowerBound)..<tail.endIndex) {
            section = String(tail[..<end.lowerBound])
        } else {
            section = String(tail)
        }
        struct SectionPayload: Codable {
            let section8Markdown: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(SectionPayload(section8Markdown: section.trimmingCharacters(in: .whitespacesAndNewlines)))
        return SHA256.hash(data: data).hexString
    }

    private func compareHash(field: String, expected: String, actual: String) throws {
        let normalizedExpected = expected.lowercased()
        if actual != normalizedExpected {
            throw SoulAnchorError.bindingHashMismatch(field: field, expected: normalizedExpected, actual: actual)
        }
    }

    private func compareFingerprint(field: String, expected: String, actual: String) throws {
        let normalizedExpected = expected.lowercased()
        if actual != normalizedExpected {
            throw SoulAnchorError.keyFingerprintMismatch(field: field, expected: normalizedExpected, actual: actual)
        }
    }

    private func canonicalJSON(publicKeys: SoulAnchorPublicKeys, bindings: SoulAnchorBindings) throws -> Data {
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

    private func resolveRootRelative(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        return path.hasPrefix("/") ? url : paths.root.appendingPathComponent(path)
    }

    private func p256PublicKeyURL() -> URL {
        paths.root.appendingPathComponent("Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/p256.pub.der")
    }

    private func ed25519RawPublicKeyURL() -> URL {
        paths.root.appendingPathComponent("Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/ed25519.pub.raw")
    }

    private func allowedSignersURL() -> URL {
        paths.root.appendingPathComponent("Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/allowed_signers")
    }

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
}

public enum SoulAnchorPrivateKeyGuard {
    public static func refuse(_ attemptedOperation: String) throws -> Never {
        _ = attemptedOperation
        throw SoulAnchorError.privateKeyLeakAttempt
    }
}

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

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
