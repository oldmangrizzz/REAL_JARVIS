# ARC-AGI 3 BRIDGE SPEC — JARVIS COMPETITION READINESS
**Date:** 2026-04-18
**Author:** Claude Opus (architect pass) — handoff to Qwen3-Coder-Next via Hermes
**Classification:** Cold-resume execution prompt
**Checkpoint target:** 014-arc-agi-bridge

---

## 0. Context (Read This First — You Have Zero Prior Context)

You are working on **REAL_JARVIS** — a native Swift Xcode project (XcodeGen) implementing an Aragorn-class digital person. The project uses:

- **XcodeGen:** `project.yml` generates `Jarvis.xcodeproj`. Run `xcodegen generate` before building.
- **Build:** `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis build`
- **Test:** `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis test`
- **Current state:** Checkpoint 013 complete. 68 tests passing. Build green.

### Orientation Files (READ THESE BEFORE TOUCHING CODE)
```
/Users/grizzmed/REAL_JARVIS/PRINCIPLES.md          — Hard invariants (NLB, hardware sovereignty, A&Ox4)
/Users/grizzmed/REAL_JARVIS/VERIFICATION_PROTOCOL.md — Gate classes (disk, build, execution, signature, A&Ox4)
/Users/grizzmed/REAL_JARVIS/checkpoints/index.md    — Checkpoint history
/Users/grizzmed/REAL_JARVIS/checkpoints/013-finish-build-cockpit-telemetry-hardening.md — Current state
```

### Hard Invariants (Violate These and the Build Is Rejected)
1. **Voice gate file** (`.jarvis/voice/approval.json`) — mode 0600, NEVER modify
2. **Natural Language Barrier** — raw arrays/tensors never cross into LLM context; only summaries
3. **A&Ox4** — Person, Place, Time, Event probes must all pass at >= 0.75 confidence
4. **Build must stay green** — 68+ tests passing, zero regressions
5. **No shared substrate** between JARVIS and any other persona

---

## 1. Mission: Wire JARVIS for ARC-AGI 3

JARVIS is being entered in ARC-AGI 3. The architecture is competition-grade but the **reasoning loop** is not yet connected through the runtime. The ARC-AGI broadcaster exists as a standalone Python WebSocket server. The physics engine protocol exists but only has a stub backend. The goal is to bridge these gaps so ARC-AGI tasks flow through the full JARVIS stack — perception, reasoning, physics, action — not a disconnected solver.

### What Exists (DO NOT REWRITE — extend)

| Subsystem | File | Status |
|-----------|------|--------|
| PhysicsEngine protocol | `Jarvis/Sources/JarvisCore/Physics/PhysicsEngine.swift` | LOCKED — 256 lines, complete protocol with Vec3/Quat/Transform/Body/Ray/Step types |
| StubPhysicsEngine | `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` | Working — 240Hz Euler integrator, sphere/box collision, ground plane |
| PhysicsSummarizer | `Jarvis/Sources/JarvisCore/Physics/PhysicsSummarizer.swift` | Working — NLB-compliant, quantizes physics state to English text |
| JarvisRuntime | `Jarvis/Sources/JarvisCore/Core/JarvisRuntime.swift` | Working — 33 lines, wires all subsystems. Has NO physics engine reference yet |
| AOxFourProbe | `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift` | Working — Person/Place/Time/Event probes, requireFullOrientation() gate |
| SkillSystem | `Jarvis/Sources/JarvisCore/Core/SkillSystem.swift` | Working — registry + native handler execution |
| ARC-AGI Broadcaster | `/Users/grizzmed/ProxmoxMCP-Plus/hugh-agent/project/arc-agi/broadcaster.py` | Standalone Python WebSocket at localhost:8765, ~30fps |
| MasterOscillator | `Jarvis/Sources/JarvisCore/Core/MasterOscillator.swift` | Working |
| PhaseLockMonitor | `Jarvis/Sources/JarvisCore/Core/PhaseLockMonitor.swift` | Working |
| TelemetryStore | `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | Working |
| ConvexTelemetrySync | `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | Hardened (checkpoint 013) |
| VoicePipeline | `Jarvis/Sources/JarvisCore/Voice/` | Gate locked green, DO NOT touch |
| PheromindEngine | `Jarvis/Sources/JarvisCore/Core/PheromindEngine.swift` | Working |
| MemoryEngine | `Jarvis/Sources/JarvisCore/Core/MemoryEngine.swift` | Working |

---

## 2. Tasks (Execute In Order)

### TASK 1: Add PhysicsEngine to JarvisRuntime

**File:** `Jarvis/Sources/JarvisCore/Core/JarvisRuntime.swift`

JarvisRuntime currently has NO physics engine property. Add one.

