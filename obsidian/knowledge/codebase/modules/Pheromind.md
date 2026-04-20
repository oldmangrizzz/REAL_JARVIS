# Pheromind

**Path:** `Jarvis/Sources/JarvisCore/Pheromind/`
**Files:** `PheromoneEngine.swift` (139 lines)

## Purpose
**Ternary-signal pheromone graph**: small, synchronous diffuser of
`.reinforce` / `.neutral` / `.repel` signals across an edge graph.

Doctrine: [[concepts/Pheromind]].

## Key types
- `TernarySignal` — `Int`, `Codable`, `Sendable`. `-1, 0, +1`.
- `EdgeKey` — `Hashable`/`Codable`/`Sendable`. Two endpoints.
- `PheromoneDeposit` — `Codable`/`Sendable`. Signal + decay meta.
- `PheromoneEngine` — in-memory engine with diffusion + decay.

## Input sources
- [[codebase/modules/Oscillator]] — PLV bands → ternary signal.
- [[codebase/modules/Interface]] — operator intents can deposit.
- [[codebase/modules/Memory]] — knowledge-graph traversal cost.
- [[codebase/modules/RLM]] — `ContextualRetrievalBridge.recordOutcome`
  turns retrieval outcomes into `PheromoneDeposit`s per retrieved path,
  then delegates to `applyGlobalUpdate` so telemetry is unified (no
  parallel log path). Closes the retrieval feedback loop: *edges that
  led to useful memories get reinforced, dead-end edges decay.*

## Consumers
- [[codebase/modules/ControlPlane]] — routes workload based on deposits.
- [[codebase/modules/Harness]] — Archon uses deposits as soft priors.
- [[codebase/modules/RLM]] — reads current gradient to bias retrieval.

## Invariants
- No unbounded growth: deposits decay, edges expire.
- Engine is purely local; NEVER cross-network without explicit plumbing.

## Related
- [[concepts/Pheromind]] — concept doc.
- [[concepts/NLB]] — Pheromind state can be summarized into LLM prompts
  through the summarizer, never directly.
