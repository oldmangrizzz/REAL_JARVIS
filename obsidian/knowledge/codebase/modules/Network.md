# Network

**Path:** `Jarvis/Sources/JarvisCore/Network/`
**Files:** `PresenceDetector.swift`, `WiFiEnvironmentScanner.swift` (98 lines)

## Purpose
Tiny module — two focused helpers for situational awareness.

- **`PresenceDetector`** — determines whether the operator is physically
  present. Feeds the Person/Place axes of [[concepts/AOx4|A&Ox4]].
- **`WiFiEnvironmentScanner`** — imports `CoreWLAN`, enumerates SSIDs to
  fingerprint the radio environment. The fingerprint is hashed into the
  [[concepts/AOx4|A&Ox4]] Place axis.

## Invariants
- SSIDs are **hashed, not stored plaintext** in telemetry.
- No scans emitted as logs/telemetry without hashing (CX-class privacy
  concern).

## Related
- [[codebase/modules/Telemetry]] — consumes hashes, not raw.
- [[concepts/AOx4]] — Place axis definition.
