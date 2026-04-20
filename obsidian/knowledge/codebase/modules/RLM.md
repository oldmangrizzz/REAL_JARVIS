# RLM

**Path:** `Jarvis/Sources/JarvisCore/RLM/`
**Files:**
- `PythonRLMBridge.swift` — Python REPL launcher / query caller.
- `ContextualRetrievalBridge.swift` — semantic-memory + pheromone-edge retrieval fused into RLM prompt context.
- `rlm_repl.py` — Python-side recursive prompt symbolizer / ranker.

## Purpose
Bridge to a **Python-side retrieval/language model** helper, plus the
Swift-side retrieval primitive that enriches prompts with durable
context from [[codebase/modules/Memory]] and [[codebase/modules/Pheromind]]
before the Python call.

## Key types
- `RLMQueryResult` — returned structure (`response`, `symbols`, `trace`, `topMatches`).
- `PythonRLMBridge` — the launcher/caller.
  - `query(prompt:query:)` — raw pass-through to Python REPL.
  - `queryWithContext(basePrompt:query:retrieval:limit:)` — convenience that runs the bridge's `enrichedPrompt` first, then delegates to `query`. Cold-memory callers get byte-identical behavior.
- `ContextualRetrievalBridge` — composes `MemoryEngine.retrieveRanked` (pure-read, no side effects) with `PheromindEngine.chooseNextEdge` so recalled memories seed pheromone-favored follow-up edges.
  - `retrieve(query:limit:)` — pure-read, fuses semantic + stigmergic signals.
  - `enrichedPrompt(basePrompt:query:limit:)` — formatted prompt header with retrieval context; cold-memory callers get the base prompt unchanged.
  - `recordOutcome(context:signal:magnitude:agentID:)` — closes the loop. After the RLM observes whether a recalled path helped, the orchestrator deposits pheromone onto every `PheromonePath` in the context (`reinforce` on success, `repel` on failure, `neutral` for pure evaporation). Idempotent w.r.t. the retrieval that produced it — no stale re-amplification. Callers dampen low-confidence signals with a smaller `magnitude`.
- `RetrievalContext` / `RetrievedMemory` / `PheromonePath` — the structured result.

## Invariants
- All traffic with the Python side is through serialized JSON shapes.
- The bridge is **inbound-only** from JARVIS's perspective — Python
  cannot initiate calls back into the process.
- Python side is expected to be a sandboxed child process or
  a network endpoint. Never `eval`.
- `ContextualRetrievalBridge` performs **no persistence, no telemetry, no FIFO mutation** on `retrieve` / `enrichedPrompt` — pure read fusion across two engines, safe for hot-path RLM invocation.
- `recordOutcome` is the **only** write surface the bridge exposes; it funnels into `PheromindEngine.applyGlobalUpdate` which already owns telemetry logging (`logStigmergicSignal`) — the bridge adds no parallel telemetry path.
- `enrichedPrompt()` on cold memory returns the base prompt unchanged, so adding the bridge never changes RLM behavior for callers with empty graphs.

## NLB relevance
Anything the RLM returns that goes into an LLM prompt must first pass
through the [[concepts/NLB|NLB]] summarizer. The retrieval-context
header is a structured symbol block, not free-form LLM output, so it
does **not** itself require NLB summarization — but any downstream
LLM use of the result still does.

## Runtime wiring
`JarvisRuntime.retrievalBridge` is the single shared instance, built
once over the runtime's `memory` and `pheromind`. Control-plane callers
should use that instead of constructing ad-hoc bridges.

## Related
- [[codebase/modules/Memory]] — supplies `retrieveRanked` ranking.
- [[codebase/modules/Pheromind]] — supplies stigmergic edge weights.
- [[concepts/NLB]]
- `scripts/render_briefing.py` — a sibling Python helper.