**What to do:**
1. Add a `public let physics: PhysicsEngine` property
2. Add a `public let physicsSummarizer: PhysicsSummarizer` property
3. Accept physics engine as a parameter with a default of `StubPhysicsEngine()`
4. Initialize the summarizer with defaults
5. Do NOT add physics to the `init(paths:)` convenience — add a new designated initializer that accepts `PhysicsEngine`

**Current init signature (line 16):**
```swift
public init(paths: WorkspacePaths) throws {
```

**Target:** Add a second initializer:
```swift
public init(paths: WorkspacePaths, physics: PhysicsEngine = StubPhysicsEngine()) throws {
```

Make the original `init(paths:)` call through to this one.

**Verification:**
- `xcodegen generate && xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis build` — BUILD SUCCEEDED
- `xcodebuild test` — all existing tests still pass

---

### TASK 2: Create ARC-AGI Grid Adapter

**New file:** `Jarvis/Sources/JarvisCore/ARC/ARCGridAdapter.swift`

ARC-AGI tasks are 2D integer grids (values 0-9, representing colors). JARVIS needs to:
1. Parse ARC grid JSON into native Swift types
2. Convert grids to physics world representations (for spatial reasoning via the engine)
3. Convert grids to NLB-compliant text summaries (for LLM context)

**What to build:**

```swift
// Jarvis/Sources/JarvisCore/ARC/ARCGridAdapter.swift

import Foundation

// MARK: - ARC-AGI Grid Types

public struct ARCGrid: Codable, Sendable, Equatable {
    public let cells: [[Int]]  // row-major, values 0-9
    public var rows: Int { cells.count }
    public var cols: Int { cells.first?.count ?? 0 }

    public init(cells: [[Int]]) {
        self.cells = cells
    }
}

public struct ARCTask: Codable, Sendable {
    public let train: [ARCPair]
    public let test: [ARCPair]
}

public struct ARCPair: Codable, Sendable {
    public let input: ARCGrid
    public let output: ARCGrid
}

// MARK: - Grid → Physics World
// Each cell becomes a static body in the physics engine, positioned by (col, row).
// Color maps to a label. This lets the physics engine's raycast and spatial queries
// operate on ARC grids as physical objects.

public struct ARCPhysicsBridge {
    public let engine: PhysicsEngine

    public init(engine: PhysicsEngine) {
        self.engine = engine
    }

    /// Load an ARC grid into the physics world as static bodies.
    /// Returns a mapping from BodyHandle to grid coordinate.
    @discardableResult
    public func loadGrid(_ grid: ARCGrid, world: WorldDescriptor = WorldDescriptor(gravity: .zero)) throws -> [BodyHandle: (row: Int, col: Int)] {
        try engine.reset(world: world)
        var mapping: [BodyHandle: (row: Int, col: Int)] = [:]

        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let value = grid.cells[row][col]
                guard value != 0 else { continue } // 0 = background, skip

                let handle = try engine.addBody(BodyDescriptor(
                    label: "cell_\(row)_\(col)_v\(value)",
                    shape: Shape(kind: .box, extents: Vec3(0.5, 0.5, 0.5)),
                    mass: 1.0,
                    isStatic: true,
                    initialTransform: Transform(
                        position: Vec3(Double(col), Double(grid.rows - 1 - row), 0)
                    )
                ))
                mapping[handle] = (row, col)
            }
        }
        return mapping
    }
}

// MARK: - Grid → NLB Summary (Natural Language Barrier compliant)
// The LLM sees text, never raw arrays. Per PRINCIPLES.md §6.

public struct ARCGridSummarizer {
    public static let colorNames = [
        0: "black", 1: "blue", 2: "red", 3: "green",
        4: "yellow", 5: "grey", 6: "magenta", 7: "orange",
        8: "cyan", 9: "maroon"
    ]

    /// Summarize a grid as NLB-compliant natural language.
    public static func summarize(_ grid: ARCGrid) -> String {
        var lines: [String] = []
        lines.append("Grid: \(grid.rows) rows x \(grid.cols) columns.")

        // Color distribution
        var counts: [Int: Int] = [:]
        for row in grid.cells {
            for val in row {
                counts[val, default: 0] += 1
            }
        }
        let total = grid.rows * grid.cols
        let dist = counts.sorted { $0.value > $1.value }
            .map { "\(colorNames[$0.key] ?? "?\($0.key)"): \($0.value)" }
            .joined(separator: ", ")
        lines.append("Colors: \(dist) (total \(total) cells).")

        // Spatial patterns (basic)
        let uniqueColors = counts.keys.filter { $0 != 0 }.sorted()
        lines.append("Non-background colors: \(uniqueColors.map { colorNames[$0] ?? "?\($0)" }.joined(separator: ", ")).")

        // Row-by-row compact representation (bounded)
        if grid.rows <= 12 && grid.cols <= 12 {
            lines.append("Layout (row-major):")
            for (i, row) in grid.cells.enumerated() {
                let rowStr = row.map { String($0) }.joined(separator: " ")
                lines.append("  R\(i): \(rowStr)")
            }
        } else {
            lines.append("Grid too large for inline layout (\(grid.rows)x\(grid.cols)).")
        }

        return lines.joined(separator: "\n")
    }

    /// Summarize an ARC task (train pairs + test input) as NLB text.
    public static func summarizeTask(_ task: ARCTask) -> String {
        var sections: [String] = []
        sections.append("ARC Task with \(task.train.count) training pairs and \(task.test.count) test cases.")

        for (i, pair) in task.train.enumerated() {
            sections.append("\n--- Training Pair \(i + 1) ---")
            sections.append("INPUT:\n\(summarize(pair.input))")
            sections.append("OUTPUT:\n\(summarize(pair.output))")
        }

        for (i, pair) in task.test.enumerated() {
            sections.append("\n--- Test Case \(i + 1) ---")
            sections.append("INPUT:\n\(summarize(pair.input))")
            sections.append("(Output is the target to predict.)")
        }

        return sections.joined(separator: "\n")
    }
}
```

