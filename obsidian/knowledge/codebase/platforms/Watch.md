# Watch

**Path:** `Jarvis/Watch/`
**Files:**
- `Extension/RealJarvisWatchApp.swift` — watchOS `@main`.
- `Extension/Info.plist`.
- `Sources/JarvisWatchCore/`:
  - `JarvisWatchCockpitView.swift`
  - `JarvisWatchCockpitStore.swift`
  - `JarvisWatchVitalMonitor.swift` — reads HealthKit vitals.

## Purpose
Wrist-level presence + vitals. The Watch feeds a tiny but important
signal into the rest of JARVIS: operator heart-rate context (used for
Presence / A&Ox4 Person-continuity checks) and quick "here" gestures.

## Invariants
- HealthKit data **stays on device**. Only derived ternary signals cross
  the tunnel (e.g., `presence: .reinforce`).
- Watch cannot authorize voice playback (must happen on Mac).

## Related
- [[codebase/modules/Network]] — Presence detector overlaps here.
- [[concepts/AOx4]] — Person continuity.
- [[codebase/platforms/Mac]]
