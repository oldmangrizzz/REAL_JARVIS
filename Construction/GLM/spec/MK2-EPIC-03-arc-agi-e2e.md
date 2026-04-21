# MK2-EPIC-03 — ARC-AGI End-to-End Submission Path

**Lane:** GLM (infra / orchestration)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4; references `ARC_AGI_BRIDGE_SPEC.md`
**Depends on:** MK2-EPIC-01
**Priority:** P1
**Canon sensitivity:** LOW

---

## Why

ARC-AGI 3 is the program's public forcing function (per `JARVIS_INTELLIGENCE_REPORT.md` §1.5 and `PRINCIPLES.md` rationale). Today:
- `ARC/ARCGridAdapter.swift` exists — grid → physics bodies.
- `ARC/ARCHarnessBridge.swift` exists — polls `~/arc-agi-tasks/` every 5 s.
- `Physics/StubPhysicsEngine.swift` exists — 240 Hz Euler.
- `RLM/PythonRLMBridge.swift` exists — subprocess bridge.

Missing: a **single-command path** from "here is a task file" → "submission JSON emitted" that exercises all of: grid ingest → physics simulation → RLM inference → candidate grid emission → submission write + telemetry.

## Scope

### In

1. **Orchestrator** `Jarvis/Sources/JarvisCore/ARC/ARCSubmissionOrchestrator.swift`:
   - `func run(taskFileURL: URL) async throws -> ARCSubmissionArtifact`
   - Loads task JSON, feeds first training input into `ARCPhysicsBridge.loadGrid(...)`.
   - Calls `PythonRLMBridge.propose(gridState:timestep:)` with a reasonable budget (≤30 s wall, ≤4096 RLM tokens).
   - Receives candidate output grid, validates shape against task's output dimensionality.
   - Returns `ARCSubmissionArtifact { taskId, candidateGrid, latencyMs, ttl, witnessSha256 }`.

2. **CLI entry** `scripts/arc/submit.sh`:
   - Usage: `scripts/arc/submit.sh <task.json> [--out DIR]`.
   - Invokes the CLI `jarvis arc-submit --task <path> --out <dir>`.
   - Writes `<taskId>-submission.json` and `<taskId>-telemetry.jsonl` to `--out` (default `~/arc-agi-submissions/`).
   - Exits 0 on success, non-zero on any error with a human-readable last-line diagnostic.

3. **CLI wire-up** in `Jarvis/App/main.swift`:
   - Add `arc-submit` subcommand using the orchestrator.
   - On success, emit telemetry events: `arc.submit.start`, `arc.submit.physics_loaded`, `arc.submit.rlm_response`, `arc.submit.validated`, `arc.submit.done`.
   - On failure, emit `arc.submit.failed` with reason code (invalid_json, shape_mismatch, rlm_timeout, physics_nan, etc.).

4. **Canned demo task** `arc-agi-tasks/demo/SAMPLE-0001.json` — small 3×3 identity task so the smoke test doesn't require network.

5. **Smoke test** `scripts/smoke/arc-submit.sh`:
   - Runs `submit.sh` on `SAMPLE-0001.json`, asserts output JSON has `candidateGrid` matching expected identity output, and `witnessSha256` non-empty.

### Out

- Do NOT build the online competition submission uploader (Mark III).
- Do NOT add MuJoCo. Stub physics is sufficient.
- Do NOT modify the RLM Python side beyond adding a small `propose_grid(state) -> [[int]]` wrapper if not present. Keep the RLM sovereign per NLB §1.1.

## Acceptance Criteria

- [ ] `scripts/smoke/arc-submit.sh` exits 0.
- [ ] Submission JSON schema matches ARC-AGI public submission schema (validate against schema file committed at `docs/arc/submission.schema.json`).
- [ ] Telemetry events present in the output `.jsonl` in the expected order.
- [ ] New tests ≥ 5: orchestrator happy path, invalid JSON, RLM timeout, shape mismatch, witness tamper.
- [ ] Latency budget: demo task end-to-end ≤ 10 s on M2 Pro.

## Invariants

- PRINCIPLES §2: RLM runs locally (existing Python subprocess). No cloud inference for ARC.
- Physics engine output summarized by `PhysicsSummarizer` for any operator-visible log lines (NLB-compliant natural-language output).

## Artifacts

- New: `ARC/ARCSubmissionOrchestrator.swift`, `arc-agi-tasks/demo/SAMPLE-0001.json`, `scripts/arc/submit.sh`, `scripts/smoke/arc-submit.sh`, `docs/arc/submission.schema.json`, `Tests/ARCSubmissionTests.swift`.
- Modified: `Jarvis/App/main.swift`, possibly `RLM/PythonRLMBridge.swift` + `Jarvis/Sources/JarvisCore/RLM/python/rlm_bridge.py` for `propose_grid`.
- Response: `Construction/GLM/response/MK2-EPIC-03.md`.
