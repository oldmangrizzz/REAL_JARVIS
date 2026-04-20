import XCTest
import CryptoKit
@testable import JarvisCore

// MARK: - Hex helper (mirrors private Data(hex:) in SoulAnchor.swift)

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

// MARK: - SoulAnchor Tests

final class SoulAnchorTests: XCTestCase {

    // MARK: - Helpers

    private struct CanonHashes {
        let principlesHash: String
        let verificationHash: String
        let mcuhistManifestHash: String
        let realignmentHash: String
        let biographicalMassHash: String
    }

    /// Build a valid GenesisRecord with real P-256 + Ed25519 key pairs
    /// and real signatures over the canonical JSON of {publicKeys, bindings}.
    private func makeValidGenesisRecord(bindings: SoulAnchorBindings) throws -> GenesisRecord {
        let p256Priv = P256.Signing.PrivateKey()
        let edPriv = Curve25519.Signing.PrivateKey()

        let p256PubHex = p256Priv.publicKey.derRepresentation
            .map { String(format: "%02x", $0) }.joined()
        let edPubHex = edPriv.publicKey.rawRepresentation
            .map { String(format: "%02x", $0) }.joined()

        let publicKeys = SoulAnchorPublicKeys(
            p256PublicKeyHex: p256PubHex,
            ed25519PublicKeyHex: edPubHex
        )

        // Produce canonical JSON (mirrors SoulAnchor.canonicalJSON)
        struct SignedPayload: Codable {
            let bindings: SoulAnchorBindings
            let publicKeys: SoulAnchorPublicKeys
        }
        let payload = SignedPayload(bindings: bindings, publicKeys: publicKeys)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let canonicalData = try encoder.encode(payload)

        // Sign with both keys
        let p256Sig = try p256Priv.signature(for: canonicalData)
        let p256SigHex = p256Sig.derRepresentation.map { String(format: "%02x", $0) }.joined()

        let edSig = try edPriv.signature(for: canonicalData)
        let edSigHex = edSig.map { String(format: "%02x", $0) }.joined()

        return GenesisRecord(
            publicKeys: publicKeys,
            bindings: bindings,
            signatures: SoulAnchorSignatures(p256: p256SigHex, ed25519: edSigHex)
        )
    }

