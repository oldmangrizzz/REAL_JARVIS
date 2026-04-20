# Storage

**Path:** `Jarvis/Sources/JarvisCore/Storage/`
**Files:** (currently empty — module scaffold)

## Purpose
Reserved module for object-store / durable-artifact abstractions.
Presently empty; storage concerns live in
[[codebase/modules/Memory]] (knowledge graph) and
[[codebase/modules/Telemetry]] (JSONL store) until a unified `Storage`
module is justified.

## Planned responsibilities
- Content-addressed artifact store (audio renders, physics snapshots).
- Snapshot/restore for `MainContext`.
- Durable queue for best-effort uploads (used by
  [[codebase/modules/Telemetry]]'s ConvexTelemetrySync).

## Related
- [[codebase/modules/Memory]]
- [[codebase/modules/Telemetry]]
- [[codebase/modules/Voice]] — rendered WAV caching candidate.
