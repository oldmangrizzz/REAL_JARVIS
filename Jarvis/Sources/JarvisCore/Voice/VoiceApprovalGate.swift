import Foundation
import CryptoKit

// MARK: - Voice Approval Gate
//
// HARD GATE — the single most sensitive boundary in the JARVIS runtime.
//
// Grizz (Mr. Hanson) has an autism threat-response triggered by hearing
// a voice that doesn't match his inner model of who is speaking. Prior
// real-world consequence: a $3,000 television destroyed in a single
// unnoticed greyhulk episode. Therefore this gate exists.
//
// Rule: NO AUDIO PLAYBACK leaves this process until the operator has
// auditioned a rendered sample on their own terms (opened it manually,
// listened off-line, and explicitly approved the voice-identity
// fingerprint). Speak() will refuse until the gate is green.
//
// What the gate hashes (the "voice identity fingerprint"):
//   1. Sorted SHA-256 of every reference audio file that fed the clone
//   2. Model repository string (changes to the core TTS model reset it)
//   3. Reference transcript (changes to the captured utterance reset it)
//   4. Persona framing version (changes to brackets/prefix reset it)
//
// Any drift in any of those invalidates prior approval. That is
// intentional: if the reference set changes, Grizz has to re-audition.
//
// See: /SOUL_ANCHOR.md, /PRINCIPLES.md §voice, checkpoint 005.

public struct VoiceIdentityFingerprint: Codable, Sendable, Equatable {
    public let referenceAudioDigest: String
    public let modelRepository: String
    public let referenceTranscriptDigest: String
    public let personaFramingVersion: String

