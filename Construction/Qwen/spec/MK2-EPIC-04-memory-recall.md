# MK2-EPIC-04 — Memory Graph Persistence + Recall API

**Lane:** Qwen (ambient / data)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** —
**Priority:** P1
**Canon sensitivity:** LOW (memory is operational, not canon)

---

## Why

`MemoryEngine` (SHA256-hashed, telemetry-witnessed) is the substrate for JARVIS's continuity. Today:
- Writes land in `Storage/knowledge-graph.json` and telemetry.
- Recall works in-process via `MemoryEngine.fetch(entity:)`.

Missing for Mark II:
- **Stable on-disk format** with version header + migration path.
- **Recall API** exposed through the tunnel so the Watch/Phone/Mac clients can query recent episodic/semantic memory.
- **Ambient recall** — when AMBIENT-001 ships, the ambient pipeline needs low-latency "what did we discuss about X in the last 24 h" queries.

## Scope

### In

1. **Persistence format v1** at `Storage/knowledge-graph.v1.json`:
   - JSON root: `{ "version": 1, "genesisSha256": "...", "createdAt": ISO8601, "entries": [MemoryEntry], "indexSha256": "..." }`.
   - `MemoryEntry`: `{ id, kind (episodic|semantic|somatic), payload, entities[], witnessSha256, createdAt, prevSha256 }` forming a Merkle-ish chain.
   - Migration: on load, if `knowledge-graph.json` is v0 (no version field), migrate to v1 writing to `.v1.json` and renaming v0 to `.v0.bak`. Migration logs `memory.migrated.v0_to_v1` telemetry.

2. **Recall API** in `MemoryEngine`:
   - `func recall(query: RecallQuery) async -> RecallResult` where `RecallQuery` supports: `entities: [String]`, `kinds: Set<MemoryKind>`, `since: Date?`, `limit: Int (≤ 200)`.
   - Returns entries sorted by `createdAt desc`, with integrity verified (chain walk cost ≤ O(limit)).
   - `RecallResult` includes `integrityOK: Bool` and `chainBreakAt: MemoryID?` for forensics.

3. **Tunnel surface** in `Shared/TunnelModels.swift`:
   - New request `JarvisRemoteRequest.memoryRecall(RecallQuery)`.
   - New response `JarvisRemoteResponse.memoryRecalled(RecallResult)`.
   - Role-gated: only roles with `memory.read` capability (macHost, macDesktop, iPhone, iPad, watchOS with ambient-gateway capability) may call it. EPIC-02's capability registry enforces.

4. **Client helper** in `MobileShared/JarvisMobileShared/JarvisRecallClient.swift`:
   - `func recall(entities: [String], since: TimeInterval, limit: Int) async throws -> [MemoryEntry]`.
   - Used by Watch ambient pipeline and Mac/PWA cockpit.

5. **Dashboard recall panel** (wired but minimal): Mac cockpit gains a "Memory" tab with an entity search box + last-20 recall table.

### Out

- Do NOT introduce an external vector DB. NLB §1.1 forbids shared vector stores.
- Do NOT implement semantic embeddings in this epic — substring + entity-tag match is Mark II.
- Do NOT expose recall to unauthenticated clients.

## Acceptance Criteria

- [ ] New tests ≥ 8: v0→v1 migration, v1 load roundtrip, chain integrity pass, chain break detection, recall-by-entity, recall-by-kind, recall-by-time-window, recall honors limit.
- [ ] Recall latency on 10k-entry graph ≤ 200 ms P95 (simulated entries in a perf test).
- [ ] Tunnel recall request rejected for unauthorized role (test in `TunnelAuthTests` — depends on EPIC-02 landing first; if EPIC-02 not yet merged, gate this assertion behind `#if EPIC_02_LANDED` with a TODO comment referencing the order).
- [ ] Mac cockpit Memory tab renders without error (UI test).

## Invariants

- NLB §1.1: no shared vector store.
- Integrity witness preserved; chain-break triggers `memory.integrity.violation` telemetry + iMessage ping via forge notifier.

## Artifacts

- New: `Memory/RecallQuery.swift`, `Memory/RecallResult.swift`, `Memory/MemoryMigration.swift`, `MobileShared/JarvisRecallClient.swift`, `Tests/MemoryRecallTests.swift`, `Tests/MemoryMigrationTests.swift`.
- Modified: `Memory/MemoryEngine.swift`, `Shared/TunnelModels.swift`, `Host/JarvisHostTunnelServer.swift`, `Jarvis/Mac/Sources/JarvisMacCore/JarvisMacCockpitView.swift`.
- Response: `Construction/Qwen/response/MK2-EPIC-04.md`.
