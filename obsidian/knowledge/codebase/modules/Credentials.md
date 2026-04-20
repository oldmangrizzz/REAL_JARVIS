# Credentials

**Path:** `Jarvis/Sources/JarvisCore/Credentials/`
**Files:** `MapboxCredentials.swift`

## Purpose
Tier-gated secret-material loader. First landed for Mapbox (SPEC-009)
but the pattern — **public vs. secret token with principal-tier
enforcement at the type boundary** — is the template for any future
credential class.

## Key types
- `MapboxCredentials` (struct, `Sendable`)
  - `publicToken` — `pk.*` style token, exposed to any tier so Companion OS maps render on family devices.
  - `secretToken(for: Principal)` — `sk.*` style token, returns `nil` for any non-operator principal. **Fails closed.**
- `MapboxCredentialLoader.load(...)` — static loader with a deterministic precedence chain.

## Precedence (first match wins)
1. Environment variables (`MAPBOX_PUBLIC_TOKEN` / `MAPBOX_SECRET_TOKEN`).
2. `.jarvis/secrets/mapbox.env` (dotenv, gitignored).

## Invariants
- Secret-token access is a **type-level gate**, not a runtime check in
  the caller. You cannot get the secret token without handing in a
  `Principal`, and only `.operatorTier` principals receive a non-nil
  answer.
- The `.jarvis/secrets/` directory is gitignored — secrets never enter
  the repo.
- Env vars take precedence over dotenv so ephemeral/CI overrides work
  without touching on-disk files.

## Related
- [[concepts/Companion-OS-Tier]] — defines the Principal enum this module gates on.
- [[architecture/TRUST_BOUNDARIES]] — operator/companion/responder/guest tiering.
- `Tests/JarvisCoreTests/MapboxCredentialsTests.swift` — principal gating + precedence tests.
- [[codebase/modules/OSINT]] — the main consumer of these credentials (base-map tiles).

## Future
- AppleMusic, Convex, Huggingface, TestFlight API keys are candidates
  for the same pattern. When adding, follow the public/secret split
  even if only one tier ever uses them — the Principal parameter keeps
  future extension cheap.