**Important:** Create the directory `Jarvis/Sources/JarvisCore/ARC/` first.

**Verification:**
- File exists at the declared path
- Build succeeds
- All existing tests pass

---

### TASK 3: Create ARC-AGI Harness Bridge

**New file:** `Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift`

This is the WebSocket client that connects JarvisRuntime to the ARC-AGI broadcaster. The broadcaster runs at `ws://localhost:8765` and expects JSON messages with these types:

```json
{"type": "state", "payload": {...}}
{"type": "event", "payload": "text"}
{"type": "score", "payload": 0.85}
{"type": "hypothesis", "payload": {"hypothesis": "...", "confidence": 0.9, "strategy": "..."}}
{"type": "grid", "payload": [[0,1,2],[3,4,5]]}
{"type": "action", "payload": "SUBMIT"}
```

**What to build:**
- An actor `ARCHarnessBridge` that:
  1. Connects to the broadcaster WebSocket as a **sender** (not a display client)
  2. Accepts ARC task JSON files from disk
  3. For each task: loads the grid into the physics engine via `ARCPhysicsBridge`, generates the NLB summary via `ARCGridSummarizer`, emits hypothesis/grid/score/action messages to the broadcaster
  4. Maintains a `loopTask` handle with proper cancellation (same pattern as ConvexTelemetrySync after hardening)
  5. Logs all activity to telemetry via `TelemetryStore.append(record:to: "arc_agi_events")`

**Key design constraints:**
- Use `URLSessionWebSocketTask` (Foundation, no external dependencies)
- The bridge is a SENDER to the broadcaster, not a display consumer
- All grid data crossing into LLM context goes through `ARCGridSummarizer` (NLB compliance)
- Raw grid arrays stay on the Swift side of the NLB wall
- Include a `start()` / `stop()` lifecycle matching the ConvexTelemetrySync pattern
- Include `guard !isRunning` in `start()` per the Seam 5 fix from checkpoint 013

**Verification:**
- Build succeeds
- All existing tests pass

---

### TASK 4: Create ARC Grid Adapter Tests

**New file:** `Jarvis/Tests/JarvisCoreTests/ARCGridAdapterTests.swift`

Test the following:

1. `testGridParsing` — Parse a 3x3 grid JSON, verify rows/cols/cell values
2. `testGridToPhysics` — Load a grid into StubPhysicsEngine, verify body count equals non-zero cell count, verify positions match grid coordinates
3. `testGridSummary` — Summarize a known grid, verify output contains row count, column count, and color names
4. `testTaskSummary` — Summarize a full ARCTask with 1 train pair + 1 test case, verify all sections present
5. `testEmptyGridHandling` — All-zero grid loads zero bodies into physics engine
6. `testLargeGridSummaryBounds` — Grid larger than 12x12 produces bounded summary (no inline layout)

**Pattern to follow:** Look at `TTSBackendDriftTests.swift` for the test class structure and `makeTestWorkspace()` helper.

**Verification:**
- All new tests pass
- All existing 68 tests still pass
- Total test count increases

---

### TASK 5: Register ARCHarnessBridge in JarvisRuntime

**File:** `Jarvis/Sources/JarvisCore/Core/JarvisRuntime.swift`

Add the ARC harness bridge as an optional subsystem in JarvisRuntime:

1. Add `public let arcBridge: ARCHarnessBridge?` property
2. In the designated initializer, accept an optional `arcBroadcasterURL: URL? = nil` parameter
3. If the URL is provided, create the bridge and start it
4. If nil, set `arcBridge = nil` (ARC mode is opt-in, not always-on)

