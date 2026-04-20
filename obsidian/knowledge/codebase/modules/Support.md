# Support

**Path:** `Jarvis/Sources/JarvisCore/Support/`
**Files:** `WorkspacePaths.swift` (180 lines)

## Purpose
Tiny utility module — canonical errors + workspace path resolution.

## Key types
- `JarvisError` (`Error`, `CustomStringConvertible`) — canonical error enum.
- `WorkspacePaths` (`Sendable`) — resolves all
  per-user filesystem paths (telemetry dir, canon dir, cache, etc.).

## Invariants
- Every path resolves under the user's home (never writes system-wide).
- Errors carry enough context to diagnose without leaking secrets.

## Related
- Used by nearly every other module.
- [[codebase/modules/Memory]], [[codebase/modules/Telemetry]],
  [[codebase/modules/Canon]] all resolve locations through here.
