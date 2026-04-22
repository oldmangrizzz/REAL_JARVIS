import Foundation

/// Client-side helper that produces a fully-signed
/// `JarvisClientRegistration` from a `BiometricIdentityVault`.
///
/// Lives on the client. The server counterpart is `TunnelIdentityStore`
/// (`validate(_:)`). The registrar's job is to assemble the fields the
/// server demands — `deviceID`, `role`, `nonce` (fresh ISO-8601 inside
/// the server's ±120 s skew window), and `identityProof` (HMAC-SHA256
/// over `"deviceID:role:nonce"` signed by the device's biometric-bound
/// key) — without the caller ever touching the raw key material.
///
/// Design:
/// - Role is lowercased before signing. The server lowercases before
///   HMAC verification (see `TunnelIdentityStore.validate`); the client
///   must match or every proof fails.
/// - Nonces are produced with millisecond precision so that two
///   registrations in the same second don't collide (server's
///   replay-window cache keys by exact string).
/// - No network calls. The registrar hands back a struct; the caller
///   owns the transport.
public struct BiometricTunnelRegistrar: Sendable {
    private let vault: BiometricIdentityVault
    private let watchVault: BiometricIdentityVault?
    private let clock: @Sendable () -> Date

    public init(
        vault: BiometricIdentityVault,
        watchVault: BiometricIdentityVault? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.vault = vault
        self.watchVault = watchVault
        self.clock = clock
    }

    /// Build a signed registration. Prompts biometric once (to unlock
    /// the identity key) and returns the struct ready to send.
    ///
    /// `reason` is surfaced in the biometric prompt string the OS
    /// presents, so pass a sentence the operator will actually
    /// understand at 3am in an ambulance.
    public func makeRegistration(
        deviceID: String,
        deviceName: String,
        platform: String,
        role: String,
        appVersion: String,
        reason: String
    ) async throws -> JarvisClientRegistration {
        let normalizedRole = role.lowercased()
        let nonceISO = Self.makeNonce(clock())
        let proof = try await vault.signRegistration(
            deviceID: deviceID,
            role: normalizedRole,
            nonceISO: nonceISO,
            reason: reason
        )
        return JarvisClientRegistration(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: platform,
            role: normalizedRole,
            appVersion: appVersion,
            nonce: nonceISO,
            identityProof: proof
        )
    }

    /// ISO-8601 matching the server's default `ISO8601DateFormatter`
    /// (internet-date-time, **no fractional seconds** — the server uses
    /// the default options and would reject a fractional nonce as
    /// unparseable). Uniqueness across back-to-back calls is the
    /// server's nonce-replay job; the client just has to be within the
    /// ±120 s skew window.
    static func makeNonce(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Watch-specific signed registration. Per SPEC-AMBIENT-002-FIX-01 §3.3,
    /// watch registration must route through a watch-dedicated
    /// `BiometricIdentityVault` (typically constructed with
    /// `LAPolicy.deviceOwnerAuthentication` so Apple Watch PIN fallback is
    /// accepted on Series 3 and other watches without Touch/Face ID).
    ///
    /// Platform is fixed to `"watch"` and the returned registration matches
    /// the iPhone HMAC shape `"deviceID:role:nonce"` so
    /// `TunnelIdentityStore.validate(...)` accepts it when
    /// `privilegedRoles` contains `"watch"`. `reason` is passed to the
    /// biometric prompt only — it is **not** hashed into the signature
    /// (server verification does not hash reason; see
    /// `TunnelIdentityStore.swift:169`).
    public func registerWatch(
        deviceID: String,
        deviceName: String,
        role: String,
        appVersion: String,
        reason: String
    ) async throws -> JarvisClientRegistration {
        guard let watchVault else {
            throw BiometricVaultError.biometryUnavailable
        }
        let normalizedRole = role.lowercased()
        let nonceISO = Self.makeNonce(clock())
        let proof = try await watchVault.signRegistration(
            deviceID: deviceID,
            role: normalizedRole,
            nonceISO: nonceISO,
            reason: reason
        )
        return JarvisClientRegistration(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: "watch",
            role: normalizedRole,
            appVersion: appVersion,
            nonce: nonceISO,
            identityProof: proof
        )
    }
}