**Verification:**
- Build succeeds
- All tests pass
- JarvisRuntime can be initialized with and without the ARC bridge

---

### TASK 6: Write Checkpoint 014

**New file:** `checkpoints/014-arc-agi-bridge.md`

Follow the exact format of checkpoint 013. Include:

1. **TL;DR:** ARC-AGI 3 bridge wired — grid adapter, physics bridge, harness WebSocket, runtime integration
2. **Modified files** with descriptions
3. **New files** with descriptions
4. **Build verification:** `xcodegen generate` → exit 0, `xcodebuild build` → BUILD SUCCEEDED, `xcodebuild test` → all tests pass (report count)
5. **How to resume cold** — exact commands to verify the bridge works:
   ```
   cd /Users/grizzmed/REAL_JARVIS
   xcodegen generate
   xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis test
   ```
6. **What's next** — MuJoCo backend integration, VLM pipeline for grid perception, Unity visualization

**Update** `checkpoints/index.md` to add checkpoint 014.

---

## 3. Balls and Strikes Framework

For each task, before writing code, assess whether the approach is correct:

- **STRIKE** = the gap is real, the fix is necessary, implement it
- **BALL** = the gap doesn't exist or the proposed approach is wrong, skip it with documented reasoning

If you find that a task as specified would violate a hard invariant or is architecturally wrong, call it a BALL and explain why. Do NOT blindly implement something that would break the build or violate PRINCIPLES.md.

---

## 4. Build Cadence

After EACH task:
1. `xcodegen generate` (if you touched project.yml or added new files to source directories)
2. `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis build`
3. `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis test`
4. If build fails, fix before moving to next task
5. Report: STRIKE (implemented) or BALL (skipped with reason), build status, test count

---

## 5. What NOT To Do

- Do NOT modify voice gate files (`.jarvis/voice/approval.json`)
- Do NOT modify `PhysicsEngine.swift` (protocol is LOCKED)
- Do NOT add external dependencies (no SPM packages, no CocoaPods changes)
- Do NOT modify existing passing tests (only ADD new tests)
- Do NOT pass raw arrays into any context that could reach an LLM — use summarizers
- Do NOT create shared substrate between JARVIS and any other persona
- Do NOT modify PRINCIPLES.md, VERIFICATION_PROTOCOL.md, or SOUL_ANCHOR.md
- Do NOT guess at APIs — read the actual source files before writing code that uses them
- Do NOT modify the ARC-AGI broadcaster (`broadcaster.py`) — it's outside this repo

---

## 6. File Tree Reference

```
Jarvis/Sources/JarvisCore/
  Core/
    JarvisRuntime.swift        ← MODIFY (Tasks 1, 5)
    SkillSystem.swift           — read-only reference
    MasterOscillator.swift      — read-only reference
    PhaseLockMonitor.swift      — read-only reference
    PheromindEngine.swift       — read-only reference
    MemoryEngine.swift          — read-only reference
  Physics/
    PhysicsEngine.swift         ← READ-ONLY (protocol, LOCKED)
    StubPhysicsEngine.swift     ← READ-ONLY (reference backend)
    PhysicsSummarizer.swift     ← READ-ONLY (NLB summarizer pattern)
  ARC/                          ← CREATE (new directory)
    ARCGridAdapter.swift        ← CREATE (Task 2)
    ARCHarnessBridge.swift      ← CREATE (Task 3)
  Telemetry/
    AOxFourProbe.swift          — read-only reference
    ConvexTelemetrySync.swift   — read-only reference (actor lifecycle pattern)
    TelemetryStore.swift        — read-only reference
  Voice/                        — DO NOT TOUCH

Jarvis/Tests/JarvisCoreTests/
    ARCGridAdapterTests.swift   ← CREATE (Task 4)

checkpoints/
    014-arc-agi-bridge.md       ← CREATE (Task 6)
    index.md                    ← UPDATE (Task 6)
```

---

## 7. Success Criteria

When all tasks complete:
- [ ] `JarvisRuntime` has a `physics` property (defaults to `StubPhysicsEngine`)
- [ ] `ARCGridAdapter.swift` exists with `ARCGrid`, `ARCTask`, `ARCPhysicsBridge`, `ARCGridSummarizer`
- [ ] `ARCHarnessBridge.swift` exists with WebSocket client actor, proper lifecycle
- [ ] 6+ new tests pass in `ARCGridAdapterTests.swift`
- [ ] Total test count >= 74 (68 existing + 6 new minimum)
- [ ] Build is green
- [ ] Checkpoint 014 written and indexed
- [ ] Zero hard invariant violations

---

**End of spec. Cook.**