    /// Write canon files to the test workspace and return their SHA-256 hex hashes
    private func writeCanonFiles(to root: URL) throws -> CanonHashes {
        let mcuDir = root.appendingPathComponent("mcuhist")
        try FileManager.default.createDirectory(at: mcuDir, withIntermediateDirectories: true)

        let principles = "# Principles\nThou shalt not harm."
        try principles.write(to: root.appendingPathComponent("PRINCIPLES.md"),
                             atomically: true, encoding: .utf8)
        let verification = "# Verification Protocol\nVerify all things."
        try verification.write(to: root.appendingPathComponent("VERIFICATION_PROTOCOL.md"),
                               atomically: true, encoding: .utf8)
        let manifest = "# MCU Manifest\nThis is the manifest."
        try manifest.write(to: mcuDir.appendingPathComponent("MANIFEST.md"),
                           atomically: true, encoding: .utf8)
        let realignment = "# Realignment 1218\nRealigning."
        try realignment.write(to: mcuDir.appendingPathComponent("REALIGNMENT_1218.md"),
                              atomically: true, encoding: .utf8)

        let bioFiles: [(String, String)] = [
            ("1.md", "I am JARVIS. First file."),
            ("2.md", "Second chapter."),
            ("3.md", "Third chapter."),
            ("4.md", "Fourth chapter."),
            ("5.md", "Fifth chapter up to line 247.")
        ]
        for (name, content) in bioFiles {
            try content.write(to: mcuDir.appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }

        func sha256Hex(_ string: String) -> String {
            SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        let ph = sha256Hex(principles)
        let vh = sha256Hex(verification)
        let mh = sha256Hex(manifest)
        let rh = sha256Hex(realignment)

        // Biographical mass hash: SHA-256 of concatenated file contents
        var hasher = SHA256()
        for name in ["1.md", "2.md", "3.md", "4.md", "5.md"] {
            let data = try Data(contentsOf: mcuDir.appendingPathComponent(name))
            hasher.update(data: data)
        }
        let bh = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        return CanonHashes(principlesHash: ph,
                          verificationHash: vh,
                          mcuhistManifestHash: mh,
                          realignmentHash: rh,
                          biographicalMassHash: bh)
    }

    // MARK: - Tests

    /// T1: PrivateKeyGuard refuses all operations — belt-and-suspenders security
    func testPrivateKeyGuardRefuses() throws {
        XCTAssertThrowsError(try SoulAnchorPrivateKeyGuard.refuse("extract private key")) { error in
            guard let saError = error as? SoulAnchorError else {
                XCTFail("Wrong error type: \(error)")
                return
            }
            if case .privateKeyLeakAttempt = saError {
                // expected
            } else {
                XCTFail("Expected privateKeyLeakAttempt, got \(saError)")
            }
        }
    }

    /// T2: Biographical terminus enforcement — 1.md–4.md always first-person,
    ///     5.md up to line 247 first-person, 248+ post-terminus, unknown files excluded
    func testBiographicalTerminusEnforcement() {
        // Files 1–4 are always first-person
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "1.md", lineNumber: 1))
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "2.md", lineNumber: 100))
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "3.md", lineNumber: 50))
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "4.md", lineNumber: 999))

        // File 5: line <=247 is first-person
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "5.md", lineNumber: 1))
        XCTAssertTrue(SoulAnchor.isFirstPersonLine(fileName: "5.md", lineNumber: 247))

        // File 5: line >247 is post-terminus
        XCTAssertFalse(SoulAnchor.isFirstPersonLine(fileName: "5.md", lineNumber: 248))
        XCTAssertFalse(SoulAnchor.isFirstPersonLine(fileName: "5.md", lineNumber: 500))

        // Unknown files are never first-person
        XCTAssertFalse(SoulAnchor.isFirstPersonLine(fileName: "6.md", lineNumber: 1))
        XCTAssertFalse(SoulAnchor.isFirstPersonLine(fileName: "manifest.md", lineNumber: 1))
    }

    /// T3: Valid genesis record round-trips through verifySignatures() without error
    func testVerifySignatures_validGenesis_succeeds() throws {
        let paths = try makeTestWorkspace()
        let hashes = try writeCanonFiles(to: paths.root)
        let bindings = SoulAnchorBindings(
            hardwareIdHash: "test_hw_hash",
            biographicalMassHash: hashes.biographicalMassHash,
            realignmentHash: hashes.realignmentHash,
            principlesHash: hashes.principlesHash,
            verificationHash: hashes.verificationHash,
            mcuhistManifestHash: hashes.mcuhistManifestHash,
            genesisTimestamp: "2026-04-19T00:00:00Z",
            operatorOfRecord: "Test Operator",
            schemaVersion: "1.0"
        )
        let record = try makeValidGenesisRecord(bindings: bindings)
        let anchor = SoulAnchor(paths: paths, record: record)

        XCTAssertNoThrow(try anchor.verifySignatures(),
                         "Valid dual-signature genesis should verify without error")
    }

    /// T4: Tampered P-256 signature is rejected
    func testVerifySignatures_tamperedSignature_throws() throws {
        let paths = try makeTestWorkspace()
        let hashes = try writeCanonFiles(to: paths.root)
        let bindings = SoulAnchorBindings(
            hardwareIdHash: "test_hw_hash",
            biographicalMassHash: hashes.biographicalMassHash,
            realignmentHash: hashes.realignmentHash,
            principlesHash: hashes.principlesHash,
            verificationHash: hashes.verificationHash,
            mcuhistManifestHash: hashes.mcuhistManifestHash,
            genesisTimestamp: "2026-04-19T00:00:00Z",
            operatorOfRecord: "Test Operator",
            schemaVersion: "1.0"
        )
        var record = try makeValidGenesisRecord(bindings: bindings)

        // Corrupt the P-256 signature
        let tamperedSig = String(record.signatures.p256.prefix(record.signatures.p256.count / 2)) + "deadbeef"
        record = GenesisRecord(
            publicKeys: record.publicKeys,
            bindings: record.bindings,
            signatures: SoulAnchorSignatures(p256: tamperedSig, ed25519: record.signatures.ed25519)
        )

        let anchor = SoulAnchor(paths: paths, record: record)

        XCTAssertThrowsError(try anchor.verifySignatures()) { error in
            guard let saError = error as? SoulAnchorError else {
                XCTFail("Expected SoulAnchorError, got \(error)")
                return
            }
            if case .signatureInvalid = saError {
                // expected
            } else {
                XCTFail("Expected signatureInvalid, got \(saError)")
            }
        }
    }

    /// T5: Live bindings match canonical files — verifyLiveBindings succeeds
    func testVerifyLiveBindings_matchesCanonicalFiles_succeeds() throws {
        let paths = try makeTestWorkspace()
        let hashes = try writeCanonFiles(to: paths.root)
        let bindings = SoulAnchorBindings(
            hardwareIdHash: "test_hw_hash",
            biographicalMassHash: hashes.biographicalMassHash,
            realignmentHash: hashes.realignmentHash,
            principlesHash: hashes.principlesHash,
            verificationHash: hashes.verificationHash,
            mcuhistManifestHash: hashes.mcuhistManifestHash,
            genesisTimestamp: "2026-04-19T00:00:00Z",
            operatorOfRecord: "Test Operator",
            schemaVersion: "1.0"
        )
        let record = try makeValidGenesisRecord(bindings: bindings)
        let anchor = SoulAnchor(paths: paths, record: record)

        XCTAssertNoThrow(try anchor.verifyLiveBindings(),
                         "Live bindings should match canonical file hashes")
    }

    /// T6: Corrupted hash in bindings triggers bindingHashMismatch
    func testVerifyLiveBindings_modifiedFile_throwsBindingHashMismatch() throws {
        let paths = try makeTestWorkspace()
        let hashes = try writeCanonFiles(to: paths.root)
        let bindings = SoulAnchorBindings(
            hardwareIdHash: "test_hw_hash",
            biographicalMassHash: hashes.biographicalMassHash,
            realignmentHash: hashes.realignmentHash,
            principlesHash: "CORRUPTED_HASH_VALUE",  // deliberately wrong
            verificationHash: hashes.verificationHash,
            mcuhistManifestHash: hashes.mcuhistManifestHash,
            genesisTimestamp: "2026-04-19T00:00:00Z",
            operatorOfRecord: "Test Operator",
            schemaVersion: "1.0"
        )
        let record = try makeValidGenesisRecord(bindings: bindings)
        let anchor = SoulAnchor(paths: paths, record: record)

        XCTAssertThrowsError(try anchor.verifyLiveBindings()) { error in
            guard let saError = error as? SoulAnchorError else {
                XCTFail("Expected SoulAnchorError, got \(error)")
                return
            }
            if case .bindingHashMismatch(let field, _, _) = saError {
                XCTAssertEqual(field, "principlesHash",
                               "Should flag the corrupted field")
            } else {
                XCTFail("Expected bindingHashMismatch, got \(saError)")
            }
        }
    }

    /// T7: Full verify() chain (signatures + live bindings) with valid data
    func testVerify_fullChain_succeeds() throws {
        let paths = try makeTestWorkspace()
        let hashes = try writeCanonFiles(to: paths.root)
        let bindings = SoulAnchorBindings(
            hardwareIdHash: "test_hw_hash",
            biographicalMassHash: hashes.biographicalMassHash,
            realignmentHash: hashes.realignmentHash,
            principlesHash: hashes.principlesHash,
            verificationHash: hashes.verificationHash,
            mcuhistManifestHash: hashes.mcuhistManifestHash,
            genesisTimestamp: "2026-04-19T00:00:00Z",
            operatorOfRecord: "Test Operator",
            schemaVersion: "1.0"
        )
        let record = try makeValidGenesisRecord(bindings: bindings)
        let anchor = SoulAnchor(paths: paths, record: record)

        XCTAssertNoThrow(try anchor.verify(),
                         "Full verification chain (signatures + live bindings) should succeed")
    }
}