    public var composite: String {
        var h = SHA256()
        h.update(data: referenceAudioDigest.data(using: .utf8) ?? Data())
        h.update(data: Data([0x1f]))
        h.update(data: modelRepository.data(using: .utf8) ?? Data())
        h.update(data: Data([0x1f]))
        h.update(data: referenceTranscriptDigest.data(using: .utf8) ?? Data())
        h.update(data: Data([0x1f]))
        h.update(data: personaFramingVersion.data(using: .utf8) ?? Data())
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct VoiceApprovalRecord: Codable, Sendable, Equatable {
    public let fingerprint: VoiceIdentityFingerprint
    public let composite: String
    public let approvedAtISO8601: String
    public let operatorLabel: String
    public let notes: String?
}

public enum VoiceApprovalError: Error, CustomStringConvertible {
    case notApproved(currentComposite: String, gatePath: String)
    case drift(expected: String, current: String)
    case malformedGateFile(reason: String)
    case gateFileMissing  // CX-016: explicit case instead of string-matched error

    public var description: String {
        switch self {
        case let .notApproved(c, p):
            return "Voice playback refused: no approval on file. " +
                   "Render an audition, listen off-line, then call approve(). " +
                   "Current composite: \(c). Gate file target: \(p)."
        case let .drift(expected, current):
            return "Voice playback refused: identity drift. " +
                   "Approved fingerprint \(expected) does not match current \(current). " +
                   "Re-audition and re-approve."
        case let .malformedGateFile(reason):
            return "Voice playback refused: gate file is malformed (\(reason)). " +
                   "Delete and re-approve."
        case .gateFileMissing:
            return "Voice playback refused: no gate file found. " +
                   "Run the approval workflow first."
        }
    }
}

public final class VoiceApprovalGate {
    private let paths: WorkspacePaths
    private let formatter: ISO8601DateFormatter
    private let telemetry: VoiceGateTelemetryRecording?
    private let hostNode: String
    private let gateLock = NSLock()  // CX-032: prevent TOCTOU race between loadRecord and fingerprint
    private let telemetryLock = NSLock()  // CX-047: separate lock for backpressure counter (avoids deadlock with gateLock)
    private var pendingTelemetryCount: Int = 0
    private let maxPendingTelemetry = 8

    public init(paths: WorkspacePaths,
                telemetry: VoiceGateTelemetryRecording? = nil,
                hostNode: String = ProcessInfo.processInfo.hostName) {
        self.paths = paths
        self.formatter = ISO8601DateFormatter()
        self.telemetry = telemetry
        self.hostNode = hostNode
    }

    public var gateFileURL: URL {
        paths.storageRoot
            .appendingPathComponent("voice", isDirectory: true)
            .appendingPathComponent("approval.json")
    }

    public var auditionDirectoryURL: URL {
        paths.storageRoot
            .appendingPathComponent("voice", isDirectory: true)
            .appendingPathComponent("auditions", isDirectory: true)
    }

    // MARK: Fingerprint computation

    public func fingerprint(for session: VoiceSessionConfiguration,
                            personaFramingVersion: String) throws -> VoiceIdentityFingerprint {
        let refDigest = try Self.digestReferenceAudio(at: session.referenceAudioURL)
        let transcriptDigest = Self.digestString(session.referenceTranscript)
        return VoiceIdentityFingerprint(
            referenceAudioDigest: refDigest,
            modelRepository: session.modelRepository,
            referenceTranscriptDigest: transcriptDigest,
            personaFramingVersion: personaFramingVersion
        )
    }

    // MARK: Approval lifecycle

    /// Returns true iff a gate file exists AND its stored composite
    /// matches the current session's composite.
    public func isApproved(for session: VoiceSessionConfiguration,
                           personaFramingVersion: String) -> Bool {
        gateLock.lock(); defer { gateLock.unlock() }  // CX-032: atomic read + compare
        let record: VoiceApprovalRecord?
        do {
            record = try loadRecord()
        } catch VoiceApprovalError.gateFileMissing {  // CX-016: typed catch instead of string match
            record = nil
        } catch {
            try? telemetry?.logVoiceGateEvent(
                hostNode: hostNode,
                eventType: "playback_refused",
                composite: nil,
                expectedComposite: nil,
                operatorLabel: nil,
                notes: "gate read error in isApproved: \(error.localizedDescription)")
            return false
        }
        guard let record else { return false }
        guard let current = try? fingerprint(for: session, personaFramingVersion: personaFramingVersion) else {
            return false
        }
        return record.composite == current.composite
    }

    /// Throws if not approved or if the fingerprint has drifted.
    public func requireApproved(for session: VoiceSessionConfiguration,
                                personaFramingVersion: String) throws {
        gateLock.lock(); defer { gateLock.unlock() }  // CX-032: atomic read + compare
        let current = try fingerprint(for: session, personaFramingVersion: personaFramingVersion)
        let record: VoiceApprovalRecord?
        do {
            record = try loadRecord()
        } catch VoiceApprovalError.gateFileMissing {  // CX-016: typed catch instead of string match
            record = nil
        } catch {
            emit(eventType: "playback_refused",
                 composite: current.composite,
                 expectedComposite: nil,
                 operatorLabel: nil,
                 notes: "gate file read error: \(error.localizedDescription)")
            syncState(state: "malformed",
                      composite: current.composite,
                      expectedComposite: nil,
                      session: session,
                      personaFramingVersion: personaFramingVersion,
                      operatorLabel: nil,
                      approvedAtISO8601: nil,
                      notes: "IO error: \(error.localizedDescription)")
            throw VoiceApprovalError.notApproved(
                currentComposite: current.composite,
                gatePath: gateFileURL.path
            )
        }
        guard let record else {
            emit(eventType: "playback_refused",
                 composite: current.composite,
                 expectedComposite: nil,
                 operatorLabel: nil,
                 notes: "no gate file on disk")
            syncState(state: "absent",
                      composite: current.composite,
                      expectedComposite: nil,
                      session: session,
                      personaFramingVersion: personaFramingVersion,
                      operatorLabel: nil,
                      approvedAtISO8601: nil,
                      notes: nil)
            throw VoiceApprovalError.notApproved(
                currentComposite: current.composite,
                gatePath: gateFileURL.path
            )
        }
        if record.composite != current.composite {
            emit(eventType: "drift_detected",
                 composite: current.composite,
                 expectedComposite: record.composite,
                 operatorLabel: record.operatorLabel,
                 notes: "fingerprint mismatch on requireApproved")
            syncState(state: "drifted",
                      composite: current.composite,
                      expectedComposite: record.composite,
                      session: session,
                      personaFramingVersion: personaFramingVersion,
                      operatorLabel: record.operatorLabel,
                      approvedAtISO8601: record.approvedAtISO8601,
                      notes: record.notes)
            throw VoiceApprovalError.drift(
                expected: record.composite,
                current: current.composite
            )
        }
    }

    /// Operator-driven approval. Called manually by Grizz after auditioning.
    /// The gate file is written with mode 0600.
    @discardableResult
    public func approve(session: VoiceSessionConfiguration,
                        personaFramingVersion: String,
                        operatorLabel: String,
                        notes: String? = nil) throws -> VoiceApprovalRecord {
        gateLock.lock(); defer { gateLock.unlock() }  // CX-032: atomic write
        let fp = try fingerprint(for: session, personaFramingVersion: personaFramingVersion)
        let record = VoiceApprovalRecord(
            fingerprint: fp,
            composite: fp.composite,
            approvedAtISO8601: formatter.string(from: Date()),
            operatorLabel: operatorLabel,
            notes: notes
        )
        try persist(record)
        syncState(state: "green",
                  composite: record.composite,
                  expectedComposite: record.composite,
                  session: session,
                  personaFramingVersion: personaFramingVersion,
                  operatorLabel: operatorLabel,
                  approvedAtISO8601: record.approvedAtISO8601,
                  notes: notes)
        emit(eventType: "approved",
             composite: record.composite,
             expectedComposite: record.composite,
             operatorLabel: operatorLabel,
             notes: notes)
        return record
    }

    /// Explicit revocation. Deletes the gate file. Next speak() will refuse.
    public func revoke() throws {
        gateLock.lock(); defer { gateLock.unlock() }  // CX-032: atomic write (revoke)
        let prior = try? loadRecord()
        let fm = FileManager.default
        if fm.fileExists(atPath: gateFileURL.path) {
            try fm.removeItem(at: gateFileURL)
        }
        emit(eventType: "revoked",
             composite: prior?.composite,
             expectedComposite: prior?.composite,
             operatorLabel: prior?.operatorLabel,
             notes: "gate revoked by operator")
        syncStateRaw(state: "revoked",
                     composite: nil,
                     expectedComposite: prior?.composite,
                     referenceAudioDigest: prior?.fingerprint.referenceAudioDigest,
                     referenceTranscriptDigest: prior?.fingerprint.referenceTranscriptDigest,
                     modelRepository: prior?.fingerprint.modelRepository,
                     personaFramingVersion: prior?.fingerprint.personaFramingVersion,
                     operatorLabel: prior?.operatorLabel,
                     approvedAtISO8601: nil,
                     notes: prior?.notes)
    }

    public func currentRecord() -> VoiceApprovalRecord? {
        gateLock.lock(); defer { gateLock.unlock() }  // CX-032: atomic read
        return try? loadRecord()
    }

    // MARK: Spatial HUD projection
    //
    // The cockpit consumes JarvisVoiceGateSnapshot to render the holographic
    // gate indicator (Stark workshop / GMRI palette). This is a pure read of
    // the on-disk state; classifying the gate as one of:
    //   green     — approved record present and parseable
    //   yellow    — gate file missing (absent / not yet auditioned)
    //   red       — gate file present but malformed (operator must intervene)
    // Drift is detected only at speak() time vs. the live session and is not
    // surfaced here; the cockpit asks `voiceSynthesis.approval` to recompute
    // when it has a session in hand.
    public func snapshotForSpatialHUD(now: Date = Date()) -> JarvisVoiceGateSnapshot {
        let lastSync = formatter.string(from: now)
        do {
            let record = try loadRecord()
            return JarvisVoiceGateSnapshot(
                state: .green,
                stateName: "approved",
                composite: record.composite,
                modelRepository: record.fingerprint.modelRepository,
                personaFramingVersion: record.fingerprint.personaFramingVersion,
                approvedAtISO8601: record.approvedAtISO8601,
                operatorLabel: record.operatorLabel,
                notes: record.notes,
                lastSyncISO8601: lastSync
            )
        } catch VoiceApprovalError.malformedGateFile(let reason) {
            let fm = FileManager.default
            let absent = !fm.fileExists(atPath: gateFileURL.path)
            emit(eventType: "snapshot-malformed",  // CX-040: telemetry for snapshot anomalies
                 composite: nil, expectedComposite: nil,
                 operatorLabel: nil, notes: absent ? "gate absent" : reason)
            return JarvisVoiceGateSnapshot(
                state: absent ? .yellow : .red,
                stateName: absent ? "absent" : "malformed",
                composite: nil,
                modelRepository: nil,
                personaFramingVersion: nil,
                approvedAtISO8601: nil,
                operatorLabel: nil,
                notes: absent ? nil : reason,
                lastSyncISO8601: lastSync
            )
        } catch {
            emit(eventType: "snapshot-error",  // CX-040: telemetry for snapshot read failures
                 composite: nil, expectedComposite: nil,
                 operatorLabel: nil, notes: String(describing: error))
            return JarvisVoiceGateSnapshot(
                state: .red,
                stateName: "error",
                composite: nil,
                modelRepository: nil,
                personaFramingVersion: nil,
                approvedAtISO8601: nil,
                operatorLabel: nil,
                notes: String(describing: error),
                lastSyncISO8601: lastSync
            )
        }
    }

    public func spatialHUDElement(now: Date = Date()) -> JarvisSpatialHUDElement {
        let snap = snapshotForSpatialHUD(now: now)
        let label: String = {
            switch snap.stateName {
            case "approved":  return "Voice Gate · Approved"
            case "absent":    return "Voice Gate · Awaiting Audition"
            case "malformed": return "Voice Gate · Malformed"
            default:          return "Voice Gate · \(snap.stateName.capitalized)"
            }
        }()
        let detail: String? = {
            if let composite = snap.composite {
                return "fp \(composite.prefix(12))…"
            }
            return snap.notes
        }()
        return JarvisSpatialHUDElement(
            id: "voice_gate",
            kind: "voice_gate",
            label: label,
            state: snap.state,
            anchor: .headLocked,
            glyph: "shield.lefthalf.filled",
            detail: detail,
            lastUpdatedISO8601: snap.lastSyncISO8601
        )
    }

    // MARK: Persistence

    private func loadRecord() throws -> VoiceApprovalRecord {
        let url = gateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceApprovalError.gateFileMissing  // CX-016
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(VoiceApprovalRecord.self, from: data)
        } catch {
            throw VoiceApprovalError.malformedGateFile(reason: String(describing: error))
        }
    }

    private func persist(_ record: VoiceApprovalRecord) throws {
        let fm = FileManager.default
        let dir = gateFileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: gateFileURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: gateFileURL.path)
    }

