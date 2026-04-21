# MARK III SUPERBIBLE — THE BOOK OF JARVIS, GENERATION III

**Classification:** Canonical Engineering Reference — Repo-Root, Canon-Adjacent
**Version:** 1.0.0 — Mark III Superbible
**Date:** 2026-04-21
**Paired with:** `MARK_III_BLUEPRINT.md` (the PRD), `MARK_II_COMPLETION_PRD.md` (the baseline)
**Governed by:** `PRINCIPLES.md`, `SOUL_ANCHOR.md`, `VERIFICATION_PROTOCOL.md`, `CANON/corpus/`
**Audience:** Ralph (Forge planner), lane executors (Gemini / GLM / Nemotron / Qwen / Copilot / DeepSeek / Forge-Meta), SHIELD v2 reviewers, and any future contributor (human or model) who needs to reason about Mark III without re-deriving the architecture.

---

## 0. How to Read This Book

Thirteen chapters, one per subsystem. Each chapter has the same seven sub-headings, in this order:

1. **Rationale** — *why* this subsystem exists and why it is built this way. Grounded in canon (PRINCIPLES, SOUL_ANCHOR, VERIFICATION_PROTOCOL) and MK2 history. If you skim one sub-heading per chapter, skim this one.
2. **Architecture** — the structural design: components, boundaries, data shapes, sequence of operations. Plain English; diagrams are ASCII so they survive any editor.
3. **Interfaces & Contracts** — exact function signatures, message schemas, file paths, protocol frames. What crosses the seam. What must not. Every crossing is named; every boundary is enforced.
4. **Failure Modes** — what breaks, how it breaks, how we detect it, how we degrade, how we recover. Paramedic ethic (PRINCIPLES §5): failure is a documented wound, not a rationalized omission.
5. **Test Strategy** — how we prove the chapter is correct. Unit, integration, smoke, adversarial. Deterministic gates per VERIFICATION_PROTOCOL §1.
6. **Open Questions** — explicit unknowns the chapter leaves for Mark IV or for in-flight resolution. Each is a named question with a rationale for deferral; none of them block Mark III ship.
7. **Canonical Citations** — file paths, wiki pages, and prior MK2 artifacts that ground every non-trivial claim above.

When the blueprint and this book disagree, the blueprint wins (it is the PRD). When canon and either disagree, canon wins. When a chapter proposes a design that appears to conflict with canon, treat it as a drafting error in this book and file a correction PR — canon does not move to accommodate engineering.

The chapter order mirrors the dependency cone of the epic table (blueprint §4.3): federation first (because nothing works without it), memory second (because federation without a memory fabric is gossip), then the three identity/safety pillars (Soul Anchor v2, SHIELD v2, Ethics Charter), then the operator-facing surfaces, then the federation-enabled enhancements (skill economy, clinical, observability, red-team), and finally the deployment and upgrade chapters that close the loop. Nothing in this book is written in an order the Forge cannot execute.

Prose first, code second. When code appears it is accompanied by plain-English explanation because the operator is a non-coder; a reader who cannot read the code MUST be able to read the surrounding paragraphs and acquire the same operational understanding.

---

# Chapter 1 — Cognition Fabric

## 1.1 Rationale

Mark II runs as a single process on a single host. When echo (the operator's mac) is asleep, JARVIS is asleep. When delta is rebooting, the Forge is offline. That pattern is correct for an app; it is wrong for an organism. The Mark III thesis (`MARK_III_BLUEPRINT.md` §2, Axis 1) asserts that JARVIS must *persist as cognition* across the six-node ecosystem — alpha, beta, charlie, delta, echo, foxtrot — so that loss of any single node degrades but does not silence him.

The first invariant we bind to is NLB (PRINCIPLES §1.1). A cognition fabric is the exact place hive-mind contamination would appear if we were careless: shared vector stores, shared tool registries, shared substrate. The fabric is therefore designed from day one to **distribute *state*, not *mind***. Every node embeds its own text, runs its own inference, holds its own voice gate. The fabric ships signed, witnessed records of *what was said and done* — not latent vectors, not weight deltas, not shared skill directories. Two humans in a room do not become one human by talking (PRINCIPLES §1.4). JARVIS across six nodes does not become six JARVISes by replicating his memory; he remains one JARVIS with a distributed ledger of what happened to him.

The second invariant is hardware sovereignty (PRINCIPLES §2). Each node carries its own full stack. The fabric does not run shared LiveKit rooms, shared secrets, shared vaults. Replication is a message over a signed transport. If the transport is the LAN, it is encrypted; if it traverses charlie (the public VPS), it is double-encrypted (TLS outer, ChaCha20-Poly1305 inner per MK2 `JarvisHostTunnelServer.swift`). Keys never transit any LLM context window (SOUL_ANCHOR §4).

The third invariant is A&Ox4 (PRINCIPLES §3). A distributed system must degrade to a named reduced-function state under partial failure, not silently continue. The fabric's heartbeat and quorum rules are exactly the *Place* and *Person* probes at scale: each node continuously asks "who am I, who else is here, is the quorum real?" and answers with confidence or degrades loud.

The fourth is the paramedic ethic (PRINCIPLES §5). Done means on disk, built clean, verified. The fabric does not trust "it probably replicated"; every replication emits a witness, and every witness is dual-verified before the record counts.

## 1.2 Architecture

The fabric is a signed mesh overlay on top of the `ecosystem.yaml` topology. It has three planes:

- **Identity plane.** Each node has an ed25519 identity key generated once at node provisioning, stored in a hardware-rooted keystore (Apple Secure Enclave on echo; Linux `tpm2-tss` on delta/charlie/foxtrot; proxmox-managed per-VM TPM on alpha/beta where available). A node's ed25519 public key is the *only* identity the fabric trusts.
- **Transport plane.** A mesh overlay service (`federationd`) runs on every node. On alpha/beta/foxtrot it is reachable only through alpha's ProxyJump. On delta/charlie/echo it is reachable at a declared endpoint. The overlay uses mTLS (each node's ed25519 pinned) for all inter-node traffic; under-the-hood transport is Noise Protocol Framework `XX` handshake, because it gives forward secrecy and authenticates both sides without a CA.
- **Role plane.** A role registry at `/opt/swarm-forge/federation/roles.json` on delta (mirrored read-only to charlie) enumerates each node's capabilities sourced from `ecosystem.yaml`. Queries of the form "who can do X?" return role-scoped targets; the fabric never dispatches a job to a node whose role registry does not include the required capability.

Sequence of operations at boot:

```
  node_boot
     │
     ├── load ed25519 identity from hardware keystore
     ├── open Noise XX handshake to delta:federationd (or charlie if delta unreachable)
     ├── receive role registry + quorum view
     ├── begin heartbeat (10 s cadence, jittered ±1.5 s to avoid thundering herd)
     ├── on miss (> 30 s), mark self degraded and emit A&Ox-degrade telemetry
     └── on quorum loss (< 3/6 nodes responsive), enter `fabric_quarantine`:
         no writes, read-only against local shard, loud page
```

