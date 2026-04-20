import XCTest
@testable import JarvisCore

/// SPEC-009 diarization spine. These tests lock in the contract before
/// voice-enrollment ships the real ML extractor, so a future refactor
/// can swap implementations without silently changing behaviour.
final class SpeakerIdentifierTests: XCTestCase {

    func testNullIdentifierAlwaysReturnsNil() throws {
        let id = NullSpeakerIdentifier()
        XCTAssertNil(try id.identify(audio: Data([0x00, 0x01])))
        XCTAssertNil(try id.identify(embedding: [0.1, 0.2, 0.3]))
    }

    func testEnrollmentIdentityIncludesPrincipalToken() {
        let enrollment = SpeakerEnrollment(
            principal: .companion(memberID: "wife"),
            embedding: [0.1, 0.2, 0.3],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            promptTexts: ["hi jarvis this is wife", "another neutral sentence"]
        )
        XCTAssertEqual(enrollment.principalToken, "companion:wife")
        XCTAssertEqual(enrollment.promptHashes.count, 2)
        XCTAssertFalse(enrollment.enrollmentID.isEmpty)
    }

    func testInMemoryStoreReplacesOnReEnrollment() throws {
        let store = InMemorySpeakerEnrollmentStore()
        try store.add(SpeakerEnrollment(principal: .companion(memberID: "wife"), embedding: [0.1, 0.2]))
        try store.add(SpeakerEnrollment(principal: .companion(memberID: "wife"), embedding: [0.3, 0.4]))
        let all = try store.enrollments()
        XCTAssertEqual(all.count, 1, "re-enrolling same principal should replace not duplicate")
        XCTAssertEqual(all.first?.embedding, [0.3, 0.4])
    }

    func testInMemoryStoreRemoveByPrincipal() throws {
        let store = InMemorySpeakerEnrollmentStore()
        try store.add(SpeakerEnrollment(principal: .operatorTier, embedding: [1, 0]))
        try store.add(SpeakerEnrollment(principal: .companion(memberID: "kid"), embedding: [0, 1]))
        try store.remove(principal: .operatorTier)
        let all = try store.enrollments()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.principalToken, "companion:kid")
    }

    func testCosineIdentifierMatchesAboveThreshold() throws {
        let store = InMemorySpeakerEnrollmentStore()
        // Two clearly orthogonal "voiceprints".
        try store.add(SpeakerEnrollment(principal: .operatorTier, embedding: [1, 0, 0, 0]))
        try store.add(SpeakerEnrollment(principal: .companion(memberID: "wife"), embedding: [0, 1, 0, 0]))
        let id = CosineSpeakerIdentifier(store: store, matchThreshold: 0.82)
        // Nearly-identical to operator embedding.
        XCTAssertEqual(try id.identify(embedding: [0.98, 0.01, 0.0, 0.0]), .operatorTier)
        // Nearly-identical to wife embedding.
        XCTAssertEqual(
            try id.identify(embedding: [0.0, 0.95, 0.1, 0.0]),
            .companion(memberID: "wife")
        )
    }

    func testCosineIdentifierReturnsNilBelowThreshold() throws {
        let store = InMemorySpeakerEnrollmentStore()
        try store.add(SpeakerEnrollment(principal: .operatorTier, embedding: [1, 0, 0, 0]))
        let id = CosineSpeakerIdentifier(store: store, matchThreshold: 0.9)
        // 45° off the enrolled vector — cosine ~0.707, below 0.9 threshold.
        XCTAssertNil(try id.identify(embedding: [1, 1, 0, 0]))
    }

    func testCosineIdentifierSkipsMismatchedEmbeddingDimensions() throws {
        let store = InMemorySpeakerEnrollmentStore()
        try store.add(SpeakerEnrollment(principal: .operatorTier, embedding: [1, 0, 0, 0]))
        let id = CosineSpeakerIdentifier(store: store)
        // Wrong dimensionality should be skipped, not crash.
        XCTAssertNil(try id.identify(embedding: [1, 0]))
    }

    func testCosineIdentifierAudioPathFailsClosedUntilExtractorLands() throws {
        // The raw-audio overload cannot produce embeddings without a
        // trained feature extractor. Until voice-enrollment ships one,
        // identify(audio:) must return nil, not guess.
        let store = InMemorySpeakerEnrollmentStore()
        try store.add(SpeakerEnrollment(principal: .operatorTier, embedding: [1, 0, 0, 0]))
        let id = CosineSpeakerIdentifier(store: store)
        XCTAssertNil(try id.identify(audio: Data([0x01, 0x02, 0x03])))
    }

    func testCosineSimilarityHandlesZeroAndEmpty() {
        XCTAssertEqual(CosineSpeakerIdentifier.cosineSimilarity([], []), 0)
        XCTAssertEqual(CosineSpeakerIdentifier.cosineSimilarity([0, 0, 0], [1, 0, 0]), 0)
    }
}
