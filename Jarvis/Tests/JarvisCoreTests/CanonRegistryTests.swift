import XCTest
@testable import JarvisCore

final class CanonRegistryTests: XCTestCase {

    /// Absolute path to the live repo root so we hash the real CANON/corpus/.
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JarvisCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Jarvis
            .deletingLastPathComponent() // REAL_JARVIS
    }

    func testRegistryIsNonEmptyAndWellFormed() {
        XCTAssertFalse(CanonRegistry.documents.isEmpty)
        for doc in CanonRegistry.documents {
            XCTAssertFalse(doc.id.isEmpty, "Document has empty id")
            XCTAssertFalse(doc.filename.isEmpty, "Document \(doc.id) has empty filename")
            XCTAssertFalse(doc.title.isEmpty, "Document \(doc.id) has empty title")
            XCTAssertFalse(doc.author.isEmpty, "Document \(doc.id) has empty author")
            XCTAssertEqual(doc.expectedSha256.count, 64, "Document \(doc.id) has non-SHA-256 hash")
            XCTAssertTrue(doc.expectedSha256.allSatisfy { $0.isHexDigit }, "Document \(doc.id) has non-hex hash")
        }
    }

    func testAllIdsAreUnique() {
        let ids = CanonRegistry.documents.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate canon ids detected")
    }

    func testAllFilenamesAreUnique() {
        let names = CanonRegistry.documents.map(\.filename)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate canon filenames detected")
    }

    func testAllHashesAreUnique() {
        let hashes = CanonRegistry.documents.map(\.expectedSha256)
        XCTAssertEqual(Set(hashes).count, hashes.count, "Duplicate expected hashes detected")
    }

    func testLookupById() {
        XCTAssertNotNil(CanonRegistry.document(id: CanonID.dphPaper3AragonSpec))
        XCTAssertNotNil(CanonRegistry.document(id: CanonID.zordTheory))
        XCTAssertNotNil(CanonRegistry.document(id: CanonID.companionOSIntegration))
        XCTAssertNil(CanonRegistry.document(id: "nonexistent-document"))
    }

    func testLookupByRole() {
        let specs = CanonRegistry.documents(withRole: .architectureSpec)
        XCTAssertTrue(specs.contains { $0.id == CanonID.dphPaper3AragonSpec })
        XCTAssertTrue(specs.contains { $0.id == CanonID.digitalPersonBlueprint })
        XCTAssertTrue(specs.contains { $0.id == CanonID.companionOSIntegration })
    }

    func testLookupByTag() {
        let aox = CanonRegistry.documents(taggedWith: "aox4")
        XCTAssertTrue(aox.contains { $0.id == CanonID.dphPaper3AragonSpec })
        XCTAssertTrue(aox.contains { $0.id == CanonID.murdockBrief })
    }

    func testWellKnownIDsMatchRegistry() {
        let mirror = Mirror(reflecting: CanonID.self)
        // CanonID is a caseless enum; use explicit list instead.
        let knownIDs: [String] = [
            CanonID.welcomeToGrizzlyMedicine,
            CanonID.grizzlyMedicineSep2025,
            CanonID.founderBiography,
            CanonID.yesterdaysProblems,
            CanonID.zordTheory,
            CanonID.digitalPersonBlueprint,
            CanonID.digitalPersonLLMsAsCNS,
            CanonID.digitalPersonHypothesisReadme,
            CanonID.dphPaper1Problem,
            CanonID.dphPaper2Foxhole,
            CanonID.dphPaper3AragonSpec,
            CanonID.companionOSIntegration,
            CanonID.murdockBrief,
            CanonID.aiAntitrustEssentialFacilities,
            CanonID.aiDiscriminationResearchObstruction,
            CanonID.anthropicConsumerProtectionAccessibility,
            CanonID.digitalSubscriptionLegalResearch,
            CanonID.googleDeveloperProgram,
        ]
        _ = mirror
        for id in knownIDs {
            XCTAssertNotNil(CanonRegistry.document(id: id), "CanonID constant '\(id)' not present in registry")
        }
        XCTAssertEqual(Set(knownIDs).count, knownIDs.count)
    }

    // MARK: - Live corpus verification
    //
    // These tests hash the actual files at <repo>/CANON/corpus/ and
    // confirm they match the hashes frozen into the registry at build time.

    func testLiveCorpusDirectoryExists() {
        let corpus = repoRoot().appendingPathComponent("CANON/corpus", isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: corpus.path, isDirectory: &isDir),
            "CANON/corpus directory missing at \(corpus.path)"
        )
        XCTAssertTrue(isDir.boolValue)
    }

    func testLiveCorpusHashesMatchRegistry() throws {
        let report = try CanonRegistry.verifyCorpus(repoRoot: repoRoot())
        XCTAssertTrue(
            report.isClean,
            """
            Canon drift detected.
            Missing: \(report.missing)
            Drifted: \(report.drifted.map { "\($0.id) expected=\($0.expected) observed=\($0.observed)" })
            """
        )
        XCTAssertEqual(report.verified.count, CanonRegistry.documents.count)
    }

    func testRequireCleanCorpusDoesNotThrow() {
        XCTAssertNoThrow(try CanonRegistry.requireCleanCorpus(repoRoot: repoRoot()))
    }

    func testLoadVerifiedReturnsMatchingDocument() throws {
        let (doc, data) = try CanonRegistry.loadVerified(id: CanonID.dphPaper3AragonSpec, repoRoot: repoRoot())
        XCTAssertEqual(doc.id, CanonID.dphPaper3AragonSpec)
        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Negative tests using a synthetic corpus

    func testVerifyCorpusDetectsMissingFiles() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("canon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent("CANON/corpus"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratch) }

        let report = try CanonRegistry.verifyCorpus(repoRoot: scratch)
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.missing.count, CanonRegistry.documents.count)
        XCTAssertTrue(report.verified.isEmpty)
    }

    func testVerifyCorpusDetectsDrift() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("canon-test-\(UUID().uuidString)", isDirectory: true)
        let corpus = scratch.appendingPathComponent("CANON/corpus", isDirectory: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Write a file with intentionally wrong contents for every canon doc.
        for doc in CanonRegistry.documents {
            let url = corpus.appendingPathComponent(doc.filename)
            try Data("DRIFT".utf8).write(to: url)
        }

        let report = try CanonRegistry.verifyCorpus(repoRoot: scratch)
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.drifted.count, CanonRegistry.documents.count)
        XCTAssertTrue(report.missing.isEmpty)
        XCTAssertTrue(report.verified.isEmpty)

        XCTAssertThrowsError(try CanonRegistry.requireCleanCorpus(repoRoot: scratch))
    }

    func testVerifyCorpusThrowsWhenCorpusDirectoryMissing() {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("canon-test-\(UUID().uuidString)", isDirectory: true)
        // Do not create CANON/corpus.
        XCTAssertThrowsError(try CanonRegistry.verifyCorpus(repoRoot: scratch)) { error in
            guard let canonError = error as? CanonError else {
                XCTFail("Expected CanonError, got \(error)")
                return
            }
            if case .corpusMissing = canonError { /* ok */ } else {
                XCTFail("Expected .corpusMissing, got \(canonError)")
            }
        }
    }

    func testSha256OfKnownData() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("canon-hash-\(UUID().uuidString).txt")
        try Data("hello\n".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hash = try CanonRegistry.sha256(of: tmp)
        // sha256("hello\n") = 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
        XCTAssertEqual(hash, "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
    }
}
