# MK2-EPIC-07 — Telemetry + Dashboard Enrichment

**Lane:** Qwen (data / UX)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** MK2-EPIC-01
**Priority:** P1
**Canon sensitivity:** LOW

---

## Why

The forge dashboard (`https://forge.grizzlymedicine.icu`) already shows task board + RustDesk pill. Jarvis-side telemetry writes to JSONL locally and syncs to Convex, but there's **no operator-facing live view** of Jarvis's own health: voice gate state, tunnel connections, mesh display health, recent intents, Ralph iter counts per in-flight forge task. Mark II delivers a unified operator dashboard.

## Scope

### In

1. **Telemetry schema completion** at `docs/telemetry/SCHEMA.md`:
   - Enumerate every telemetry event name emitted by Swift + forge + services.
   - Field contracts per event. Required vs optional. Witness-hash semantics.
   - This is documentation; no code change unless an event name is inconsistent.

2. **Convex mutations audit** in `convex/`:
   - Ensure `telemetry:push` accepts every event listed in SCHEMA with strict validator.
   - Add `telemetry:recent(limit)` query returning the last N events across all sources, role-gated.

3. **Dashboard enrichment** at `/opt/swarm-forge/dashboard/server.py` (on Delta) + `dashboard/templates/index.html`:
   - New section **Jarvis Live**:
     - Tunnel connections count, voice gate state, last mesh action, current telemetry burst rate.
     - Data source: Convex `telemetry:recent` over HTTPS, cached 2 s.
   - New section **Ralph Runtime**: per-task iter/budget/lesson-count by reading `/opt/swarm-forge/state/ralph/<tid>.json`.
   - Link each task row to a modal that renders the latest `<tid>.md` Ralph scratchpad (read-only).

4. **Heartbeat push**:
   - Jarvis host emits `heartbeat` telemetry every 30 s with `{voiceGateOK, tunnelClients, memoryVersion, lastIntentAt}`.
   - Dashboard shows GREEN if heartbeat < 60 s old, YELLOW < 300 s, RED otherwise.

### Out

- Do NOT add Grafana / Prometheus. Convex + in-process JSONL is the Mark II tier.
- Do NOT expose telemetry publicly. Dashboard MUST remain behind the forge auth layer (Caddy basic auth or bearer).

## Acceptance Criteria

- [ ] Schema doc enumerates ≥ 30 event names with field contracts.
- [ ] `curl https://forge.grizzlymedicine.icu/tasks` returns JSON with new `ralph_iter`, `ralph_budget` fields.
- [ ] Heartbeat gap > 60 s visibly turns the health pill YELLOW in < 5 s.
- [ ] Unauthorized `/tasks` requests rejected (HTTP 401/403).
- [ ] New tests ≥ 4: schema parser, heartbeat emitter, Convex mutation validator, dashboard unauthorized-reject.

## Invariants

- PRINCIPLES §2: telemetry does not carry raw audio, raw canon content, or private keys.
- EPIC-02 auth applies to any dashboard mutation/control endpoint.

## Artifacts

- New: `docs/telemetry/SCHEMA.md`, `Telemetry/HeartbeatEmitter.swift`, `Tests/HeartbeatEmitterTests.swift`.
- Modified: `convex/telemetry.ts` (or equivalent), `/opt/swarm-forge/dashboard/server.py`, `/opt/swarm-forge/dashboard/templates/index.html`.
- Response: `Construction/Qwen/response/MK2-EPIC-07.md`.