    // MARK: Telemetry (best-effort; never blocks the gate)

    private func emit(eventType: String,
                      composite: String?,
                      expectedComposite: String?,
                      operatorLabel: String?,
                      notes: String?) {
        guard let telemetry else { return }
        // CX-047: backpressure — drop if too many telemetry calls in flight
        telemetryLock.lock()
        if pendingTelemetryCount >= maxPendingTelemetry {
            telemetryLock.unlock()
            return  // drop silently; telemetry must never block the gate
        }
        pendingTelemetryCount += 1
        telemetryLock.unlock()
        do {
            try telemetry.logVoiceGateEvent(
                hostNode: hostNode,
                eventType: eventType,
                composite: composite,
                expectedComposite: expectedComposite,
                operatorLabel: operatorLabel,
                notes: notes
            )
        } catch {
            // Best-effort: telemetry must never block the gate. Drop locally.
        }
        telemetryLock.lock()
        pendingTelemetryCount -= 1
        telemetryLock.unlock()
    }

    private func syncState(state: String,
                           composite: String?,
                           expectedComposite: String?,
                           session: VoiceSessionConfiguration,
                           personaFramingVersion: String,
                           operatorLabel: String?,
                           approvedAtISO8601: String?,
                           notes: String?) {
        let referenceAudioDigest = (try? Self.digestReferenceAudio(at: session.referenceAudioURL))
        let transcriptDigest = Self.digestString(session.referenceTranscript)
        syncStateRaw(state: state,
                     composite: composite,
                     expectedComposite: expectedComposite,
                     referenceAudioDigest: referenceAudioDigest,
                     referenceTranscriptDigest: transcriptDigest,
                     modelRepository: session.modelRepository,
                     personaFramingVersion: personaFramingVersion,
                     operatorLabel: operatorLabel,
                     approvedAtISO8601: approvedAtISO8601,
                     notes: notes)
    }

