# Host

**Path:** `Jarvis/Sources/JarvisCore/Host/`
**Files:** `JarvisHostTunnelServer.swift` (453 lines)

## Purpose
The **host-side tunnel server**: accepts connections from trusted peers
(Linux worker, mobile clients) and relays commands/telemetry over a
hardened transport. Imports `Network` + `Security`.

## Key type
- `JarvisHostTunnelServer` — `@unchecked Sendable`. Final class.

## Security
- CX-044: uses `SecRandomCopyBytes` for all nonces (fixed prior
  weak-PRNG usage — see [[history/REMEDIATION_TIMELINE]]).
- Every inbound peer must present a [[codebase/modules/SoulAnchor|SoulAnchor]]-
  ratified fingerprint.
- Traffic is authenticated + encrypted end-to-end.
- Plaintext PII is never written to logs (hashed only).

## Traffic classes
- Control-plane (Mycelium — see [[codebase/modules/ControlPlane]]).
- Telemetry upload.
- Command bridge ([[codebase/modules/Interface]] display commands).

## Related
- [[codebase/modules/ControlPlane]]
- [[codebase/modules/SoulAnchor]]
- [[codebase/services/jarvis-linux-node]] — the remote peer it serves.
- [[architecture/TRUST_BOUNDARIES]]
- [[history/REMEDIATION_TIMELINE]] (CX-044)
