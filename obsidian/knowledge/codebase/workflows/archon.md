# archon

**Path:** `Archon/default_workflow.yaml`

## Purpose
**Archon** is the external, deterministic workflow engine. JARVIS's
[[codebase/modules/Harness|Harness]] module talks to Archon via the
`ArchonWorkflow` model; Archon executes the canonical build/remediation
cycle.

## Default workflow (`default_workflow.yaml`)
Linear DAG:

1. `planning` — "Analyze codebase and emit a deterministic build plan."
2. `implementation` — "Generate code strictly from planning outputs."
3. `validation` — `xcodebuild -project Jarvis.xcodeproj -scheme Jarvis build test`.
4. `review` — "Review changes against validation evidence and telemetry."

Each node depends on the previous one.

## Invariants
- Every mutation is hash-signed through [[codebase/modules/Harness]].
- `validation` runs the real XCTest suite — there is no stub.
- Execution traces land in Convex (`execution_traces` table — see
  [[codebase/backend/convex]]).

## Related
- [[codebase/modules/Harness]]
- [[codebase/backend/convex]]
- [[codebase/testing/TestSuite]]