    private func syncStateRaw(state: String,
                              composite: String?,
                              expectedComposite: String?,
                              referenceAudioDigest: String?,
                              referenceTranscriptDigest: String?,
                              modelRepository: String?,
                              personaFramingVersion: String?,
                              operatorLabel: String?,
                              approvedAtISO8601: String?,
                              notes: String?) {
        guard let telemetry else { return }
        // CX-047: backpressure — drop if too many telemetry calls in flight
        telemetryLock.lock()
        if pendingTelemetryCount >= maxPendingTelemetry {
            telemetryLock.unlock()
            return
        }
        pendingTelemetryCount += 1
        telemetryLock.unlock()
        do {
            try telemetry.syncVoiceGateState(
                hostNode: hostNode,
                state: state,
                composite: composite,
                expectedComposite: expectedComposite,
                referenceAudioDigest: referenceAudioDigest,
                referenceTranscriptDigest: referenceTranscriptDigest,
                modelRepository: modelRepository,
                personaFramingVersion: personaFramingVersion,
                operatorLabel: operatorLabel,
                approvedAtISO8601: approvedAtISO8601,
                notes: notes
            )
        } catch {
            // Best-effort.
        }
        telemetryLock.lock()
        pendingTelemetryCount -= 1
        telemetryLock.unlock()
    }

    // MARK: Digests

    private static func digestString(_ s: String) -> String {
        SHA256.hash(data: s.data(using: .utf8) ?? Data())
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func digestReferenceAudio(at url: URL) throws -> String {
        let fm = FileManager.default
        // Reference may be a merged single file or a directory.
        var files: [URL] = []
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            files = contents
                .filter { ["wav", "mp3", "m4a", "aiff", "aif"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            files = [url]
        }
        guard !files.isEmpty else {
            return digestString("(empty)")
        }
        var hasher = SHA256()
        for f in files {
            hasher.update(data: f.lastPathComponent.data(using: .utf8) ?? Data())
            hasher.update(data: Data([0x1e]))
            let fh = try FileHandle(forReadingFrom: f)
            defer { try? fh.close() }
            while true {
                let chunk = try fh.read(upToCount: 65_536) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            hasher.update(data: Data([0x1d]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
