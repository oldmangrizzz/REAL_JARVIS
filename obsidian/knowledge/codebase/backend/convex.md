# convex

**Path:** `convex/`
**Files:**
- `schema.ts` — Convex data model.
- `control_plane.ts` — control-plane mutations/queries.
- `jarvis.ts` — JARVIS-facing endpoints.
- `node_registry.ts` — node enrollment + heartbeats.

## Purpose
Convex is the **external backing store for cross-node coordination** —
complementary to (not replacing) [[codebase/modules/Telemetry]]'s local
JSONL. Used by [[codebase/modules/ControlPlane]] to publish ternary
signals and read shared state, and by Archon for execution traces.

## Schema (from `schema.ts`)
- `execution_traces` — workflowId, stepId, inputContext, outputResult,
  status (success|failure|pending), timestamp.
  Index: `by_workflow_step`.
- `stigmergic_signals` — nodeSource, nodeTarget, ternaryValue (-1|0|1),
  agentId, pheromone, timestamp.
  Indexes: `by_edge`, `by_agent`, `by_timestamp`.
- `recursive_thoughts` — sessionId, thoughtTrace[], memoryPageFault,
  timestamp.

## Roles
- Stigmergic pheromone store: feeds [[codebase/modules/Pheromind]]
  with shared, decaying reinforcement signals.
- Archon execution trace log: per-step status for the workflow engine
  (see [[codebase/workflows/archon]]).
- Node registry: where a Linux worker announces itself post-enrollment.

## Invariants
- Ternary values are the **only** allowed kind for stigmergic edges.
- Convex is **not** canon — it is ephemeral coordination state.
- No PII leaves the Mac; only derived signals land here.

## Related
- [[codebase/modules/Pheromind]]
- [[codebase/modules/ControlPlane]]
- [[codebase/workflows/archon]]
