# ControlPlane

**Path:** `Jarvis/Sources/JarvisCore/ControlPlane/`
**Files:** `MyceliumControlPlane.swift` (758 lines — largest single-file module)

## Purpose
The **Mycelium** control plane: distributed coordination for JARVIS across
nodes (Mac host, Linux worker, optional phones). Named mycelium because
it's the fungal-network layer under the visible system — quietly routing
signals, work, and trust.

## Key types
- `MyceliumControlPlaneStatus` (`Sendable`) — current health/posture.
- `MyceliumControlPlane` — final class. The coordinator.

## Responsibilities
- Route work across nodes based on [[codebase/modules/Pheromind]] deposits
  and [[codebase/modules/Oscillator]] PLV bands.
- Enforce trust posture: unknown nodes are repelled. Known nodes must
  present a Soul-Anchor-ratified fingerprint
  ([[codebase/modules/SoulAnchor]]).
- Graceful degradation: if A&Ox4 drops, the plane shrinks
  (nodes fall back to local-only).

## Security
Imports `Security` — uses `SecRandomCopyBytes` for nonces, signatures via
SoulAnchor public halves. No remote command can run without a matching
fingerprint.

## Related
- [[codebase/modules/Pheromind]]
- [[codebase/modules/Oscillator]]
- [[codebase/modules/SoulAnchor]]
- [[codebase/modules/Host]] — the tunnel server it coordinates with.
- [[architecture/TRUST_BOUNDARIES]]
