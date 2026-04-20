# ARC

**Path:** `Jarvis/Sources/JarvisCore/ARC/`
**Files:** `ARCGridAdapter.swift`, `ARCHarnessBridge.swift` (346 lines)

## Purpose
Bridge JARVIS into the **ARC-AGI** evaluation loop. Loads ARC task JSON
files, converts grids into embodied physics worlds (via [[codebase/modules/Physics]]),
and emits hypothesis/grid/score/action messages over a WebSocket sender.

See doctrine: [[concepts/ARC-AGI-Bridge]].

## Key types
- `ARCGrid` (`Codable`/`Sendable`/`Equatable`) — single colored grid.
- `ARCTask` (`Codable`/`Sendable`) — train/test pairs.
- `ARCPair` (`Codable`/`Sendable`) — input/output grid pair.
- `ARCHarnessBridge` (**actor**) — WebSocket sender-only; connects to
  `ws://localhost:8765` (the ARC-AGI broadcaster).

## Flow
1. Load `ARCTask` from JSON.
2. `ARCGridAdapter` converts each grid into a physics world.
3. Hypothesis is generated, scored against targets.
4. Bridge emits `hypothesis` → `grid` → `score` → `action` messages.

## HARD INVARIANT
The bridge is **sender-only**. It is not a display client. It does not
render. It does not accept remote commands. One direction: JARVIS → broadcaster.

## Related
- [[concepts/ARC-AGI-Bridge]]
- [[codebase/modules/Physics]] — grids become physics worlds.
- [[codebase/modules/Harness]] — Archon workflow harness.
- `ARC_AGI_BRIDGE_SPEC.md` at repo root.
