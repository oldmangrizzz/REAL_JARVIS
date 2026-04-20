# TestSuite

**Path:** `Jarvis/Tests/`
**Dirs:** `JarvisCoreTests/`, `JarvisMacCoreTests/`
**File count:** ~22 Swift test files

## Purpose
XCTest suite covering `JarvisCore` modules and the Mac cockpit store.
Tests are the **load-bearing part** of the remediation cycle — CX fixes
(see [[history/REMEDIATION_TIMELINE]]) land with tests that reproduce
the bug before the fix.

## Layout
- `JarvisCoreTests/` — cross-platform module tests
  (Physics, SoulAnchor, Canon, Pheromind, Oscillator, Memory, Telemetry, ARC, etc.).
- `JarvisMacCoreTests/` — Mac-specific (cockpit store, system hooks).

## Running
- Xcode: scheme `Jarvis`, ⌘U.
- CLI: `xcodebuild -project Jarvis.xcodeproj -scheme Jarvis test` (also
  used by Archon's `validation` node — see [[codebase/workflows/archon]]).
- See [[reference/BUILD_AND_TEST]] for details.

## Conventions
- Physics tests assert on real numbers (gravity = −9.80665 etc.) —
  `StubPhysicsEngine` is NOT a mock.
- SoulAnchor tests use pinned SHA-256 values.
- NLB tests verify that raw physics never leaks into LLM prompts
  ([[concepts/NLB]]).

## Related
- [[history/REMEDIATION_TIMELINE]]
- [[reference/BUILD_AND_TEST]]
