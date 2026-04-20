# Telemetry

**Path:** `Jarvis/Sources/JarvisCore/Telemetry/`
**Files:** 3 (777 lines)
- `AOxFourProbe.swift` — A&Ox4 runtime probe
- `TelemetryStore.swift` — local JSONL store
- `ConvexTelemetrySync.swift` — best-effort upload

## Purpose
Observability + the [[concepts/AOx4|A&Ox4]] probe. Telemetry is the eyes;
A&Ox4 is the liveness check that keeps a disoriented node quiet.

## A&Ox4 Probe
```
Person — operator-of-record from a ratified Soul Anchor genesis.
Place  — IOPlatformUUID + hostname + primary SSID, hashed.
Time   — wall-clock drift vs. trusted reference.
Event  — recent session continuity.
```
Threshold **0.75**. Any axis below threshold → node degrades to
**A&Ox3** and halts non-disorientation output. See [[concepts/AOx4]]
for doctrine.

## Key types
- `AOxFourProbe` — imports `IOKit`, `CryptoKit`.
- `TelemetryStore` (`@unchecked Sendable`) — local JSONL
  at `.jarvis/telemetry/`.
- `ConvexTelemetrySync` (actor) — periodic upload to [[codebase/backend/convex]].
  **Best-effort only; never blocks runtime.**

## Invariants
- No PII in telemetry lines; IDs are hashed.
- Sync failures are silent — uptime > observability.
- Store writes are append-only JSONL.

## Related
- [[concepts/AOx4]]
- [[codebase/backend/convex]]
- [[codebase/modules/SoulAnchor]] — Person axis reads the genesis.
- [[architecture/TRUST_BOUNDARIES]] — A&Ox4 is gate class 5.
