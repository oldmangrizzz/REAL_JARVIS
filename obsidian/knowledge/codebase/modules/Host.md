# Host

**Path:** `Jarvis/Sources/JarvisCore/Host/`
**Files:**
- `JarvisHostTunnelServer.swift` — tunnel transport (accept + relay)
- `TunnelIdentityStore.swift` — server-side per-device key registry + HMAC validation
- `BiometricIdentityVault.swift` — client-side biometric-bound mirror (added SPEC-007-BIO)
- `BiometricTunnelRegistrar.swift` — composes vault → signed `JarvisClientRegistration`

## Purpose
The **host-side tunnel server** plus its paired identity primitives.
The server accepts connections from trusted peers (Linux worker, mobile
clients, cockpit) and relays commands/telemetry over a hardened
transport. Imports `Network` + `Security`.

Identity storage is split across the trust boundary:
- **Server** (`TunnelIdentityStore`) holds the long-lived 32-byte HMAC
  key per device and validates registration proofs.
- **Client** ([[codebase/modules/Host|BiometricIdentityVault]]) holds
  the same key biometric-bound in the Keychain, and *signs* the
  registration proof every connection.

Neither side ever transmits the raw key after provisioning.

## Key types
- `JarvisHostTunnelServer` — `@unchecked Sendable`. Final class. Socket
  listener + per-peer handler.
- `TunnelIdentityStore` — server-side JSON-backed store at
  `.jarvis/storage/tunnel/identities.json`. `validate(registration:)`
  recomputes `HMAC-SHA256("deviceID:role:nonceISO")` over the stored
  key and timing-safe-compares to the client-sent hex proof.
- `TunnelIdentityStore.privilegedRoles` — `["voice-operator"]`. Any
  role in this set MUST present a valid identity proof.
- `BiometricIdentityVault` — client-side. Protocol-based DI:
  - `BiometricAuthenticator` (default: `LocalAuthenticationBiometricAuthenticator`, LAContext under `#if canImport(LocalAuthentication)`).
  - `IdentityKeyStore` (default: `KeychainIdentityKeyStore`, `.biometryCurrentSet` ACL).
  - API: `provisionDevice(deviceID:reason:)` (one-time, biometric-gated, returns hex), `signRegistration(deviceID:role:nonceISO:reason:)`, `revokeDevice(deviceID:reason:)`.
- `BiometricVaultError` — enum. `keyAlreadyProvisioned` blocks silent
  key-swap (re-provisioning requires explicit revoke).

## Security
- CX-044: uses `SecRandomCopyBytes` for all nonces (fixed prior
  weak-PRNG usage — see [[history/REMEDIATION_TIMELINE]]).
- Every inbound peer must present a [[codebase/modules/SoulAnchor|SoulAnchor]]-
  ratified fingerprint.
- Traffic is authenticated + encrypted end-to-end.
- Plaintext PII is never written to logs (hashed only).
- **Fresh enrollment is a new human.** Keychain ACL `.biometryCurrentSet`
  means any change to Touch ID / Face ID enrollment invalidates the
  stored key; the device must re-provision through operator-ratified
  enrollment. Doctrine: fail closed.
- The vault enforces non-empty nonces at sign time (`.malformedNonce`)
  and rejects double-provisioning (`.keyAlreadyProvisioned`) so the
  operator cannot accidentally overwrite a live device key.

## Traffic classes
- Control-plane (Mycelium — see [[codebase/modules/ControlPlane]]).
- Telemetry upload.
- Command bridge ([[codebase/modules/Interface]] display commands).

## Tests
- `JarvisHostTunnelServerTests` — transport + framing.
- `TunnelIdentityStoreTests` — registration validate happy path + reject paths.
- `BiometricIdentityVaultTests` (11 tests) — provisioning, re-provision
- `BiometricTunnelRegistrarTests` (7 tests) — round-trip through `TunnelIdentityStore.validate`, role lowercasing, ISO-8601 nonce format, injected-clock uniqueness, staleness, replay, proof-mismatch
  rejection, HMAC shape match, determinism, biometry-deny propagation,
  malformed-nonce rejection, independent HMAC cross-check.

## Related
- [[codebase/modules/ControlPlane]]
- [[codebase/modules/SoulAnchor]]
- [[codebase/services/jarvis-linux-node]] — the remote peer it serves.
- [[architecture/TRUST_BOUNDARIES]]
- [[history/REMEDIATION_TIMELINE]] (CX-044)
