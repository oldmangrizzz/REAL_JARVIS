import CryptoKit
import Foundation

/// SPEC-007: Per-device identity registry for the host tunnel.
///
/// Binds tunnel roles to specific devices' identity keys so that a leak of
/// the channel shared-secret alone does not allow an attacker to register
/// as a privileged role (e.g. `voice-operator`). Each registered device
/// holds its own 32-byte identity key; the server holds the same key in
/// `.jarvis/storage/tunnel/identities.json`.
///
/// Registration flow:
///   client HMAC-SHA256(identityKey, "deviceID:role:nonceISO")
///   server looks up deviceID -> allowedRoles, verifies HMAC, nonce
///   freshness (±120s), and nonce non-replay.
///
/// If the identities file doesn't exist yet, the store operates in
/// "bootstrap" mode: non-privileged roles still register, privileged roles
/// are rejected. This prevents silent lock-out while keeping the security
/// property that privileged roles cannot be claimed by anyone holding only
/// the channel secret.
public final class TunnelIdentityStore: @unchecked Sendable {
    public struct DeviceIdentity: Codable, Equatable, Sendable {
        public let deviceID: String
        public let allowedRoles: [String]
        /// Identity key, 32 bytes encoded as lowercase hex.
        public let identityKeyHex: String
    }

    public struct Document: Codable, Sendable {
        public let identities: [DeviceIdentity]
        /// When true and a device is not registered, allow non-privileged
        /// roles to register as before (preserves existing terminal /
        /// obsidian bootstrap clients). Privileged roles always require a
        /// matching identity entry.
        public let allowUnregisteredNonPrivileged: Bool?
    }

    public enum ValidationError: Error, Equatable {
        case privilegedRoleRequiresIdentityProof
        case nonceMissing
        case nonceStale(driftSeconds: Int)
        case nonceReplay
        case unknownDevice
        case roleNotAllowedForDevice
        case proofMismatch
        case malformedIdentityKey
    }

    /// Roles that MUST present a valid identity proof, whether or not an
    /// identities.json entry exists. Escalation-sensitive roles only.
    public static let privilegedRoles: Set<String> = ["voice-operator"]

    /// Clock skew tolerance for nonce freshness.
    public static let nonceWindow: TimeInterval = 120

    private let fileURL: URL
    private let lock = NSLock()
    private var document: Document?
    /// Per-device seen-nonce cache. Keyed by deviceID → Set<nonceString>.
    /// Entries older than `nonceWindow * 2` are pruned on each validation.
    private var seenNonces: [String: [(nonce: String, at: Date)]] = [:]
    private let now: () -> Date

    public init(fileURL: URL, clock: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = clock
    }

    public func reload() {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            document = nil
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            document = nil
        }
    }

    public var isBootstrapMode: Bool {
        lock.lock(); defer { lock.unlock() }
        return document == nil
    }

    /// Returns `nil` on success (registration may proceed), or a
    /// `ValidationError` explaining why the registration must be rejected.
    public func validate(_ registration: JarvisClientRegistration) -> ValidationError? {
        let role = registration.role.lowercased()
        lock.lock()
        let doc = document
        lock.unlock()

        let isPrivileged = Self.privilegedRoles.contains(role)

        if doc == nil {
            // Bootstrap: no identities.json yet. Allow non-privileged.
            return isPrivileged ? .privilegedRoleRequiresIdentityProof : nil
        }

        let knownDevice = doc?.identities.first(where: { $0.deviceID == registration.deviceID })

        if knownDevice == nil {
            if isPrivileged { return .unknownDevice }
            let allowUnregistered = doc?.allowUnregisteredNonPrivileged ?? false
            return allowUnregistered ? nil : .unknownDevice
        }

        guard let device = knownDevice else { return .unknownDevice }

        // Role must be whitelisted for this device.
        guard device.allowedRoles.contains(role) else {
            return .roleNotAllowedForDevice
        }

        // Proof is required once identities.json exists AND the device is
        // registered. (Non-privileged devices still need to prove identity
        // to claim their listed roles — the point of the store.)
        guard let proof = registration.identityProof, !proof.isEmpty else {
            return .privilegedRoleRequiresIdentityProof
        }
        guard let nonce = registration.nonce, !nonce.isEmpty else {
            return .nonceMissing
        }

        // Nonce freshness: parse ISO8601 and check drift.
        let formatter = ISO8601DateFormatter()
        guard let nonceDate = formatter.date(from: nonce) else {
            return .nonceStale(driftSeconds: Int.max)
        }
        let drift = abs(now().timeIntervalSince(nonceDate))
        if drift > Self.nonceWindow {
            return .nonceStale(driftSeconds: Int(drift))
        }

        // Nonce replay: reject if we've seen this exact nonce for this device
        // within the tracked window.
        lock.lock()
        let current = now()
        pruneExpiredNoncesLocked(reference: current)
        let seen = seenNonces[registration.deviceID] ?? []
        if seen.contains(where: { $0.nonce == nonce }) {
            lock.unlock()
            return .nonceReplay
        }
        lock.unlock()

        // Verify HMAC-SHA256(identityKey, "deviceID:role:nonce").
        guard let keyData = Data(hexString: device.identityKeyHex) else {
            return .malformedIdentityKey
        }
        let key = SymmetricKey(data: keyData)
        let message = "\(device.deviceID):\(role):\(nonce)".data(using: .utf8) ?? Data()
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        let expected = mac.map { String(format: "%02x", $0) }.joined()
        guard expected.caseInsensitiveCompare(proof) == .orderedSame else {
            return .proofMismatch
        }

        // Record nonce as seen.
        lock.lock()
        var updated = seenNonces[registration.deviceID] ?? []
        updated.append((nonce: nonce, at: current))
        seenNonces[registration.deviceID] = updated
        lock.unlock()

        return nil
    }

    private func pruneExpiredNoncesLocked(reference: Date) {
        let window = Self.nonceWindow * 2
        for (device, entries) in seenNonces {
            let fresh = entries.filter { reference.timeIntervalSince($0.at) < window }
            if fresh.isEmpty {
                seenNonces.removeValue(forKey: device)
            } else {
                seenNonces[device] = fresh
            }
        }
    }
}

// MARK: - Data hex helper

private extension Data {
    init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count % 2 == 0 else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex {
            let next = trimmed.index(idx, offsetBy: 2)
            guard let byte = UInt8(trimmed[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
