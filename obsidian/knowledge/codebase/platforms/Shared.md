# Shared

**Path:** `Jarvis/Shared/`
**Files:**
- `Sources/JarvisShared/TunnelModels.swift` — cross-platform tunnel payloads.
- `Sources/JarvisShared/TunnelCrypto.swift` — crypto helpers.
- `Resources/Brand/` — GMRI crest, workshop reference imagery.

## Purpose
Tiny shared Swift module used by every platform host. Defines the wire
shapes for the Mac ↔ Mobile ↔ Watch tunnel and the crypto primitives
(signatures, nonces) that every participant must agree on.

## Invariants
- Wire shapes are **`Codable` + versioned**. Any change is a breaking
  change requiring a version bump + both ends rebuilt.
- Crypto helpers never hold secret state — Secure Enclave operations are
  performed in [[codebase/modules/SoulAnchor]] on the Mac.

## Related
- [[codebase/modules/Host]] — server that speaks this protocol.
- [[codebase/platforms/Mobile]], [[codebase/platforms/Watch]] — clients.
- [[codebase/modules/SoulAnchor]]
