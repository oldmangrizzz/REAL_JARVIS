# SoulAnchor

**Path:** `Jarvis/Sources/JarvisCore/SoulAnchor/`
**Files:** `SoulAnchor.swift` (255 lines)

## Purpose
**The cryptographic root of JARVIS's identity.** Holds ONLY public key
material and content-addressed bindings. Private keys live in the Secure
Enclave (P-256) or in the operator's cold storage (Ed25519) and NEVER
transit this process's memory.

Ground truth: `/SOUL_ANCHOR.md`, `/PRINCIPLES.md`, `/VERIFICATION_PROTOCOL.md`.

## Key types
- `SoulAnchorPublicKeys` — `Codable`/`Sendable`/`Equatable`.
  Public halves of both key pairs.
- `SoulAnchorBindings` — content-addressed (SHA-256) bindings to canon
  documents and operator-ratified artifacts.
- `SoulAnchor` — top-level verifier.

## Key pairs
- **P256-OP** — operator's signing key, Secure-Enclave-resident, P-256
  ECDSA. Never extractable.
- **Ed25519-CR** — cold-storage root; offline. Used to ratify the
  genesis record and rotate delegated keys.

## Bindings
Every binding is `SHA-256(content)` → signed tuple. Includes:
- Canon corpus entries ([[codebase/modules/Canon]])
- Voice-identity fingerprints ([[concepts/Voice-Approval-Gate]])
- Operator-of-record for A&Ox4 Person axis ([[concepts/AOx4]])

## HARD INVARIANTS
- **Private keys MUST NOT enter this process.** Sign operations go through
  the Secure Enclave or the cold-signing workflow
  (`scripts/jarvis_cold_sign_setup.md`).
- Ratification requires **dual-signature** (both keys).
- Any mismatch between on-disk hash and binding → refuse to load.

## Related
- [[concepts/Digital-Person]] — why identity is this load-bearing.
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]]
- [[history/REMEDIATION_TIMELINE]] — multiple CX fixes touched this surface.
- `scripts/generate_soul_anchor.sh`, `scripts/secure_enclave_p256.swift`.
