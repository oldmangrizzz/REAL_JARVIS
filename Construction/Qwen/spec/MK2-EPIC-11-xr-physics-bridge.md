# MK2-EPIC-11 — XR Passthrough Physics Bridge

**Lane:** Qwen (ambient / UX / data)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** MK2-EPIC-03, MK2-EPIC-04, MK2-EPIC-07
**Priority:** P0
**Canon sensitivity:** LOW

---

## Why

Mark II cannot wait for the full Mark III VR world before JARVIS gets spatial grounding. The operator needs JARVIS functional for day-to-day work while the dark factory builds Mark III on delta. That means Mark II must ship a narrow bridge:

- a passthrough XR workshop that can render the current knowledge graph and stigmergic/pheromone pressure,
- a physics-grounding feed produced by the existing `PhysicsEngine` + `PhysicsSummarizer` seam,
- smoke checks that prove the feed is present and NLB-safe,
- no claim that production MuJoCo or the full immersive VR world is shipped.

This is the "Tony wireframe mockup" layer: a live spatial overlay for reasoning and construction, not yet the fully immersive world.

It is also the spatial/physics substrate for ARC-AGI-3 practice while Mark III is under construction. The bridge should make it easy to run a headless MuJoCo daemon on delta or alpha later, but Mark II must stay functional if that daemon is offline.

## Scope

### In

1. **Physics summary artifact**
   - Add a deterministic demo command or script that instantiates `StubPhysicsEngine`, steps a small scene, summarizes through `PhysicsSummarizer`, and writes:
     - `.jarvis/telemetry/physics_summary.json`
     - `.jarvis/telemetry/physics_summary.txt`
   - The JSON must include at least: `backendName`, `simulatedTime`, `bodyCount`, `movingCount`, `restingCount`, `recentContactCount`, `text`, `generatedAt`.
   - The text must be the bounded natural-language summary from `PhysicsSummarizer`.
   - Raw vectors/arrays must not be written into files that cross into the XR/LLM layer.

2. **Workshop feed wiring**
   - Update `the_workshop.html` to fetch `.jarvis/telemetry/physics_summary.json`.
   - Render a visible "Physics Grounding" panel or spatial node showing:
     - backend name,
     - body/rest/moving/contact counts,
     - bounded summary text.
   - Existing knowledge graph and pheromone rendering must continue to work if physics fetch fails; failure must surface visibly in the status line.

3. **XR mode preservation**
   - Preserve existing WebXR passthrough path:
     - `webxr` optional features include `local-floor`, `dom-overlay`, `hit-test`.
     - `enterPassthrough()` continues to try AR first, then VR fallback.
   - Do not require visionOS platform components for this epic; WebXR/A-Frame static checks are sufficient for Mark II.

4. **Smoke gate**
   - Add `scripts/smoke/xr-physics-bridge.sh`.
   - It must:
     - generate or refresh the demo physics summary,
     - assert `the_workshop.html` references the physics summary source,
     - assert the generated JSON has non-empty `text`,
     - assert the JSON does not contain raw `linearVelocity`, `angularVelocity`, or unbounded body arrays,
     - exit non-zero on failure.

5. **Dashboard/deploy integration**
   - Add `xr-physics-bridge.sh` to `scripts/smoke/all.sh` when EPIC-09 builds the unified smoke runner.
   - If the dashboard state artifact exists, include `xrPhysicsBridge` with pass/fail and last generated timestamp.

6. **Remote MuJoCo-ready seam**
   - Define the environment contract for a future headless physics daemon:
     - `JARVIS_PHYSICS_BACKEND=stub|remote-mujoco`
     - `JARVIS_MUJOCO_URL=http://<host>:<port>`
     - `JARVIS_MUJOCO_TOKEN_FILE=<path>`
   - If the remote daemon is absent, smoke must explicitly report `backendName: "stub"` rather than pretending MuJoCo is active.
   - If the daemon is present, the same `physics_summary.json` shape must be emitted with `backendName: "remote-mujoco"`.

### Out

- Do NOT add production MuJoCo.
- Do NOT add a full VR world.
- Do NOT add live ARC-AGI competition scoring UI.
- Do NOT make visionOS platform availability a blocker.
- Do NOT stream raw physics arrays into the browser, LLM prompt, Convex mirror, or memory bridge.
- Do NOT require Echo, iPhone, or iPad to host the physics engine.

## Acceptance Criteria

- [ ] `scripts/smoke/xr-physics-bridge.sh` exits 0.
- [ ] `.jarvis/telemetry/physics_summary.json` exists and validates required fields.
- [ ] `the_workshop.html` renders a physics grounding surface from that JSON.
- [ ] Physics text crosses the NLB only via `PhysicsSummarizer`.
- [ ] Existing `scripts/smoke/arc-submit.sh` still exits 0.
- [ ] No MuJoCo dependency is introduced.
- [ ] `JARVIS_PHYSICS_BACKEND` contract is documented and smoke output names the active backend honestly.

## Invariants

- Physics is a truth oracle; the LLM/browser sees only bounded summaries.
- XR is a Mark II operational overlay, not a claim that Mark III immersive VR is complete.
- The bridge must degrade visibly when physics telemetry is absent.
- Mark II remains day-to-day functional while Mark III construction runs separately on delta.
- Competition-facing ARC work remains staged: offline practice in Mark II, live submission in Mark III.

## Artifacts

- New or changed:
  - `the_workshop.html`
  - `scripts/smoke/xr-physics-bridge.sh`
  - physics-summary generation script or CLI path
  - `.jarvis/telemetry/physics_summary.json` generated by smoke/runtime, not committed unless it is a fixture under `Tests/Fixtures`
- Response: `Construction/Qwen/response/MK2-EPIC-11-response.md`.
