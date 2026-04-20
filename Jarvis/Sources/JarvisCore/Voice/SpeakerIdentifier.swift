import Foundation
import CryptoKit

/// SPEC-009 diarization spine.
///
/// A `SpeakerIdentifier` answers: "whose voice is this?" — given either
/// an audio sample or a speaker embedding vector, it returns the
/// matching `Principal` if a voice-print match is found, or nil if the
/// speaker is unknown.
///
/// The actual embedding model (voice-clone / speaker-verification)
/// lives on the voice-enrollment ticket. This protocol exists now so
/// the router path, telemetry path, and onboarding path can all be
/// wired without waiting on ML capture code.
public protocol SpeakerIdentifier: Sendable {
    /// Match a sample of audio against enrolled voice prints.
    ///
    /// Returns `nil` on no match. Never returns an implicit fallback
    /// principal — the caller is responsible for whatever policy it
    /// wants to apply when the speaker is unknown (typically: keep the
    /// existing session principal, or drop to `.guestTier`).
    func identify(audio: Data) throws -> Principal?

    /// Match a pre-computed embedding vector (for callers that already
    /// ran the audio through a feature extractor).
    func identify(embedding: [Float]) throws -> Principal?
}

/// Default no-op identifier. Safe to wire into the router spine before
/// voice-enrollment lands — it always returns nil, meaning "no match",
/// which the router interprets as "keep the session principal." This
/// is the explicit, auditable fallback called out in RealJarvisInterface
/// line 517-521: we document the fact that console mic is treated as
/// operator tier until real diarization is in.
public struct NullSpeakerIdentifier: SpeakerIdentifier {
    public init() {}
    public func identify(audio: Data) throws -> Principal? { nil }
    public func identify(embedding: [Float]) throws -> Principal? { nil }
}

// MARK: - Speaker enrollment

/// A stored voice-print for a single family-tier or operator-tier
/// principal. The embedding itself is just a vector of floats — the
/// privacy sensitivity is LOW at the vector level (embeddings are not
/// invertible back to the raw audio with any known technique), but we
/// still hash the principal's tier token into the enrollment ID so
/// family-tier embeddings can't be silently re-bound to operator.
public struct SpeakerEnrollment: Codable, Equatable, Sendable {
    public let enrollmentID: String
    public let principalToken: String
    public let embedding: [Float]
    public let createdAtISO8601: String
    public let promptHashes: [String]

    public init(principal: Principal,
                embedding: [Float],
                createdAt: Date = Date(),
                promptTexts: [String] = []) {
        self.principalToken = principal.tierToken
        self.embedding = embedding
        let iso = ISO8601DateFormatter().string(from: createdAt)
        self.createdAtISO8601 = iso
        self.promptHashes = promptTexts.map { Self.sha256Hex(Data($0.utf8)) }
        let idBody = "\(principal.tierToken)|\(iso)|\(embedding.count)"
        self.enrollmentID = Self.sha256Hex(Data(idBody.utf8))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Protocol over the on-disk enrollment store. Voice-enrollment will
/// ship a Convex-backed implementation; tests use an in-memory stub.
public protocol SpeakerEnrollmentStore: Sendable {
    func enrollments() throws -> [SpeakerEnrollment]
    func add(_ enrollment: SpeakerEnrollment) throws
    func remove(principal: Principal) throws
}

/// In-memory, thread-safe enrollment store. Useful for tests and for
/// dev builds before the Convex-backed implementation lands.
public final class InMemorySpeakerEnrollmentStore: SpeakerEnrollmentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpeakerEnrollment] = []

    public init() {}

    public func enrollments() throws -> [SpeakerEnrollment] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public func add(_ enrollment: SpeakerEnrollment) throws {
        lock.lock(); defer { lock.unlock() }
        // One enrollment per principal token — re-enrolling replaces.
        storage.removeAll { $0.principalToken == enrollment.principalToken }
        storage.append(enrollment)
    }

    public func remove(principal: Principal) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.principalToken == principal.tierToken }
    }
}

/// Reference cosine-similarity matcher over an enrollment store. Takes
/// a "match threshold" (cosine similarity >= threshold counts as a
/// match). When voice-enrollment lands, a production identifier can
/// swap this for a trained speaker-verification model; this one is
/// the deterministic baseline used in tests and as a fallback.
public struct CosineSpeakerIdentifier: SpeakerIdentifier {
    public let store: SpeakerEnrollmentStore
    public let matchThreshold: Double

    public init(store: SpeakerEnrollmentStore, matchThreshold: Double = 0.82) {
        self.store = store
        self.matchThreshold = matchThreshold
    }

    public func identify(audio: Data) throws -> Principal? {
        // The audio→embedding step is what voice-enrollment owns. This
        // default identifier cannot turn raw audio into an embedding on
        // its own, so it fails closed (returns nil). Callers with a
        // trained extractor should call `identify(embedding:)` directly.
        _ = audio
        return nil
    }

    public func identify(embedding: [Float]) throws -> Principal? {
        let enrollments = try store.enrollments()
        var best: (score: Double, token: String)?
        for enrollment in enrollments {
            guard enrollment.embedding.count == embedding.count else { continue }
            let score = Self.cosineSimilarity(enrollment.embedding, embedding)
            if score >= matchThreshold, score > (best?.score ?? -Double.infinity) {
                best = (score, enrollment.principalToken)
            }
        }
        guard let best else { return nil }
        return Principal.fromTierToken(best.token)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var magA: Double = 0
        var magB: Double = 0
        for i in 0..<a.count {
            let x = Double(a[i])
            let y = Double(b[i])
            dot += x * y
            magA += x * x
            magB += y * y
        }
        let denom = (magA.squareRoot()) * (magB.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
