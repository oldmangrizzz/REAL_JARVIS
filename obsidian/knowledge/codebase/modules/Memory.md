# Memory

**Path:** `Jarvis/Sources/JarvisCore/Memory/`
**Files:** `MemoryEngine.swift` (328 lines)

## Purpose
Durable knowledge: a content-addressed graph (`KnowledgeNode` + `KnowledgeEdge`)
plus a `MainContext` struct for per-session state. Hashes use SHA-256
(CX-037: prior truncation bug fixed — see [[history/REMEDIATION_TIMELINE]]).

## Key types
- `MainContext` — `Codable`/`Sendable`. Per-session memory root.
- `KnowledgeNode` — canonical entity in the graph.
- `KnowledgeEdge` — labeled relation.
- `KnowledgeGraph` — aggregate node/edge store.
- `MemoryEngine` — public API.

## Hashing
Imports `CryptoKit`. SHA-256 is used for `stableHash` (node identity +
edge key). **Never truncate** — CX-037 was a 64-bit truncation that made
collisions possible; fixed by using full digest.

## Related
- [[codebase/modules/SoulAnchor]] — some node kinds are Canon-bound and
  require dual-signature to persist.
- [[codebase/modules/Canon]] — canonical corpus registry; memory can
  reference canon entries by id.
- [[history/REMEDIATION_TIMELINE]] — CX-037 context.

## Gotchas
- Persistence format is JSON-Codable; if you change field names, you
  break old snapshots — write a migration.
- Don't stuff raw LLM output here; apply NLB summarizer first
  ([[concepts/NLB]]).