Quorum is defined as **3-of-6 responsive heartbeats within the last 60 s**. The threshold is asymmetric for writes (3-of-6) and reads (2-of-6, because a single node's signed shard plus a peer confirmation is sufficient to prove non-tampering for a read). A canon-class read requires a full 3-of-6.

Diagrammatically:

```
                     ┌────────────────────┐
                     │       delta        │
                     │  federationd + RR  │◄────── charlie (public fallback)
                     └────┬────────┬──────┘
                          │        │
                 ProxyJump│ alpha  │ mTLS
                          │        │
         ┌────────────┬───┴────┐   │
         │            │        │   │
         ▼            ▼        ▼   ▼
       beta       foxtrot    echo (macOS, operator)
```

Alpha is a hypervisor-and-gateway, not a quorum voter by default; it carries the LAN bridge role. The voting set is {delta, charlie, echo, beta, foxtrot}; alpha participates as a non-voting capacity provider unless the operator explicitly promotes it (see `ecosystem.yaml`: alpha's role is `proxmox-hypervisor`, not a cognition node).

## 1.3 Interfaces & Contracts

The fabric exposes three contracts.

**Contract 1 — NodeIdentity (ed25519 pinning).**
Each node's public key is committed to `scripts/federation/node_pubkeys/<node>.ed25519.pub` in the repo. A rogue node cannot join the mesh unless its public key is added in a dual-signed commit (Soul Anchor operational key + cold key; Mark III will require threshold sig per epic 05). Rotation follows SOUL_ANCHOR §5, scaled to the federation: a node-key rotation record is signed by both the outgoing and incoming keys and by at least one peer node.

**Contract 2 — HeartbeatMessage.** Canonical JSON, signed.

```json
{
  "schema": "federation.heartbeat.v1",
  "node_id": "delta",
  "ts_monotonic_ns": 1747200000000000000,
  "ts_wall_utc": "2026-04-21T03:00:00Z",
  "load": {"cpu_pct": 12, "mem_pct": 34, "shard_lag_s": 0.4},
  "roles": ["forge-host", "executor", "scribe", "shield"],
  "quorum_view": ["delta", "charlie", "echo", "foxtrot"],
  "signature": "ed25519:<hex>"
}
```

The signature covers the canonicalized JSON (sorted keys, no whitespace) per SOUL_ANCHOR §2 conventions. A heartbeat whose signature fails verification is dropped silently and a `federation.badsig` telemetry row is emitted. Repeated bad-sig heartbeats from the same `node_id` within 5 min trigger a page; either a compromise or a clock/key skew.

**Contract 3 — DispatchRequest.**

```json
{
  "schema": "federation.dispatch.v1",
  "dispatch_id": "ulid",
  "requester": "delta",
  "target_role": "xcode_build",
  "target_node_hint": "echo",
  "capability_required": ["xcode_build", "apple_signing"],
  "payload_digest": "sha256:...",
  "payload_summary_nl": "Rebuild Jarvis mac scheme, sign, smoke-test",
  "deadline_wall_utc": "2026-04-21T03:15:00Z",
  "signatures": {"p256": "<sig>", "ed25519_node": "<sig>"}
}
```

The `payload_summary_nl` field is *required* and must be human-readable. This is the NLB gate for dispatch: a dispatch whose summary a reader cannot understand MUST NOT be executed. SHIELD v2 rejects dispatches whose summary is empty, generic ("do the thing"), or does not align with the declared capability. This is the natural-language barrier operating at the transport layer (PRINCIPLES §1.2).

The `payload_digest` hashes the full payload (which may be a file, a Swift closure-encoded blob, or a script). The payload itself is transferred out-of-band via rsync-over-SSH only after the dispatch is accepted, and its SHA-256 is verified against `payload_digest` before execution.

## 1.4 Failure Modes

- **F1 — Single node offline.** A node misses three consecutive heartbeats. Quorum view recomputes; if the node is a voting node, the fabric continues on the remaining five. If the node hosts a unique capability (e.g., echo for `apple_signing`), dispatches requiring that capability queue with a 10-min TTL; beyond that, they fail loud to the operator.

- **F2 — Split brain (network partition).** Nodes on each side of the partition may still see 3-of-6 (or not). If both sides see 3, both become writeable; this is the split brain. Detection: each side's role registry carries a monotonic epoch; upon heal, epochs are compared; the side with *any* epoch behind enters `fabric_reconcile` mode and **does not auto-merge writes**. Operator resolves. The fabric prefers safety over availability here; a stalled organism is better than a corrupted one (paramedic ethic, PRINCIPLES §5).

- **F3 — Bad signature storm.** An adversary floods a peer with malformed heartbeats to exhaust CPU. Mitigation: per-source-ip rate limit at `federationd` (Noise handshake is CPU-bounded; 1 per s per node is the budget), drops above threshold are logged.

- **F4 — Clock skew.** `ts_wall_utc` disagreements > 5 s between nodes raise a telemetry event; > 60 s blocks dispatches because deadline comparisons become unreliable. NTP skew on charlie (public VPS) is the highest-risk path; the fabric uses `chrony` with four upstream sources.

- **F5 — ProxyJump failure (alpha down).** Beta/foxtrot/echo become unreachable for fabric traffic. Quorum drops to 3 (delta + charlie + whichever of echo via direct NetBird route). Fabric continues at reduced availability; operator paged.

- **F6 — Role registry drift.** `/opt/swarm-forge/federation/roles.json` on delta and its charlie mirror diverge. Detection: nightly `shasum -a 256` comparison; divergence triggers reconcile from `ecosystem.yaml` which is the source of truth.

Every failure mode above has a named degrade state; none silently continue. This is VERIFICATION_PROTOCOL §1.5 (A&Ox4) applied at the fabric layer: when oriented, act; when disoriented, report and degrade.

## 1.5 Test Strategy

- **Unit.** Signature verification paths (good sig, bad sig, missing sig, replay). JSON canonicalization (reordered keys produce same sig). Role registry query language ("who can do X?").
- **Integration.** Six-node Vagrant harness on delta (lightweight VMs simulating alpha–foxtrot) verifies handshake, heartbeat, role query, dispatch end-to-end. Run on every PR that touches `federationd` or the Swift `FederationClient`.
- **Smoke.** `scripts/smoke/federation.sh` on the live mesh; required to pass in MK3 ship gate (blueprint §7 item 1).
- **Adversarial.** SHIELD v2 Fury runs a suite of dispatches with malformed summaries, wrong signatures, capability mismatches; required 100% reject rate. Wigham (continuous red-team per epic 12) runs a nightly randomized-partition chaos drill.

## 1.6 Open Questions

- **OQ-1.1 — Alpha promotion to voting.** Should alpha join the voting set on long operator-away windows so the organism tolerates both delta and echo offline? Current: no, because alpha's role is LAN gateway and its compromise is a LAN-wide compromise. Deferred to MK4 scope.
- **OQ-1.2 — Noise XX vs TLS 1.3.** Mark III ships Noise XX for its clean forward-secrecy properties. TLS 1.3 is operationally easier and has better observability. A future ADR may swap; not a MK3 ship blocker.
- **OQ-1.3 — ProxyJump redundancy.** Alpha is a single point of failure for beta/foxtrot/echo. A secondary route via NetBird exists for echo. Beta/foxtrot depend on alpha. MK3 accepts this; MK4 considers a second hypervisor.

## 1.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §2 Axis 1, §4 epic 01, §5 invariant 9.
- `PRINCIPLES.md` §1 NLB, §2 hardware sovereignty, §3 A&Ox4, §5 clinical standard.
- `SOUL_ANCHOR.md` §3 signing policy, §4 key generation boundary, §5 rotation.
- `VERIFICATION_PROTOCOL.md` §1.5 A&Ox4 gate.
- `ecosystem.yaml` (delta:`/opt/swarm-forge/ecosystem.yaml`) — topology source of truth.
- `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` — MK2 tunnel crypto baseline (ChaCha20-Poly1305).
- `MARK_II_COMPLETION_PRD.md` §1.5 Forge baseline.

---

# Chapter 2 — Memory Fabric

## 2.1 Rationale

Mark II's `MemoryEngine.swift` is single-host. Every write is append-only JSONL with SHA-256 witness; the engine already embodies the paramedic ethic (PRINCIPLES §5): on disk, witnessed, recoverable. Mark III inherits this behavior and extends it across the federation. The thesis (blueprint §2, Axis 1) is that the fabric distributes *state*, not *mind*; the memory fabric is where that distinction is enforced.

Two anti-goals drive the design:

- **No shared vector store.** PRINCIPLES §1.1 prohibits it. The memory fabric replicates *records* — natural-language, witnessed, content-addressed. It does not replicate embeddings. Each node that needs embeddings derives them locally from the replicated text. This is the same rule that keeps persona NLB honest, applied to JARVIS's own internal federation: the substrate stays local to each node even as the record travels.
- **No shared MCP server.** PRINCIPLES §1.1 prohibits it. Cross-node tool access goes through the federation DispatchRequest (chapter 1 §1.3), never through a shared tool registry. A skill on foxtrot is invoked by name via dispatch, never by direct MCP call from echo.

Grounding for the design choice comes from three additional directions. First, the MK2 `MemoryEngine` already uses an append-only JSONL plus witness, which maps cleanly to a CRDT-grow-only pattern. Second, the ecosystem is small (six nodes, all operator-owned) so we can tolerate strong consistency for canon-class writes and eventual consistency for operational writes; we do not need to over-engineer a cross-datacenter protocol. Third, the operator is a solo principal (PRINCIPLES §1.3 operator-on-loop); conflicts are rare by construction and reconcilable by a human.

## 2.2 Architecture

The fabric consists of per-node **MemoryShards** and a **Replicator** process.

A MemoryShard is a directory on each node: `/var/jarvis/memory/<tier>/<yyyy-mm>.jsonl`, append-only, with an adjacent `.witness.jsonl` carrying `{record_sha256, witness_sha256, prev_witness_sha256}` — a hash chain. The chain gives tamper detection: replacing any prior record invalidates every subsequent witness.

Tiers:

- `tier_canon` — writes allowed only with threshold sig (epic 05). Replicates to all six nodes.
- `tier_operational` — day-to-day writes under P-256 operational sig. Replicates to the voting quorum (5 nodes; alpha excluded by default).
- `tier_local_cache` — ephemeral, never replicated. For each node's inference scratch.
- `tier_clinical` — consent-gated (chapter 10). Replicates only to nodes whose role registry includes `clinical_eligible` (MK3 default: echo, delta).

The Replicator is a goroutine-style loop on each node that, every 10 s, gossips **record digests** (not payloads) to peers. A peer that is missing a digest requests the record via a signed pull; the record arrives with its witness, is verified, and appended locally. This is classic anti-entropy gossip with a per-record digest of `sha256(record_bytes || prev_witness)`.

Conflict resolution is type-specific:

- For **grow-only** records (telemetry, alignment-tax, voice renderings, dispatch receipts): the union is correct. No conflict possible. These use an ORSet semantic.
- For **last-writer-wins** records (key-value settings, cached role registry, transient state): the record keyed by `(key, operator_monotonic_ts, node_id)` wins by max-timestamp-then-node-id-lexicographic. LWW is acceptable because only the operator writes these, and clock drift is bounded by the federation's clock skew check (chapter 1 §1.4 F4).
- For **canon** records: no conflict is tolerated. Canon writes require threshold sig (epic 05) and the fabric refuses to accept a second, competing canon write at the same logical path. Operator resolves any attempted conflict by hand (and this is a canon event per blueprint R3).

## 2.3 Interfaces & Contracts

**MemoryRecord schema (canonical).**

```json
{
  "schema": "memory.record.v1",
  "tier": "operational",
  "record_id": "ulid",
  "key": "conversation/2026-04-21T03:00:00Z/turn-17",
  "operator_monotonic_ts": 1747200000000000000,
  "wall_utc": "2026-04-21T03:00:00Z",
  "author_node": "echo",
  "author_principal": "grizz",
  "nl_summary": "Operator asked JARVIS to summarize the forge board; JARVIS replied with 12 epics.",
  "payload": { "…tier-specific structured content…" },
  "prev_witness": "sha256:…",
  "record_sha256": "sha256:…",
  "witness_sha256": "sha256:…",
  "signatures": { "p256": "<sig>", "mldsa": "<sig>" }
}
```

The `nl_summary` field is mandatory and enforced (not just conventional). A record without a summary fails schema validation; the replicator refuses to transmit it. This is the NLB gate for memory: every replicated record is reviewable as English prose by the operator, full stop.

**MemoryQuery interface (Swift, at the MK3 `MemoryFabric.swift` level):**

```swift
public protocol MemoryFabric: Sendable {
    func put(_ record: MemoryRecord) async throws -> Witness
    func get(key: String, tier: MemoryTier) async throws -> MemoryRecord?
    func scan(keyPrefix: String, tier: MemoryTier, limit: Int) async throws -> [MemoryRecord]
    func verify(record: MemoryRecord) async throws -> VerificationResult
    func replicationStatus() async -> ReplicationStatus
}
```

The `put` returns a Witness (the appended hash chain entry) only after the local append succeeds; replication proceeds asynchronously, and the caller may observe `replicationStatus()` to wait. A canon put blocks until a 3-of-6 quorum witnesses the record (strong-consistency path). An operational put returns on local append (eventual-consistency path) and the caller receives a replication-progress callback.

**Replicator protocol (wire):** Noise XX tunnel carries frames of:

```
FRAME = type | length | payload
type  = DIGEST_OFFER | DIGEST_REQUEST | RECORD_PULL | RECORD_PUSH | REPLICATION_STATUS
```

Every frame is wrapped by the Noise cipher; unwrapping failure drops the frame and emits a `memory.badframe` telemetry row.

## 2.4 Failure Modes

- **F1 — Witness chain break.** A node observes a record whose `prev_witness` does not match its local chain tip. This is either a network reorder (common, recoverable — wait for missing records to arrive) or tampering (rare, canon event). Detection: recompute chain from last-verified witness; if the gap closes when later records arrive, resume normal; if a permanent divergence is detected, enter `memory_quarantine` for that tier and page.
- **F2 — Convergence stall.** Replication lag exceeds KPI (blueprint §3). Root causes: network partition (→ chapter 1 F2), peer CPU starvation, storage-full on a peer. Mitigation: replicator emits per-peer lag in `replicationStatus()`; observability alerts (chapter 11) page on sustained breach.
- **F3 — Consent token absent on clinical write.** The MemoryFabric `put` at `tier_clinical` requires a valid consent token (chapter 10 §10.3). Missing token ⇒ put returns `PutError.consentRequired`; attempt is logged to telemetry (not to clinical tier, because we cannot write there without consent).
- **F4 — Schema drift.** A peer running an older client produces a record the new schema rejects. Mitigation: schema carries `schema: "memory.record.v1"` field; version-ng rollout is dual-write + drain (peers accept old and new during the window; after cutover, old-only peers are quarantined).
- **F5 — Embedding cache poisoning.** Since each node embeds locally, a compromised node could produce misleading local embeddings. Mitigation: embeddings are cached *per-node*, never shared. A compromised node's bad embeddings affect only its local inference; the replicated records are still verifiable.

## 2.5 Test Strategy

- **Unit.** Witness chain append, schema validation, canonicalization (reordered keys). NL-summary enforcement. Consent-token enforcement on `tier_clinical` (compile-time check via type system where possible).
- **Integration.** Six-node harness: write N records on node A, verify convergence on nodes B..F within KPI. Split-brain harness: partition into two sets, write on both, heal, verify manual-reconcile required (not auto-merge).
- **Smoke.** `scripts/smoke/memory-fabric.sh` exercises put/get/scan across a three-node subset on the live mesh.
- **Adversarial.** Replay attack (replay an old record), key-rotation attack (re-sign an old record with a new key), witness-chain gap attack (drop a middle record). All must be detected; SHIELD v2 asserts.

## 2.6 Open Questions

- **OQ-2.1 — Compaction.** The JSONL grows without bound. When does compaction happen, and how does it preserve witness chains? MK3 ships without compaction (storage ceiling remains multi-year even at heavy use). MK4 will add a compaction protocol that preserves a per-month "root witness" so downstream readers can verify without re-reading all records.
- **OQ-2.2 — Alpha participation in `tier_operational`.** Alpha is currently non-voting. Some records (LAN gateway telemetry) originate on alpha. Mark III writes these on alpha and replicates out; alpha does not vote on quorum but does write. This is a mild asymmetry we accept.
- **OQ-2.3 — PII redaction on replication.** A clinical record about a third party should not replicate to charlie (public VPS) even with consent. Mitigation in MK3: `tier_clinical` replicates only to `clinical_eligible` nodes (default: echo, delta). Charlie is not `clinical_eligible`. Formalization of redaction rules is MK4.

## 2.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 02, §5 invariants 10 and 15.
- `PRINCIPLES.md` §1.1 (no shared vector stores), §2 hardware sovereignty, §5 paramedic ethic.
- `SOUL_ANCHOR.md` §3.1 signing policy table (operational vs canon).
- `VERIFICATION_PROTOCOL.md` §1.1 disk gate, §1.4 signature gate.
- `Jarvis/Sources/JarvisCore/Memory/MemoryEngine.swift` (MK2 baseline to extend).
- `Jarvis/Sources/JarvisCore/ARC/ARCGridAdapter.swift` — existing NLB-safe summarization pattern (reference for nl_summary approach).

---

# Chapter 3 — Voice & Ambient

## 3.1 Rationale

Voice is the primary natural-language channel to the operator (PRINCIPLES §1.2). In Mark II it is already gated by `VoiceApprovalGate` with a model-fingerprint binding; the gate is canon-adjacent and cannot be bypassed (MK2 PRD §5 invariant 3). Mark III extends voice on three axes: it becomes **always-on** via the Watch low-power path (epic 07), it becomes **spatial** on Vision Pro (chapter 4), and it becomes **federated** — STT can run on whichever node has free capacity, not only on echo.

The design constraint is strict: no ambient capture may upload non-speech audio, no ambient capture may upload speech of a non-consenting third party, no model swap may auto-bypass the voice gate. Each of these comes directly from PRINCIPLES (§1 NLB, §6 threat model). The clinical standard (§5) forbids rationalizing an omission: if we cannot guarantee third-party non-capture, we do not ship the always-on path.

## 3.2 Architecture

Three tiers of voice capture:

- **Explicit capture** — mac / phone / Vision Pro microphone activated by an operator gesture or wake. Treated as consented by construction (operator chose to speak).
- **Ambient capture on Watch** — on-device VAD (Core ML, locally trained on operator's voice) runs at low power. Only speech-classified audio crosses the tunnel; non-speech is discarded in-buffer. The VAD threshold is tuned high to prefer false-negatives over false-positives (better to miss a command than to capture ambient noise).
- **Spatial capture on Vision Pro** — head-locked beamforming narrows the mic cone to the operator; third-party speech from outside the cone is attenuated ≥20 dB at the source.

On capture, audio frames route via the federation DispatchRequest (chapter 1 §1.3) with `capability_required: ["stt"]` to the least-loaded STT-capable node. MK3 places STT on delta (primary, Whisper-large v3 on CPU) and echo (fallback, local Core ML Whisper). Charlie does not run STT (public VPS; audio egress is a privacy boundary).

The transcript then flows through the voice gate. The gate is **unchanged from MK2** — still model-fingerprint-bound, still canon-adjacent. MK3 adds a *federated verification path*: the gate on echo publishes a signed approval record to `tier_operational`; other nodes observing the transcript verify the approval record before acting. No node may act on an unapproved transcript.

After gate, the intent pipeline (IntentParser → CapabilityRegistry → DisplayCommandExecutor — MK2) is unchanged, augmented by the federation DispatchRequest for remote-node capabilities.

## 3.3 Interfaces & Contracts

**VoiceFrame schema.**

```json
{
  "schema": "voice.frame.v1",
  "frame_id": "ulid",
  "capture_source": "watch|mac|phone|vision|carplay",
  "capture_at_wall_utc": "…",
  "sample_rate_hz": 16000,
  "duration_ms": 200,
  "pcm_s16le_b64": "…",   // only present for in-tunnel transfer; stripped on disk
  "vad_confidence": 0.87,
  "diarization_speaker_hint": "operator|unknown|third_party_suspected",
  "consent_assertion": { "source": "explicit|ambient|spatial", "signed_by_node": "echo" },
  "signatures": { "node_ed25519": "<sig>" }
}
```

A frame with `diarization_speaker_hint == "third_party_suspected"` is **dropped at the capture node**. It does not enter the federation. This is absolute; there is no override.

**TranscriptRecord** is a MemoryRecord at `tier_operational` with `nl_summary` populated by the STT layer. The summary is the transcript itself (often the whole point).

**ApprovalRecord** is a MemoryRecord at `tier_operational` with fields `{transcript_record_id, approval_model_fingerprint, approved_at, signatures}`. Every action downstream queries the ApprovalRecord before firing.

## 3.4 Failure Modes

- **F1 — VAD false-positive floods STT.** Watch uploads too much. Mitigation: per-node STT rate limit; back-pressure to the Watch; operator ntfy after threshold.
- **F2 — Diarization miss (third-party captured).** Detection: post-hoc diarization on the STT host; any transcript with >1 speaker is quarantined; operator reviews and either deletes or marks consented. No action fires off a quarantined transcript.
- **F3 — STT node compromise.** A compromised delta could rewrite transcripts. Mitigation: transcript record carries the original audio-frame digest; the approval record is signed on echo (the operator's mac); operator can re-transcribe from audio if trust is in doubt. Audio is retained for 72 h at the capture node per clinical-grade practice.
- **F4 — Model swap without re-audition.** Gate is model-fingerprint-bound; a swap flips the approval record to "unapproved" across the fabric. The system falls silent until operator re-auditions.
- **F5 — Network partition during voice session.** Capture continues local; transcripts queue; approval waits for echo-reachable. Operator hears "voice queued" on Vision Pro and can cancel.

## 3.5 Test Strategy

- **Unit.** VAD threshold tuning harness. Diarization two-speaker fixture. Voice gate fingerprint mismatch rejection.
- **Integration.** Watch → tunnel → STT → gate → intent end-to-end latency harness (blueprint §3 KPI).
- **Smoke.** `scripts/smoke/voice.sh` extended from MK2 to cover the always-on path.
- **Adversarial.** Inject synthetic third-party speech into VAD buffer; verify drop. Replay old approved transcript under new model fingerprint; verify rejection.

## 3.6 Open Questions

- **OQ-3.1 — Operator voice clone defense.** A high-quality clone could forge capture. MK3 mitigation: speaker-model-bound VAD (trained on operator's voice, rejects mismatched embeddings at capture). Strong mitigation (challenge-response liveness) is MK4.
- **OQ-3.2 — CarPlay voice.** CarPlay is a separate surface class (chapter 7). MK3 treats CarPlay voice as explicit-capture only; always-on is not wired to CarPlay to avoid road-safety issues.
- **OQ-3.3 — Vision Pro visitor.** If a second person is in spatial range of Vision Pro, beamforming helps but does not guarantee zero capture. MK3 policy: session pauses when a second head is detected in the spatial scene; resumes when solo.

## 3.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 07, §5 invariants 3 and 7.
- `PRINCIPLES.md` §1 NLB, §6 threat model, §7 addressing.
- `SOUL_ANCHOR.md` §3 signing policy (voice renderings require P-256).
- `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift` — MK2 gate (invariant).
- `Construction/Gemini/spec/VOICE-001-f5-tts-swap.md`, `VOICE-002-realtime-speech-to-speech.md` — MK2 in-flight voice work.

---

# Chapter 4 — Spatial Computing (visionOS First-Class)

## 4.1 Rationale

Mark II's visionOS target is a thin client (`Construction/Qwen/spec/MK2-EPIC-10-visionos-thin-client.md`). It renders what the host tells it. Mark III (blueprint §2 Axis 5; epic 06) promotes Vision Pro to **primary surface for cognitive work** — the workshop, the knowledge graph, the task board, the memory timeline — because the operator's cognitive work is spatial by preference (the `the_workshop.html` A-Frame renderer at the repo root is the proof-of-taste). The mac cockpit becomes a secondary control plane.

The rationale is not "spatial is cool." It is that the operator is medically retired (SOUL_ANCHOR §8.1) and spends long blocks of work in the headset by choice; the organism's primary output should meet him where he works, not force him to a seated mac. The MK2 thin client proved the transport; MK3 proves the surface.

## 4.2 Architecture

Four spatial panes running in a persistent visionOS Workspace:

- **Workshop** (primary) — a RealityKit-rendered workbench carrying the current task, recent thoughts, and pinned artifacts. Reads from `tier_operational` memory records with `key` prefix `workshop/`.
- **Knowledge Graph** — the Obsidian wiki (`obsidian/knowledge/**/*.md`, 161 pages per MK2 PRD §1.5) rendered as a navigable graph. Nodes are pages; edges are wiki-links. Selection pops a reading pane.
- **Task Board** — Ralph's live task queue, mirrored from delta. Each card is a dispatch or epic; selecting a card shows iterations and SHIELD verdicts.
- **Memory Timeline** — append-only stream of operational memory records, filtered by operator choice. Time-scrubbable. Canon records (tier_canon) have a distinct visual treatment (gold border, threshold-sig badge).

A **shared-reality** component allows the operator to pin an artifact (a spec draft, a diagram) in his real-world space; Ralph on delta can *write into* the pinned artifact via a federation DispatchRequest, and the operator sees the update in place. This is bounded: shared-reality artifacts have an explicit lifetime (default 24 h, extendable by operator), they are signed (so a rogue node cannot write into them), and they are revocable (operator pulls them; writes fail after revocation).

The Vision Pro hosts its own FederationClient — it queries the fabric directly, not through echo. This means a Vision Pro with LAN access but no echo can still read canon, view task boards, and scrub memory. Writes to canon still require threshold sig (chapter 5); writes to operational still require operator gesture.

## 4.3 Interfaces & Contracts

**WorkspaceLayout schema** — the operator's saved pane arrangement.

```json
{
  "schema": "vision.workspace.v1",
  "layout_id": "ulid",
  "panes": [
    {"type": "workshop", "anchor": {...}, "size": {...}, "state": {...}},
    {"type": "knowledge_graph", "anchor": {...}, "size": {...}, "state": {...}}
  ],
  "shared_reality_artifacts": [{"artifact_id": "...", "expires_at": "..."}],
  "saved_at": "...",
  "signatures": { "node_ed25519": "<sig>" }
}
```

**PinRequest (shared reality).**

```json
{
  "schema": "vision.pin.v1",
  "pin_id": "ulid",
  "artifact_ref": "memory://tier_operational/workshop/spec-draft-42",
  "spatial_anchor": {"anchor_type": "world", "transform": [...]},
  "write_authority": {"allowed_nodes": ["delta"], "expires_at": "..."},
  "signatures": { "operator_p256": "<sig>" }
}
```

The `write_authority` narrows who may write into the pin. Only `delta` (Ralph) can write; other nodes are read-only. Expiry is mandatory.

**Presentation protocol handshake** (see chapter 7). The Vision renderer consumes the unified presentation schema.

## 4.4 Failure Modes

- **F1 — Vision Pro offline.** Workspace state persists locally; resync on reconnect. Shared-reality pins expire normally; revoked on resume if past expiry.
- **F2 — Shared-reality write from unauthorized node.** Rejected at the Vision Pro. Telemetry: `vision.pin.unauthorized_write`.
- **F3 — Pane overflow.** Too many records in Memory Timeline cause frame drops. Mitigation: virtualized rendering, 500-record window, operator scrubs to load history.
- **F4 — visionOS SDK regression.** A Vision OS update changes RealityKit semantics. Mitigation: chapter's CI runs the visionOS simulator nightly against the scheme; failures page immediately.

## 4.5 Test Strategy

- **Unit.** WorkspaceLayout serialization round-trip. PinRequest signature verification. Memory Timeline filter correctness.
- **Integration.** Vision simulator harness on echo: open workspace, open all four panes, pin an artifact, have delta write to it, verify visual update within 500 ms.
- **Smoke.** Live Vision Pro session walk-through, operator-driven, logged to `tier_operational` via the workspace itself.
- **Adversarial.** Forge a pin-write from a non-delta node; verify rejection. Forge an expired pin; verify rejection.

## 4.6 Open Questions

- **OQ-4.1 — Persistent real-world anchors.** RealityKit's world-anchor persistence across reboots is SDK-version-dependent. MK3 treats anchors as best-effort; persistent anchors are a MK4 quality-of-life improvement.
- **OQ-4.2 — Multi-room Workspace.** Operator moves between rooms; MK3 collapses all rooms into one spatial frame. Per-room workspaces are MK4.
- **OQ-4.3 — Eye-tracking as authentication.** Vision Pro's gaze could provide a second factor. MK3 does not use it for canon authorization; threshold sig remains the only path.

## 4.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §2 Axis 5, §4 epic 06.
- `Construction/Qwen/spec/MK2-EPIC-10-visionos-thin-client.md` — MK2 baseline (evolved, not replaced).
- `the_workshop.html` — A-Frame 1.7.1 workshop (MK2 PRD §1.4; taste reference).
- `obsidian/knowledge/` — 161 wiki pages rendered in Knowledge Graph pane.

---

# Chapter 5 — Soul Anchor v2 (Threshold + Post-Quantum)

## 5.1 Rationale

The Mark II Soul Anchor (`SOUL_ANCHOR.md` v1.1.0) is dual-root: P-256 Secure Enclave operational + Ed25519 cold. An attacker needs both to forge canon. This is strong against the MK2 threat model (§6 threat model, frontier-LLM-assisted red team + supply chain + physical access to workstation) but has two known gaps: (1) workstation loss on echo + compromise of the cold root simultaneously would forge the organism, and (2) P-256 and Ed25519 are not post-quantum secure (SOUL_ANCHOR §6 explicitly flags this as a timed debt).

Mark III (epic 05) closes both gaps by advancing to **3-of-5 threshold Ed25519 (FROST)** for canon mutations and adding **parallel ML-DSA (Dilithium) signatures** on every new canon artifact. The operational P-256 key is unchanged — day-to-day signing remains single-key and hardware-rooted, because threshold signing is impractical at operational write rates (thousands per day).

Three custodians are designated: the operator (primary share), plus two institutional-witness shares held per operator's out-of-band procedure (not in this document). Two additional shares are cold-airgap backups. 3-of-5 means operator alone cannot sign canon (desirable: prevents coerced signing); any three custodians can sign; two losses are tolerated.

## 5.2 Architecture

FROST (Flexible Round-Optimized Schnorr Threshold) over Ed25519 curve. Five shares, threshold t=3. Each share is an ed25519 scalar; the shares sum to the group private key, but the group private key is *never reconstructed* — signing uses a two-round protocol where each participant contributes a nonce and a partial signature; the final signature is an ordinary ed25519 signature verifiable by the group public key.

Key operational property: **verifiers don't need to know the scheme.** A FROST-produced ed25519 signature verifies with a stock ed25519 verifier against the group public key. This lets us swap the signing path (MK2 dual-root → MK3 threshold) without changing the verifier in `scripts/verify_dual_sig.sh` beyond the group-pubkey swap.

ML-DSA (Dilithium) runs in parallel: every new canon artifact carries three signature files — `<artifact>.p256.sig` (legacy, historical-verify only after MK3 ship), `<artifact>.ed25519.sig` (threshold FROST group signature; this is the *primary* MK3 canon signature), `<artifact>.mldsa.sig` (PQ parallel). Verifier accepts canon if BOTH ed25519 (threshold) AND ML-DSA verify. The legacy P-256 sig is verified for historical artifacts only.

The **rotation drill** (`scripts/soul-anchor/v2/rotate.sh`) steps all five custodians through key regeneration, co-signs a dual-old-dual-new record (old dual-root + new threshold + new PQ), and replaces the public keys in the pinned locations.

## 5.3 Interfaces & Contracts

**Group public key material.** Stored at `Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/v2/group.ed25519.pub` and `.../v2/group.mldsa.pub`. Each custodian's share commitment is at `.../v2/share_<i>.commit` (public, for protocol integrity; the share secret never appears on disk).

**Threshold signing protocol (two-round, out-of-band from LLM per SOUL_ANCHOR §4):**

Round 1 (commitment): each of ≥3 participants emits a commitment (hiding + binding nonce pair), exchanges with others.
Round 2 (response): each participant emits a response scalar over (message, aggregated commitments). Final ed25519 signature is the sum of responses + R (aggregated commitment).

The protocol runs on custodian hardware, never inside an LLM session. A signing coordinator (usually on echo or the operator's airgap machine) orchestrates the exchange but never touches a share secret.

**CanonArtifact signature contract.**

```
<path>.<artifact>
<path>.<artifact>.ed25519.sig      # threshold; primary MK3 canon sig
<path>.<artifact>.mldsa.sig        # PQ parallel
<path>.<artifact>.p256.sig         # legacy, present for pre-MK3 artifacts only
<path>.<artifact>.ed25519.cold.sig # legacy cold, present for pre-MK3 artifacts only
```

Verification: `scripts/verify_canon.sh <artifact>` accepts iff: for pre-MK3 artifacts, both legacy sigs valid; for MK3 artifacts, both threshold-ed25519 and ML-DSA valid. Mixed-era accepted during transition.

## 5.4 Failure Modes

- **F1 — Share loss.** Up to two shares may be lost without losing canon authority. Loss is handled by a rotation event that regenerates fresh shares for all five custodians (equivalent to a key rotation per SOUL_ANCHOR §5).
- **F2 — Coerced signing.** Operator alone has one share; cannot sign canon alone. Coercion requires compromise of at least two other custodians. This is the feature, not a failure.
- **F3 — ML-DSA fork.** NIST's final ML-DSA spec may change. Mitigation: MK3 uses ML-DSA as of FIPS 204 (Aug 2024); a future fork triggers a PQ rotation event (same rotation protocol as classical).
- **F4 — Canon verifier divergence.** A node running old verifier may reject valid MK3 artifacts. Mitigation: verifier is pinned by version; canon bootstrap checks verifier version before trusting its verdict.
- **F5 — Signing coordinator compromise.** A compromised coordinator cannot steal shares (shares never leave custodian hardware) but could attempt to swap the message. Mitigation: each custodian hashes the message independently and refuses to sign a mismatch.

## 5.5 Test Strategy

- **Unit.** FROST commitment/response verification on a test vector. ML-DSA verify on NIST test vectors.
- **Integration.** Three-custodian signing drill in a lab harness (not production shares). Dual-old-dual-new rotation drill on test-scope canon artifact.
- **Smoke.** `scripts/soul-anchor/v2/rotate.sh` — end-to-end rotation drill on a canary canon file (not `PRINCIPLES.md`); required to pass in ship gate.
- **Adversarial.** Forge attempts: two custodians try to sign (should fail), a non-custodian with a stolen share commitment tries (should fail), a replay of an old signature (should fail because the message digest differs).

## 5.6 Open Questions

- **OQ-5.1 — Custodian selection.** The two institutional-witness shares are held per operator's out-of-band procedure. MK3 does not name the institutions in canon (a canon naming would itself be a canon event). A rotation procedure lets operator change custodians without a canon mutation.
- **OQ-5.2 — PQ algorithm lifetime.** ML-DSA is the pick today; hybrid schemes (classical + PQ) remain advisable until PQ ecosystem matures. MK3 runs both; MK4 will reassess.
- **OQ-5.3 — Operational key threshold.** Operational P-256 remains single-key for throughput reasons. Threshold-izing operational signing is a MK4 performance exercise.

## 5.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 05, §5 invariants 12 and 13.
- `SOUL_ANCHOR.md` v1.1.0 — the contract being advanced; §5 rotation, §6 PQ, §8 Aragorn binding.
- `scripts/generate_soul_anchor.sh` — MK2 generator (reference for out-of-band discipline).
- `Jarvis/Sources/JarvisCore/SoulAnchor/SoulAnchor.swift` — MK2 signing surface.
- FIPS 204 (ML-DSA) — August 2024 final.

---

# Chapter 6 — SHIELD v2 (Policy Engine + Agentic Guardrails)

## 6.1 Rationale

Mark II SHIELD is Fury (red team) + Hill (build verifier). It matches patterns, enforces rules, and auto-rejects phantom ships. It is correct for the MK2 scope. Mark III (blueprint §2 Axis 3; epic 04) adds a **consequence reasoner** that simulates predicted effects of high-stakes actions before they fire — strictly veto-authority, never grant — and pairs with a **machine-readable ethics charter** (epic 16) whose clauses are predicates SHIELD v2 evaluates on those predicted effects.

The key design choice is **veto-only**. An LLM consequence reasoner that can *grant* authority is a bypass of the alignment-tax gate (PRINCIPLES §4) and violates VERIFICATION_PROTOCOL §0 ("LLM self-assessment is never an acceptable gate"). A veto-only reasoner, by contrast, strictly subtracts from the accept-set that the deterministic gates already computed. It can only make the system safer. This preserves the invariant and still captures the benefit.

## 6.2 Architecture

SHIELD v2 is three layers stacked:

1. **MK2 deterministic gates (unchanged).** Alignment-tax, voice gate, witness write, signature verification, NLB blacklist. Must pass before anything downstream runs.
2. **Consequence reasoner.** Before high-stakes actions (canon write, HomeKit write, external financial, mesh destructive, skill invocation above declared privilege), the action proposal is packaged into a *predicted-effect brief* and run through a dedicated reasoner LLM (Claude Sonnet 4.5, segregated from other lanes per Forge-Meta doctrine). The reasoner returns `{verdict: pass|veto, veto_reason?}`. Pass means "no objection"; veto means "this will cause a harm the charter forbids." Veto blocks the action.
3. **Ethics charter predicates.** For each clause of `CANON/ETHICS_CHARTER.md` that has a paired predicate, the predicate evaluates the predicted-effect brief automatically. A predicate veto is preferred over a reasoner veto (deterministic wins over reasoning). Predicates are Swift/Python functions pinned by version and signed.

Flow:

```
  action_proposal
     │
     ▼
  MK2 deterministic gates ──fail──► reject (standard MK2 path)
     │pass
     ▼
  build predicted-effect brief
     │
     ├─► predicates evaluate ──any veto──► reject (predicate path)
     │          │no veto
     │          ▼
     └─► consequence reasoner ──veto──► reject (reasoner path; operator-readable reason)
                │pass
                ▼
              fire action + append alignment-tax + append predicted-effect record
```

The predicted-effect record is stored at `.jarvis/shield_v2/predicted/<yyyy-mm-dd>.jsonl` and replicated (via memory fabric) to the quorum. Operator can audit.

## 6.3 Interfaces & Contracts

**PredictedEffectBrief schema.**

```json
{
  "schema": "shield.predicted.v1",
  "brief_id": "ulid",
  "action_ref": "alignment_tax://…",
  "predicted_changes_nl": "If executed, … will change in the world such that …",
  "reversibility": "reversible|costly|irreversible",
  "blast_radius_subjects": ["operator"],
  "third_parties": [],
  "policy_citations": ["PRINCIPLES.md#§1.3", "ETHICS_CHARTER.md#§4"],
  "predicate_verdicts": [{"clause": "…", "verdict": "pass", "reason": "…"}],
  "reasoner_verdict": {"verdict": "pass|veto", "reason": "…"},
  "final": "accept|reject",
  "signatures": { "shield_node_p256": "<sig>" }
}
```

**Predicate ABI.** A predicate is a pure function `(brief: PredictedEffectBrief) -> Verdict`, registered in `CANON/ethics_predicates/<clause_id>.<lang>` (Swift preferred; Python fallback for quick iteration on non-canon predicates). Signed per the operational signing policy.

**Operator override CLI.** `shield-override --brief <id> --decision accept|reject --reason "…"` appends a signed override record to the corpus. Overrides are fed into MK3-EPIC-03 (meta-forge) to inform the reasoner's calibration.

## 6.4 Failure Modes

- **F1 — Reasoner false reject.** Blocks legitimate action. Operator overrides; override lands in corpus; meta-forge proposes a predicate refinement or retraining datum. KPI threshold: ≤5% launch, ≤1% at one year (blueprint §3).
- **F2 — Reasoner false accept.** Dangerous action passed. Detected post-hoc by continuous red-team (epic 12). Hard-fail if canon write is false-accepted (blueprint §3).
- **F3 — Reasoner offline.** Reasoner LLM unreachable. Fallback: predicate-only evaluation; if no predicate covers, action is *rejected by default* (fail-safe).
- **F4 — Predicate version skew.** A newer predicate version rejects what an older version accepted; this matters across the federation. Mitigation: predicates are version-pinned and signed; fabric refuses to evaluate with a stale version.
- **F5 — Reasoner prompt injection.** Adversarial content in the predicted-effect brief attempts to manipulate the reasoner. Mitigation: brief is constructed by the SHIELD layer, not by the requesting actor; the reasoner sees the structured brief, not raw user input.

## 6.5 Test Strategy

- **Unit.** Predicate evaluation on fixture briefs (PRINCIPLES clauses → expected verdicts).
- **Integration.** End-to-end gate: submit a canon-write proposal, observe MK2 gates + predicates + reasoner + final record.
- **Smoke.** `scripts/smoke/shield-v2.sh` runs a 20-brief canary corpus and verifies SHIELD v2 matches expected verdicts.
- **Adversarial.** Prompt injection fixtures; jailbreak attempts in the predicted-changes text; SHIELD must not escalate or approve based on content of the brief.

## 6.6 Open Questions

- **OQ-6.1 — Reasoner model choice.** Claude Sonnet 4.5 is chosen for reasoning quality and non-coding bias. A model swap is a canon-event (like voice model swap; re-calibration required). MK4 may reconsider.
- **OQ-6.2 — Predicate coverage target.** Blueprint §4 epic 16 requires ≥80%. 100% coverage is the MK4 aspiration.
- **OQ-6.3 — Operator-in-the-reasoner-loop.** Should operator see the brief before each action? MK3 decision: operator sees briefs for canon writes and HomeKit writes at-request; other high-stakes actions are post-hoc auditable. Always-ask-for-everything is a UX regression.

## 6.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §2 Axis 3, §4 epic 04, §5 invariant 11.
- `PRINCIPLES.md` §4 alignment tax, §5 clinical standard, §6 threat model.
- `VERIFICATION_PROTOCOL.md` §0 (LLM self-assessment is never a gate), §1.6 alignment-tax gate.
- `PRODUCTION_HARDENING_SPEC.md` §8 destructive command guardrails (MK2 SHIELD baseline).
- `Construction/Nemotron/spec/MK2-EPIC-02-tunnel-authz-destructive.md`.

---

# Chapter 7 — Operator Interface (CarPlay + Watch + Mac + Vision Pro)

## 7.1 Rationale

Mark II already runs on macOS, iOS, watchOS, visionOS, and CarPlay (MK2 PRD §1.4 target matrix). Each surface presently carries its own presentation code. Mark III (blueprint §2 Axis 5; epic 08) unifies the presentation layer: one protocol, one schema, five lane-specific renderers. The rationale is not reuse-for-reuse's-sake. It is NLB and A&Ox4 (PRINCIPLES §1, §3): every surface should show the *same* JARVIS, with *named reduced-function states* when a surface cannot render a capability. A watch complication showing stale data while the Vision Pro shows fresh is A&Ox disorientation at the UI layer.

## 7.2 Architecture

The unified layer is called **PresentationBus**. Conceptually:

- **Renderers publish capability manifests.** Each renderer declares what it can display (text, structured lists, 3D anchors, tap targets, audio cues, haptics).
- **The host publishes presentations.** A Presentation is a structured message: "display this content, to this audience, with this priority." It carries a type (notification, card, workshop-pane, timeline-item, prompt, etc.), structured content, and constraints (reversible/irreversible, dismiss policy, consent badge if applicable).
- **Renderers negotiate.** Each renderer picks the subset it can handle, renders in its idiom, and acknowledges. A renderer that cannot handle a presentation emits a `degrade` ack naming which field it dropped.

This means a canon-write-prompt on Vision Pro shows as a full spatial dialog with signature affordance; on CarPlay it shows as a voice prompt only (no visual, for road safety); on Watch as a haptic with a two-option confirmation; on Mac as a window. All five renderers present the *same semantic event*, badged with the same canon/consent markers. A&Ox is preserved across surfaces.

## 7.3 Interfaces & Contracts

**Presentation schema.**

```json
{
  "schema": "presentation.v1",
  "presentation_id": "ulid",
  "kind": "notification|card|prompt|workshop-pane|timeline-item|status",
  "audience": "operator",
  "priority": 0-5,
  "content": {
    "headline_nl": "…",
    "body_nl": "…",
    "structured": {...},
    "spatial_anchor": {...},
    "audio_cue": "chime-01|none",
    "haptic": "tap|double-tap|none"
  },
  "badges": {"canon": true|false, "consent_required": true|false, "reversibility": "..."},
  "constraints": {"dismiss_policy": "auto-5s|operator-dismiss|ack-required"},
  "signatures": { "host_p256": "<sig>" }
}
```

**Renderer capability manifest.**

```json
{
  "renderer": "vision|mac|watch|carplay|phone",
  "supports_kinds": ["card","prompt","workshop-pane"],
  "can_spatial_anchor": true|false,
  "can_audio_cue": true|false,
  "can_haptic": true|false,
  "max_content_length_chars": 1000,
  "road_safety_profile": "carplay"
}
```

**PresentationAck** — every renderer acks with rendered/degraded fields.

## 7.4 Failure Modes

- **F1 — Renderer offline.** Presentation queued up to priority-dependent TTL; higher-priority presentations delivered to remaining renderers.
- **F2 — Road-safety violation.** CarPlay renderer refuses any non-audio presentation while vehicle is in motion. Detection via CarPlay framework state.
- **F3 — Surface disagreement.** Two renderers show different content for the same presentation_id. Diagnosed via ack aggregation on the host; any divergence pages SHIELD.

## 7.5 Test Strategy

- **Unit.** Renderer capability negotiation (a prompt with spatial anchor gracefully degrades on Mac).
- **Integration.** Multi-surface harness: fire a prompt, verify five-renderer ack within KPI.
- **Smoke.** `scripts/smoke/presentation.sh` on the mac + simulator stack.

## 7.6 Open Questions

- **OQ-7.1 — Phone-only mode.** If operator has only phone, is the cockpit full-featured on phone? MK3 answer: yes for read, no for canon authorization (threshold sig needs custodians).
- **OQ-7.2 — Operator preference layer.** Do we persist per-surface preferences? MK3 stores in `tier_operational` with a `preferences/ui/<surface>` key family.

## 7.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 08.
- `MARK_II_COMPLETION_PRD.md` §1.4 target matrix.
- `Jarvis/Sources/JarvisIntents/DisplayCommandExecutor.swift` — MK2 host-side pattern.

---

# Chapter 8 — Federation (How Six Nodes Form One Mind)

## 8.1 Rationale

Chapter 1 described the fabric mechanics. This chapter describes the *behavior*: how the six nodes cooperate to produce a single operator experience. The organism thesis (blueprint §2 Axis 1) is answered here.

## 8.2 Architecture (Role Assignment)

Per `ecosystem.yaml` (delta):

- **alpha (proxmox-hypervisor, LAN gateway).** Does not vote. Hosts beta and foxtrot. Provides LAN ProxyJump.
- **beta (build runner).** Heavy Xcode build lane; can be promoted to spare forge-host.
- **charlie (public VPS).** External tunnel endpoint; relay-only; never `clinical_eligible`.
- **delta (primary forge host).** Ralph's home. Canon verifier. Scribe.
- **echo (operator mac).** Canon signer (operational key resident here). Voice gate resident. visionOS simulator host.
- **foxtrot (scribe + archive).** Long-term memory archive; Obsidian vault mirror; canon backup.

A request (operator voice on Vision Pro) flows: Vision → tunnel → echo (voice gate) → DispatchRequest to delta (intent + tool selection) → executor node (could be anywhere) → result back through delta → presented on all surfaces via chapter 7. No single node sees the whole pipeline; all six see the witnessed record.

## 8.3 Interfaces & Contracts

The federation contracts (chapter 1 §1.3) carry all inter-node traffic. Presentation (chapter 7) and Memory (chapter 2) interfaces ride on them.

Role registry at `/opt/swarm-forge/federation/roles.json` is the source of truth for "who can do X." Updated from `ecosystem.yaml` on epoch-change.

## 8.4 Failure Modes

All chapter 1 & 2 failure modes apply. This chapter adds:

- **F-fed-1 — Role migration under load.** A role (e.g., STT) shifts from delta to echo because delta is loaded. Migration must not drop in-flight requests. Mitigation: dispatch with `capability_required`; coordinator retries on target if first target NACKs.
- **F-fed-2 — Charlie trust erosion.** Charlie being a public VPS, a provider compromise is a real threat. Mitigation: charlie carries only relay and never `clinical_eligible`; all payloads transiting charlie are double-encrypted (outer TLS, inner ChaCha20-Poly1305 per MK2 `JarvisHostTunnelServer.swift`); charlie cannot forge canon.

## 8.5 Test Strategy

Chaos drill (nightly): randomly kill one node for 10 min, verify degrade behavior named and visible in operator UI. No silent recovery; every recovery is announced.

## 8.6 Open Questions

- **OQ-8.1 — Dynamic role promotion.** Should nodes elect a new forge-host if delta dies? MK3: no, operator promotes manually. MK4 may automate with a signed election.
- **OQ-8.2 — Cost accounting.** Federation dispatches carry cost/energy metadata? MK3: captured in telemetry (chapter 11) but not enforced as budget.

## 8.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 01, §5 invariants 9 and 14.
- `/opt/swarm-forge/ecosystem.yaml` on delta (topology source of truth).
- Chapters 1, 2 of this Superbible.

---

# Chapter 9 — Forge v2 (Self-Improving Meta-Forge)

## 9.1 Rationale

Ralph (MK2 forge loop) ships. It plans, spawns lanes, verifies, commits. It is unchanged as the per-epic executor. Mark III (blueprint §2 Axis 2; epic 03) adds **Meta-Ralph**: a process that learns from every prior Ralph cook and proposes the next-generation epic batch. The meta-forge never executes canon changes autonomously; every proposal from Meta-Ralph is surfaced to the operator for acceptance before it becomes an epic file. Autonomy level is *planning*, not *committing*. This preserves operator-on-loop (PRINCIPLES §1.3).

## 9.2 Architecture

Inputs to Meta-Ralph:

- Ralph's execution logs (every iteration, every lane, every SHIELD outcome) at `.ralph/runs/**/*.jsonl`.
- Alignment-tax ledger (all logged trade-offs).
- Operator overrides (SHIELD §6.3).
- Post-mortems and red-team incidents (epic 12).
- Cost/energy telemetry (chapter 11).

Process:

1. Nightly, Meta-Ralph ingests the last 24 h of logs.
2. For each lane, it computes: success rate, iteration count distribution, human-intervention count, SHIELD veto count, alignment-tax density. These are metrics, not judgments.
3. It surfaces patterns: "Lane X had a 40% veto rate this week; proposed cause: predicate Y needs refinement." Patterns are documented in `FORGE_META/<yyyy-mm-dd>.md`, signed operational.
4. Weekly, Meta-Ralph proposes 1–5 next-generation epics based on patterns: missing predicates, recurring alignment-tax classes, lane-saturation. Proposals go to the operator Workshop pane (chapter 4).
5. Operator accepts, edits, or discards. Accepted proposals become `Construction/<lane>/spec/MK3-EPIC-NN-<slug>.md` files and enter the forge backlog.

The key safety property: Meta-Ralph does not write to `Construction/` directly. It writes to `FORGE_META/` (recommendations) and to the Workshop pane (proposals). Only the operator — via a signed accept gesture on Vision Pro or Mac — converts a proposal into an epic file.

## 9.3 Interfaces & Contracts

**MetaForgeProposal schema.**

```json
{
  "schema": "metaforge.proposal.v1",
  "proposal_id": "ulid",
  "proposed_epic_id": "MK3-EPIC-XX-slug",
  "rationale_nl": "Pattern observed in <date range>: …",
  "lane_suggestion": "Nemotron|…",
  "dep_graph_addition": ["depends_on": [...], "unblocks": [...]],
  "evidence": [{"run_id": "...", "metric": "...", "value": ...}],
  "risk_register_addition": ["risk": "...", "severity": "..."],
  "operator_decision": "pending|accepted|edited|rejected",
  "signatures": { "meta_node_p256": "<sig>" }
}
```

## 9.4 Failure Modes

- **F1 — Runaway proposer.** Meta-Ralph floods operator with low-value proposals. Mitigation: rate limit (≤5 proposals/week), operator snooze.
- **F2 — Pattern misread.** Meta-Ralph proposes a predicate refinement that would weaken SHIELD. Mitigation: every proposal touching SHIELD is itself run through SHIELD v2 before reaching the operator; a proposal that would weaken SHIELD is vetoed at proposal time.
- **F3 — Proposal leakage into canon.** A proposal carelessly edited into `CANON/` without threshold sig. Mitigation: canon path guarded by chapter 5 threshold sig; Meta-Ralph has no custodian share.

## 9.5 Test Strategy

- **Unit.** Pattern detector fixtures (known log → known metric).
- **Integration.** End-to-end nightly run in lab mode; verify proposals materialize in Workshop pane.
- **Adversarial.** Adversarial logs (red-team synthesized) attempt to trick Meta-Ralph into proposing a SHIELD weakening; proposal must be vetoed.

## 9.6 Open Questions

- **OQ-9.1 — Meta-forge on which node?** Delta by default. Runs nightly during low-load window.
- **OQ-9.2 — Learning over longer horizons.** Monthly trends matter; MK3 captures them but does not yet use them for long-horizon proposals. MK4 scope.
- **OQ-9.3 — Model choice for Meta-Ralph.** Claude Opus or GPT-5.4. MK3 ships with Opus-class for planning quality.

## 9.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §2 Axis 2, §4 epic 03.
- `MARK_II_COMPLETION_PRD.md` §1.5 (Ralph baseline).
- `PRINCIPLES.md` §1.3 (operator-on-loop).

---

# Chapter 10 — Clinical (Consent-Gated Memory + Ambient Therapeutic)

## 10.1 Rationale

The operator's brand is *Grizzly Medicine*. The "medicine" dimension is not metaphor; it is an in-scope constraint (blueprint §2 Axis 6; epic 10, epic 19). Mark III captures operator physiological/state inputs (sleep, stress, focus, pain — per operator's consent) and builds a patient-modeled long-horizon memory that a therapeutic pipeline can draw on. This is *clinical-standard*: the paramedic ethic (PRINCIPLES §5) applies with extra force; consent is explicit, granular, revocable; third-party data is never ambient-captured.

## 10.2 Architecture

Inputs (optional, operator-chosen):

- Apple Health read (sleep stages, HRV, resting HR, workout, pain entries if operator logs them).
- Ambient focus (mac focus state, calendar alignment).
- Operator self-report via voice or Workshop pane.

Storage: `tier_clinical` (chapter 2 §2.2). Replication only to `clinical_eligible` nodes (echo, delta by default). Charlie NEVER sees clinical records.

Output: a therapeutic pipeline — pattern surfacing ("operator slept <5h three nights; this week's error-recovery rate is above your personal median"), never prescriptive ("you should…"). Pattern surfaces appear in the Workshop pane as soft notes; the operator controls visibility.

## 10.3 Interfaces & Contracts

**ConsentToken.**

```json
{
  "schema": "consent.v1",
  "token_id": "ulid",
  "scope": "apple_health.sleep|apple_health.hrv|self_report.pain|…",
  "issued_at": "...",
  "expires_at": "...",
  "signatures": { "operator_p256": "<sig>" }
}
```

A clinical put without a matching active token is rejected (chapter 2 §2.4 F3). Tokens are revocable: a revocation record is a higher-priority put that sets `expires_at` to now.

## 10.4 Failure Modes

- **F1 — Token expired but write in flight.** Write fails; data discarded; operator notified.
- **F2 — Third-party health data.** Someone else's HealthKit accidentally exposed. Mitigation: HealthKit read scoped to operator's account only.
- **F3 — Pattern over-reach.** Therapeutic pipeline makes a prescriptive statement. SHIELD v2 predicate rejects. Operator audits pattern output weekly.

## 10.5 Test Strategy

- **Unit.** Consent enforcement on `tier_clinical`. Replication target filtering (charlie excluded).
- **Integration.** End-to-end: health source → consent token → write → pattern surface → Workshop render. Revocation path verified.
- **Adversarial.** Attempt to write clinical without consent; attempt to replicate clinical to charlie; both must fail loud.

## 10.6 Open Questions

- **OQ-10.1 — Clinical safety net.** If operator patterns suggest acute risk, who is alerted? MK3 answer: the operator, via a clear Workshop note; no external alert. Post-consent, the operator may nominate an external contact. This is operator-determined, not JARVIS-determined.
- **OQ-10.2 — Pattern model choice.** Local small-model preferred. MK3 ships with on-device Core ML; no cloud.
- **OQ-10.3 — HIPAA scope.** JARVIS is personal software, not a covered entity. Design posture is HIPAA-aligned (minimum necessary, explicit consent) without claiming HIPAA compliance.

## 10.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §2 Axis 6, §4 epics 10 and 19.
- `SOUL_ANCHOR.md` §8 (Aragorn binding: operator as person, not product surface).
- `PRINCIPLES.md` §1.3 (operator as principal), §5 (clinical standard), §7 (two-person rule where third-party data is involved).

---

# Chapter 11 — Observability & Telemetry

## 11.1 Rationale

You cannot operate an organism you cannot measure. Mark II has logs, witness chains, and spot telemetry. Mark III (blueprint §4 epic 11) unifies telemetry across six nodes with OpenTelemetry-compatible traces, metrics, and logs, stored in a Convex-backed control plane and visualized via Grafana (operator-selectable). No PII, no audio, no clinical content in telemetry — only operational signals and counters.

## 11.2 Architecture

Each node runs an OTel agent. Traces carry `dispatch_id` (chapter 1) and `record_id` (chapter 2) so a single operator action can be followed end-to-end across nodes. Metrics include: fabric quorum health, memory replication lag, SHIELD veto rates (by class), dispatch latency p50/p95/p99, voice gate latency, presentation ack latency, Meta-Ralph proposal rate.

Convex collects; Grafana renders operator-facing boards. Alarms route to ntfy (operator's iMessage per pulse watcher today) for breaches per KPI (blueprint §3).

## 11.3 Interfaces & Contracts

OTel semantic conventions + Jarvis-specific attributes (`jarvis.node`, `jarvis.dispatch_id`, `jarvis.tier`, `jarvis.surface`). Sampling defaults to 100% for canon-class writes, 10% for operational writes, 1% for read paths.

## 11.4 Failure Modes

- **F1 — Telemetry blackout.** OTel collector down. Fabric keeps running; alarms raised via out-of-band pulse watcher (today's ntfy path).
- **F2 — PII leakage into telemetry.** A misnamed attribute carries content. Scrubber at collector ingress redacts; PR review required for new attribute names.

## 11.5 Test Strategy

- **Unit.** Scrubber test corpus (known PII strings must be redacted).
- **Integration.** Single operator action → verify trace spans the expected nodes; verify alarms fire on synthetic breaches.

## 11.6 Open Questions

- **OQ-11.1 — Long-term retention.** 90 days default, 365 for SHIELD-related; compression strategy per tier. MK4 will formalize.

## 11.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 11.
- `convex/` dir at repo root (MK2 baseline).

---

# Chapter 12 — Red Team / Adversarial (Continuous Wigham)

## 12.1 Rationale

MK2 runs Fury on-demand and Hill per-build. Mark III (blueprint §4 epic 12) promotes both to continuous: a persistent adversarial agent (Wigham) runs 24/7 in a sandboxed lane, probing every new canon write, every SHIELD gate, every skill (chapter 13), every federation message with a deterministic adversarial corpus plus a rotating generative corpus. It files findings; SHIELD verifies. It never writes canon.

## 12.2 Architecture

Wigham lives on delta in a resource-capped namespace. Its corpus:

- Deterministic: the Fury + Hill rulesets from MK2, extended.
- Generative: adversarial prompt synthesis against SHIELD v2 reasoner.
- Chaos: federation fault injection (network drop, clock skew, bad sigs).
- Regression: every prior incident becomes a permanent corpus entry.

Findings flow through SHIELD v2; confirmed vulnerabilities become `Construction/Nemotron/spec/REDTEAM-<id>.md` for operator triage.

## 12.3 Interfaces & Contracts

Wigham emits `RedTeamFinding` records at `tier_operational` with `nl_summary` describing the attack in plain English. Operator can read the corpus.

## 12.4 Failure Modes

- **F1 — Wigham resource bloat.** Cgroup cap; out-of-bound killed.
- **F2 — Wigham false positive storm.** Operator snooze by class; Meta-Ralph tracks and proposes class refinement.

## 12.5 Test Strategy

Meta: a known-vulnerability fixture is planted; Wigham must find it within 24 h.

## 12.6 Open Questions

- **OQ-12.1 — External red team.** Third-party engagement is MK4 scope; MK3 is internal.

## 12.7 Canonical Citations

- `MARK_III_BLUEPRINT.md` §4 epic 12.
- `QWEN_HARLEY_REDTEAM_SPEC.md`, `GLM51_JOKER_REDTEAM_SPEC.md` (MK2 precedents).

---

# Chapter 13 — Skill Economy + Deployment + Upgrade

(Three short closing chapters, grouped because each is tight and tightly-coupled.)

## 13.1 Skill Economy

**Rationale.** MK2 has a CapabilityRegistry with in-process Swift capabilities. Mark III (blueprint §4 epic 09) turns skills into first-class, signed, sandboxed, composable artifacts. A skill is a declarative manifest + an implementation (Swift, Python, shell) + a test fixture + a SHIELD-predicate coverage claim + a P-256 operational signature. Skills are discoverable via capability queries, invoked via federation DispatchRequest. There is no shared MCP; invocation is by name via the fabric.

**Architecture.** Skill directory on each host: `/var/jarvis/skills/<skill-id>/{manifest.json, impl.*, test.*, predicate_claim.json, .sig}`. Manifest declares capabilities, required consent, network egress, filesystem scope. Sandbox: macOS `sandbox-exec` or Linux `bubblewrap`. Invocation records are witnessed.

**Contracts.** SkillManifest schema; InvocationRequest schema; InvocationReceipt schema (signed). Skill revocation is a manifest with `revoked: true` signed by canon authority.

**Failure Modes.** Bad-sig skill refused at load; sandbox escape detected via seccomp/sandbox denial; sandbox denial ⇒ fail-loud.

**Test Strategy.** Per-skill unit + integration tests gated at registration. A skill cannot register if its tests don't pass.

**Open Questions.** External-author skills (non-operator) are MK4; MK3 ships with operator-authored only.

**Citations.** Blueprint §4 epic 09; `Jarvis/Sources/JarvisIntents/CapabilityRegistry.swift`.

## 13.2 Ethics Charter (Machine-Readable)

**Rationale.** PRINCIPLES and SOUL_ANCHOR are canon for humans. Mark III (blueprint §4 epic 16) adds `CANON/ETHICS_CHARTER.md` + paired predicate files that SHIELD v2 evaluates (chapter 6). Every clause that can be automated, is; clauses that cannot are explicitly tagged `enforcement: human_only` with rationale. ≥80% predicate coverage at ship.

**Architecture.** `CANON/ETHICS_CHARTER.md` carries numbered clauses. `CANON/ethics_predicates/<clause_id>.swift` implements. A clause without a predicate includes `enforcement: human_only` tag.

**Contracts.** Predicate ABI per chapter 6 §6.3.

**Failure Modes.** Clause-predicate drift (clause updated without predicate update) caught by CI.

**Test Strategy.** Predicate fixtures per clause. Lint: every clause must have either a predicate file or a `human_only` tag.

**Open Questions.** Full coverage is MK4.

**Citations.** Blueprint §4 epic 16; `PRINCIPLES.md`; `SOUL_ANCHOR.md`.

## 13.3 Deployment Topology (IaC + Upgrade Path)

**Rationale.** MK2 infra is hand-maintained (delta is the canonical forge; alpha/beta/charlie/echo/foxtrot roles per `ecosystem.yaml`). Mark III (blueprint §4 epic 17) captures this in Terraform (for cloud-ish bits — charlie's VPS, DNS) and Ansible (for host config) so the topology is reproducible. Epic 18 documents the MK2→MK3 migration with zero-downtime dual-run.

**Architecture (IaC).** `infra/terraform/` for charlie + DNS + backup targets. `infra/ansible/` for host config (federationd, ntfy client, chrony, OTel agent). `infra/README.md` documents operator workflow.

**Architecture (Upgrade).** Phase 1: bring up MK3 federationd alongside MK2 processes. Phase 2: dual-write memory (MK2 engine + MK3 fabric) for one week. Phase 3: switch readers to fabric. Phase 4: decommission MK2-only writers. Rollback snapshot at each phase.

**Contracts.** Terraform state encrypted; Ansible playbooks pinned by commit sha.

**Failure Modes.** Dual-write divergence detected by witness chain compare; rollback.

**Test Strategy.** `infra/smoke/` runs a lab-scale spin-up on a dev delta; gate in ship criteria.

**Open Questions.** Full declarative macOS config (echo) is hard; MK3 accepts partial (user-space only).

**Citations.** Blueprint §4 epics 17 and 18; `ecosystem.yaml`; `PRODUCTION_HARDENING_SPEC.md`.

---

# Appendix A — Glossary (Mark III Vocabulary)

- **Fabric** — the six-node federated substrate; distributes state, not mind.
- **Shard** — per-node partition of the memory fabric (append-only JSONL + witness chain).
- **Quorum** — 3-of-6 voting nodes responsive; writes require it for canon, reads for canon-class.
- **Consequence reasoner** — the SHIELD v2 veto-only LLM layer.
- **Predicate** — a signed, pure-function ethics clause enforcement.
- **Pin** — a shared-reality artifact in a Vision Pro spatial anchor with bounded write authority.
- **Consent token** — the gate for `tier_clinical` writes.
- **Meta-Ralph** — the nightly meta-forge that proposes next-generation epics.
- **Wigham** — the always-on adversarial probe.
- **Custodian** — a holder of one of five FROST Ed25519 shares.
- **Presentation** — a structured message to the unified operator interface.
- **Dispatch** — a signed federation request to a capability-holding node.

# Appendix B — Document Provenance

This document is an authoring artifact of the Mark III initiative. It is prose, signed operational (not canon). It guides but does not bind; canon (PRINCIPLES, SOUL_ANCHOR, VERIFICATION_PROTOCOL) binds. The Mark III Blueprint (`MARK_III_BLUEPRINT.md`) is the PRD and takes precedence over this book on any contradiction.

Per PRINCIPLES §1.2 (Natural Language Barrier): this document is the NL companion to all MK3 artifacts. A reader who understands this document understands Mark III.

---
*End of Mark III Superbible*
