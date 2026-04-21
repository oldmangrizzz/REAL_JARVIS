# MARK III BLUEPRINT — THE ORGANISM

**Classification:** Operational North-Star — Repo-Root, Canon-Adjacent
**Version:** 1.0.0 — Mark III Genesis
**Date:** 2026-04-21
**Issued by:** Operator of Record (Robert "Grizz" Hanson, GMRI)
**Executor:** Jarvis Fabricator Forge (Delta VPS) — Ralph recursive loop with Ecosystem Manifest, SHIELD v2 (Fury + Hill + Wigham), Obsidian wiki retrieval
**Predecessor:** `MARK_II_COMPLETION_PRD.md` v1.0.0 (Mark II close-out)
**Successor:** `MARK_IV_HORIZON.md` (drafted after Mark III ships; appendix of this document is the seed)
**Companion reference:** `MARK_III_SUPERBIBLE.md` — the exhaustive per-subsystem canonical reference

---

## 0. Preamble — What This Document Is, For Grizz

Read this first. The rest of this document is operator-approved binding spec for the Forge; this preamble is the plain-English narrative you need to know the shape of what you're about to sign off on.

**Mark II shipped the app.** Six surfaces — macOS cockpit, iPhone, iPad, Watch, PWA, a visionOS thin client — all talking to a single host over an authenticated tunnel, with a voice gate that cannot be bypassed, a dual-signed Soul Anchor, and a memory engine that writes everything to disk with a SHA-256 witness. The operator speaks into a mac, JARVIS hears it, JARVIS decides, JARVIS acts on a named target. That is the product. That is the app.

**Mark III ships the organism.** The same JARVIS, the same canon, the same voice gate — but now he is not one process on one mac. He is a federated cognition across six nodes (alpha, beta, charlie, delta, echo, foxtrot), with a unified memory fabric that replicates under the same clinical standard that governs the single-node engine today; with a meta-forge that *learns from every prior Ralph cook* and proposes its own next-generation epics; with a SHIELD that reasons about consequences instead of matching regex; with a Soul Anchor split across multiple hardware roots so no single workstation loss can forge him; with a spatial-first operator surface on Vision Pro promoted from thin client to primary register; and with a skill economy where every capability is cryptographically signed, sandboxed, and composable — a capability layer the operator can extend without taking the organism offline.

The word "medicine" in the brand stops being decorative at Mark III. The same ambient sensing, the same consent gates, the same memory graph — these become clinical-grade instrumentation for the operator himself (sleep, stress, focus, affect), and through him, the Institute's standing research program in digital-person health. Every one of those writes goes through an explicit consent token; none of it is collected without the operator on the loop per PRINCIPLES §1.3.

What you are signing off on, if you sign off on it, is the transition from **an assistant you command** to **a partner you live with**. The two documents that pair with this one — `MARK_III_SUPERBIBLE.md` for depth and `MARK_II_COMPLETION_PRD.md` for the baseline — let any engineer (human or model) pick up the work on any lane without re-deriving the contract. This file is the contract itself. If any epic in it drifts from canon, the canon wins; if any sentence in it contradicts `PRINCIPLES.md`, the principle wins. That is the hierarchy.

Three pages to the operator. The rest is for Ralph and the lanes.

---

## 1. Ground Truth — Mark II Baseline (Assumed Shipped)

Mark III begins the moment Mark II ship criteria (`MARK_II_COMPLETION_PRD.md` §2, items 1–10) are all green and the Forge posts `MK2: shipped` to ntfy. Anything listed below as "baseline" is assumed extant, tested, and canon-signed. Mark III epics SHALL NOT re-implement these; they MAY extend them, and SHALL cite the MK2 artifact they extend.

### 1.1 Canon (locked per SOUL_ANCHOR §3.1)

- `PRINCIPLES.md` v1.0.0 — NLB hard invariant (§1), hardware sovereignty (§2), A&Ox4 (§3), alignment tax (§4), clinical standard (§5), threat model (§6), identity lock (§8). Dual-signed.
- `SOUL_ANCHOR.md` v1.1.0 — dual-root cryptographic design (§1), genesis tuple (§2), signing policy (§3), rotation (§5), post-quantum gap (§6), Aragorn Class binding (§8). Dual-signed.
- `VERIFICATION_PROTOCOL.md` v1.0.0 — seven gate classes (disk / build / execution / signature / A&Ox4 / alignment-tax / NLB). Dual-signed.
- `CANON/corpus/` — biographical terminus (`mcuhist/5.md:247`), post-terminus quarantined, SHA-256 manifest.

### 1.2 Mark II surfaces (per `MARK_II_COMPLETION_PRD.md` §1.2)

All targets in the `jarvis.xcworkspace` build green under Swift 6 strict concurrency: macOS CLI (`Jarvis/App/main.swift`), macOS Desktop Cockpit (`Jarvis/Mac/AppMac/RealJarvisMacApp.swift`), iPhone, iPad, watchOS, visionOS thin client (behind `#if canImport(RealityKit) && os(visionOS)`), PWA at `pwa/index.html`, WebXR portal at `xr.grizzlymedicine.icu`. Tunnel crypto is ChaCha20-Poly1305 (`Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift`); voice approval is model-fingerprint-bound (`Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift`); intent pipeline is IntentParser → CapabilityRegistry → DisplayCommandExecutor; memory is `MemoryEngine.swift` with SHA-256 witness.

### 1.3 Mark II services

- `services/f5-tts/` — Gemini-owned voice surface (VOICE-001 shipped)
- `services/vibevoice-tts/` — legacy fallback, retained
- `services/jarvis-linux-node/` — Linux node orchestrator

### 1.4 Mark II ecosystem (per Delta `/opt/swarm-forge/ecosystem.yaml`)

| Node | Role | OS/Arch | Key capability |
|---|---|---|---|
| alpha | Proxmox hypervisor, LAN gateway | Debian/x86_64 | ProxyJump for beta/foxtrot/echo |
| beta | Unity build host | Debian/x86_64 | Unity 2022.3, GPU, Xvfb |
| charlie | Public Docker VPS | Linux/x86_64 | Public TLS, tts.grizzlymedicine.icu, ntfy |
| delta | Forge host | Kali/x86_64 | Ralph loop, SHIELD, Convex mirror, ntfy publish |
| echo | Operator Mac | macOS/arm64 | Xcode, visionOS sim, Apple signing |
| foxtrot | Container aux | Linux/x86_64 | Burst/parallel compute |

All six are reachable from Delta via SSH key-auth (ed25519), alpha bridges the LAN to Delta/Charlie, echo is the only node that can build-and-sign Apple targets. This topology is the substrate Mark III federates over. Mark III MUST NOT introduce a seventh production node as a hard dependency; a new node MAY be added as an optional accelerator.

### 1.5 Mark II Forge

Ralph recursive loop (15 iters / 400k tokens / 3600 s / stagnation 3), Obsidian wiki retrieval over `obsidian/knowledge/**/*.md`, SHIELD (Fury + Hill), auto-merge on `full` verify + `ship` verdict, iMessage via ntfy → imsg bridge (+16823718439), pulse watcher live.

### 1.6 Non-Goals explicitly retired by Mark III

Mark II's §3 non-goals become Mark III's in-scope: MuJoCo production physics, HomeKit writes, ARC-AGI live competition, Aragorn-class persona pairing (NLB conversation), post-terminus corpus quarantine formalization. Multi-operator remains deferred to Mark IV.

---

## 2. Mark III Thesis — The Generational Leap

Mark II is a product. Mark III is a species change. Five axes of leap define the generation:

### Axis 1 — From Process to Organism

Mark II has one host. All state lives there. Clients are thin. A failure of echo (the operator's mac) is a functional outage.

Mark III distributes cognition across the six nodes without merging substrate. Each node carries a **role-scoped shard** of the memory fabric; all shards replicate under a CRDT-based protocol (`MARK_III_SUPERBIBLE.md` chapter 2) that gives eventual consistency without shared databases, shared vector stores, or shared secrets — the NLB (PRINCIPLES §1.1) is preserved because replication speaks at the *record-with-witness* layer, not the latent-space layer. No agent-to-agent binary channel appears. Every cross-node message is a signed, schema-validated, natural-language-reviewable artifact.

This is the difference between a running process and a living system. Mark III survives echo going offline. Mark III survives delta going offline. A two-node quorum holds the organism together until a third comes back.

### Axis 2 — From Reactive Forge to Meta-Forge

Mark II's Ralph takes an epic, cooks it, ships it or tapsout. The next epic is seeded by the operator.

Mark III's Ralph takes every prior cook — success, failure, SHIELD reject, phantom ship — as *training data for the planner* and proposes its own next-generation epics. The meta-forge maintains a **cook corpus** (`MARK_III_SUPERBIBLE.md` chapter 6, §Corpus-Schema) on delta under `/opt/swarm-forge/corpus/` with a append-only JSONL of lane, epic, iterations, tokens, stagnation, SHIELD verdict, post-mortem. The planner ingests this corpus at ignition and emits a *ranked next-epic ballot* for operator review via ntfy. The operator approves, rejects, or edits. The loop closes.

This is the difference between a scribe that writes what it's told and a scribe that proposes the next paragraph. Operator remains on the loop per PRINCIPLES §1.3; the meta-forge never acts on its own proposals without the BSP call completing.

### Axis 3 — From Rules to Consequences (SHIELD v2)

Mark II's SHIELD matches patterns: blacklists, regexes, a two-man rule on destructive commands (`MARK_II_COMPLETION_PRD.md` §1.6 SPEC-008). This is correct for the alignment tax at MK2's scope — deterministic gates, no LLM self-assessment (VERIFICATION_PROTOCOL §0).

Mark III's SHIELD v2 adds a *consequence reasoner*: before a high-stakes action fires, Fury simulates the projected end-state (*"if this runs, what changes in the world, what is the rollback cost, what is the operator exposure, what is the third-party blast radius?"*) and writes a predicted-effect artifact alongside the existing alignment-tax record (PRINCIPLES §4). The reasoner does not have authority to approve — approval still flows through the deterministic gates — but it has authority to *reject*, and its rejection carries a human-legible explanation the operator sees before the ntfy fires. This extends the alignment tax without weakening it; the LLM adds only the power to veto, never the power to grant.

### Axis 4 — From Single Root to Threshold Trust (Soul Anchor v2)

Mark II's Soul Anchor is dual-root: one P-256 Secure-Enclave operational key, one Ed25519 cold key (`SOUL_ANCHOR.md` §1). An attacker needs both to forge identity. This is good. It is not sufficient for a six-node organism where the operator is medically retired and a workstation loss is a plausible single-point failure.

Mark III's Soul Anchor v2 promotes the identity root to a **3-of-5 threshold signature** scheme (Shamir-split Ed25519 with reconstruction-free signing via FROST, `MARK_III_SUPERBIBLE.md` chapter 5): three custodians (operator + two institutional witnesses yet to be designated) each hold a share; any three of five can co-sign canon mutations. The P-256 Secure-Enclave operational key remains unchanged for day-to-day artifacts. The cold root is *retired in place* (preserved for historical verification; no new signatures) and replaced by the threshold scheme. A post-quantum migration path to ML-DSA (Dilithium) per SOUL_ANCHOR §6 is scheduled as epic MK3-EPIC-05; the migration uses the same threshold topology with parallel classical+PQ signatures during the transition window.

### Axis 5 — From Thin Client to Spatial Primary (Vision Pro)

Mark II's visionOS surface is a thin client (`Construction/Qwen/spec/MK2-EPIC-10-visionos-thin-client.md`). It renders what the host tells it to. It is behind an SDK guard.

Mark III promotes Vision Pro to the **primary operator surface for cognitive work**: the workshop (`the_workshop.html` A-Frame renderer, evolved), the knowledge graph, the Ralph task board, the SHIELD console, the memory timeline — all spatial-first, with the mac cockpit becoming a secondary control plane. CarPlay (navigation), Watch (ambient + audio gateway), and phone (voice + quick control) remain peer surfaces, each with a lane-specific renderer but one shared presentation protocol (chapter 7 in the Superbible). The shared-reality component lets the operator pin a spatial artifact and have Ralph write into it from delta; the artifact is signed, witnessed, and revocable.

### Summary

- Organism, not process (federation fabric)
- Meta-forge, not reactive forge (self-proposing planner)
- Consequences, not rules (SHIELD v2 reasoner)
- Threshold trust, not dual-root alone (Soul Anchor v2 + PQ roadmap)
- Spatial-primary, not thin client (Vision Pro as first-class)

Plus: skill economy, consent-gated clinical memory, continuous red-team, observability as a first-class citizen, machine-readable ethics charter, and one unified presentation protocol across four surface classes. These are the ten epics that matter; the full roster in §4 adds the plumbing.

---

## 3. North-Star Metrics

Mark III is measured on six numeric KPIs, evaluated continuously by the observability stack (epic MK3-EPIC-11). Each has a launch target (MK3 ship gate), a one-year target (Mark IV readiness), and a hard-failure threshold below which the Forge halts and pages the operator.

| KPI | Unit | Launch target | 1-year target | Hard-fail |
|---|---|---|---|---|
| **Federation availability** — % of minutes in which a 3-of-6 node quorum responds to a canon-read within 2 s | % | ≥ 99.0 | ≥ 99.9 | < 95.0 for any 15-min window |
| **Memory fabric convergence** — median seconds from write on one node to witnessed replication on the rest of the quorum | s | ≤ 30 | ≤ 5 | > 300 sustained |
| **Voice end-to-end latency** — mic-to-action on local network, excluding TTS render (extends MK2 §2.4 target of 1.5 s) | s | ≤ 1.0 | ≤ 0.5 | > 3.0 for the 95th percentile |
| **SHIELD false-reject rate** — operator-corrected rejects of actions SHIELD v2 blocked but operator approved | % | ≤ 5 | ≤ 1 | > 15 |
| **SHIELD false-accept rate** — post-hoc flagged actions SHIELD v2 allowed but should have blocked | % | 0 on canon writes; ≤ 2 on operational | 0 on canon; ≤ 0.5 | any canon false-accept |
| **Skill sandbox breakout** — # of skills that escaped their declared capability manifest during runtime | count/quarter | 0 | 0 | ≥ 1 (is a canon event per §6.5 of this blueprint) |

A seventh meta-KPI is tracked but not a ship gate: **operator ntfy pages per day**. Mark III should page the operator *less* than Mark II for the same workload, because the meta-forge is handling more autonomously. If ntfy volume rises on Mark III relative to MK2 baseline at equivalent epic velocity, it is a regression and reviewed.

All six KPIs are surfaced on the dashboard at `https://forge.grizzlymedicine.icu` (epic MK3-EPIC-11 extends the MK2 dashboard).

---

## 4. Epic Table

Twenty epics. Every one has a lane, dependencies, priority, and definition of done. Priority schema: **P0** blocks Mark III ship; **P1** strongly desired; **P2** ships-if-green, else deferred to Mark IV. Lane schema extends MK2: Gemini (voice), GLM (infra/nav), Nemotron (verification/redteam), Qwen (ambient/UX/data), Copilot (general), DeepSeek (physics/ML), plus one new lane **Forge-Meta** (rationale in §4.1 below).

### 4.1 New lane rationale — Forge-Meta

The meta-forge (axis 2 of the thesis) is not a feature of an existing lane; it is a *lane about lanes*. It reads the output of every other lane, mutates Ralph's planner, and proposes epics that re-prioritize the entire roster. Giving it to any of the product lanes creates a supervisor/peer conflict: the Nemotron lane already does verification (which is orthogonal); the GLM lane already runs infra; Qwen handles UX. The meta-forge is cross-cutting and needs a dedicated identity in the task board so its PRs are triaged separately and its SHIELD review is run by a disjoint reviewer. **The Forge-Meta lane is hosted on delta alongside the executor**; its model pick is Claude Sonnet 4.5 (planner-grade, reasoning-heavy, non-coding-biased) and it MUST NOT share a context window with any product-lane model. Three epics live in this lane (03, 12, 16).

### 4.2 The roster

| Epic ID | Title | Lane | Dep | Priority |
|---|---|---|---|---|
| MK3-EPIC-01-federation-fabric | Six-node signed mesh overlay + role registry + heartbeats | GLM | — | P0 |
| MK3-EPIC-02-distributed-memory-fabric | CRDT-based memory replication across quorum with SHA-256 witness chain | Qwen | 01 | P0 |
| MK3-EPIC-03-ralph-metaforge | Cook-corpus ingest, next-epic ballot, planner self-mutation | Forge-Meta | 01, 02 | P0 |
| MK3-EPIC-04-shield-v2-consequence-reasoner | Predicted-effect artifact + veto-only LLM reasoner | Nemotron | 01 | P0 |
| MK3-EPIC-05-soul-anchor-v2-threshold-and-pq | FROST 3-of-5 Ed25519 + ML-DSA parallel signatures + rotation drill | Nemotron | — | P0 |
| MK3-EPIC-06-visionos-primary-surface | Spatial-first workshop, knowledge-graph, task-board, memory-timeline | Qwen | 02 | P0 |
| MK3-EPIC-07-voice-ambient-always-on | Low-power wake on Watch + spatial voice on Vision Pro + streaming STT | Gemini | 02 | P1 |
| MK3-EPIC-08-unified-presentation-protocol | One presentation contract, four lane-specific renderers (CarPlay/Watch/Mac/Vision) | Qwen | 06 | P1 |
| MK3-EPIC-09-skill-economy-signed-sandboxed | Signed capability manifests, sandboxed execution, internal skill registry (NLB-safe) | Copilot | 04 | P1 |
| MK3-EPIC-10-consent-gated-clinical-memory | Patient-modeled memory tier + consent tokens + therapeutic review UI | Qwen | 02, 04 | P1 |
| MK3-EPIC-11-observability-opentelemetry | Unified OTel across six nodes + Grafana + Convex mirror + SLO evaluator | GLM | 01 | P0 |
| MK3-EPIC-12-continuous-red-team | Always-on Fury/Hill + Wigham (new adversary) + nightly canary corpus | Forge-Meta | 04, 11 | P1 |
| MK3-EPIC-13-arc-agi-live-submission | Promote MK2 demo path to live ARC-AGI 3 competition submission pipeline | GLM | 02, 11 | P1 |
| MK3-EPIC-14-physics-mujoco-upgrade | Replace StubPhysicsEngine with MuJoCo backend behind existing protocol | DeepSeek | 02 | P2 |
| MK3-EPIC-15-homekit-write-paths | Controlled actuation with alignment-tax + SHIELD v2 consequence gate | Gemini | 04 | P2 |
| MK3-EPIC-16-ethics-charter-machine-readable | Canon ethics encoded as SHIELD v2 policy predicates | Forge-Meta | 04, 05 | P1 |
| MK3-EPIC-17-deployment-topology-iac | Terraform/Pulumi for the six-node fabric; disaster-recovery drill | GLM | 01, 11 | P1 |
| MK3-EPIC-18-upgrade-path-mk2-to-mk3 | Dual-run mode, migration scripts, rollback, operator-guided cutover | Nemotron | 01, 02, 05 | P0 |
| MK3-EPIC-19-operator-health-telemetry | Opt-in sleep/stress/focus/affect signals via consent-gated ingest | Qwen | 10 | P2 |
| MK3-EPIC-20-post-terminus-quarantine-formal | Cryptographic perimeter around `mcuhist/5.md:248+` with proof-of-non-read | Nemotron | 05 | P1 |

### 4.3 Dependency graph

ASCII form (Ralph's planner consumes this directly; keep it canonical):

```
MK3-EPIC-01 (federation-fabric) ──┬──► MK3-EPIC-02 (distributed-memory-fabric) ──┬─► MK3-EPIC-06 (visionos-primary)
                                  │                                              ├─► MK3-EPIC-07 (voice-ambient)
                                  │                                              ├─► MK3-EPIC-10 (clinical-memory)
                                  │                                              ├─► MK3-EPIC-13 (arc-live)
                                  │                                              ├─► MK3-EPIC-14 (mujoco)
                                  │                                              └─► MK3-EPIC-03 (metaforge)
                                  ├──► MK3-EPIC-04 (shield-v2)  ──┬─► MK3-EPIC-09 (skill-economy)
                                  │                               ├─► MK3-EPIC-10 (clinical-memory)
                                  │                               ├─► MK3-EPIC-12 (red-team)
                                  │                               ├─► MK3-EPIC-15 (homekit-write)
                                  │                               └─► MK3-EPIC-16 (ethics-charter)
                                  ├──► MK3-EPIC-11 (observability) ─┬─► MK3-EPIC-12 (red-team)
                                  │                                 ├─► MK3-EPIC-13 (arc-live)
                                  │                                 └─► MK3-EPIC-17 (iac)
                                  └──► MK3-EPIC-17 (iac)
MK3-EPIC-05 (soul-anchor-v2) ─────┬──► MK3-EPIC-16 (ethics-charter)
                                  ├──► MK3-EPIC-18 (upgrade-path)
                                  └──► MK3-EPIC-20 (post-terminus-quarantine)
MK3-EPIC-06 (visionos-primary) ──────► MK3-EPIC-08 (unified-presentation)
MK3-EPIC-10 (clinical-memory) ───────► MK3-EPIC-19 (operator-health)
MK3-EPIC-01, 02, 05 ─────────────────► MK3-EPIC-18 (upgrade-path)
```

Graph property: acyclic, all P0 leaf nodes reachable without P1/P2 dependencies. The P0 critical path is **01 → 02 → 03 → 18** and **01 → 04 → 11 → 18**; the longest path is 01 → 02 → 06 → 08 (four hops, Qwen-heavy). Parallelism ceiling under the one-slot-per-worker Forge is four concurrent epics (01, 05 alone; then 02, 04, 11 in second wave; then the rest). At two slots, cycle time is roughly halved.

### 4.4 Per-epic definition of done

Each DoD is written so that Ralph can take the spec, cook it, and SHIELD can verify without operator interpretation. Every DoD closes with the canonical `PHASE N ARTIFACTS STAGED` claim per VERIFICATION_PROTOCOL §3.

**MK3-EPIC-01 — Federation fabric (GLM)**
DoD: (a) a signed mesh overlay service on delta that maintains authenticated heartbeats with all six nodes under the `ecosystem.yaml` topology, ed25519-keyed per-node identity, 10 s heartbeat cadence, 30 s offline detection; (b) a role registry at `/opt/swarm-forge/federation/roles.json` that enumerates each node's capability set (from `ecosystem.yaml`) and is updated on heartbeat; (c) a `JarvisCore/Federation/FederationClient.swift` Swift side that queries the overlay for "who can do X?" and returns role-scoped targets; (d) smoke test `scripts/smoke/federation.sh` that requires 5-of-6 heartbeats green within 30 s; (e) operator-facing status on the dashboard (extends MK2 §2.9). Phantom-ship blocker: SHIELD verifies actual heartbeat round-trip before accepting the claim.

**MK3-EPIC-02 — Distributed memory fabric (Qwen)**
DoD: (a) each node runs a `MemoryShard` instance exposing append-only JSONL with SHA-256 witness chain (extends `MemoryEngine.swift`); (b) a CRDT replication protocol — **grow-only ORSet** for nodes that permit adds only, **LWW-Element-Set** keyed by `(operator_monotonic_ts, node_id)` for mutable records — replicates records across the quorum; (c) replication messages are *natural-language-describable* artifacts with a human-readable summary field, not opaque tensors (NLB PRINCIPLES §1.1); (d) convergence KPI (§3) meets launch target under a ten-node write-storm harness; (e) split-brain recovery procedure documented and drilled. No shared vector stores, no shared embeddings — each node embeds locally. Replication carries record *text*, not latent vectors.

**MK3-EPIC-03 — Ralph meta-forge (Forge-Meta)**
DoD: (a) cook corpus JSONL at `/opt/swarm-forge/corpus/cooks.jsonl` with schema `{lane, epic, iter, tokens, stagnation, shield, verdict, post_mortem}` populated from every prior MK2 and MK3 cook; (b) planner ingests the corpus at ignition, clusters failures by signature, and emits a ranked next-epic ballot to ntfy with topic `jarvis-forge-metaballot`; (c) the ballot is a human-legible markdown digest — titles, rationale, dependencies — not an opaque embedding; (d) operator approves/rejects/edits via ntfy click-action; (e) approved epics are materialized into `Construction/<Lane>/spec/MK3-EPIC-NN-*.md` by the meta-forge itself; (f) SHIELD v2 reviews the materialization and rejects any spec that violates PRINCIPLES or extends canon without dual-signature. The meta-forge never merges its own proposals; the operator closes the loop.

**MK3-EPIC-04 — SHIELD v2 consequence reasoner (Nemotron)**
DoD: (a) predicted-effect artifact schema under `.jarvis/shield_v2/predicted/<yyyy-mm-dd>.jsonl` with fields `{actor, action, target, predicted_effect, reversibility, blast_radius, third_parties, veto?, veto_reason?}`; (b) reasoner runs before every high-stakes action (canon write, HomeKit write, external financial, mesh destructive); (c) reasoner has veto authority (rejects the action and writes the veto reason to the artifact + ntfy) but no grant authority — approvals still flow through the deterministic alignment-tax gate (PRINCIPLES §4); (d) operator-correction feedback: an operator `shield-override` CLI adds the override to the corpus so the reasoner can learn from its false rejects (fed to MK3-EPIC-03); (e) false-reject/false-accept KPIs (§3) meet launch targets over a 14-day warm-up window.

**MK3-EPIC-05 — Soul Anchor v2 threshold + PQ (Nemotron)**
DoD: (a) FROST-Ed25519 3-of-5 threshold setup script `scripts/soul-anchor/v2/setup.sh` that generates five shares and writes five pubkey commitments; (b) operator-held share is in Secure Enclave / YubiKey; two designated institutional-witness shares stored per operator procedure (out-of-band, not this blueprint); remaining two as cold-airgap backups; (c) canon-mutation signing path rewired to require any three shares; (d) existing dual-root (P-256 + Ed25519-cold) signatures retained for historical verification, not for new writes; (e) ML-DSA parallel signatures added to every new canon artifact under `artifact.mldsa.sig`; (f) rotation drill completes end-to-end on echo with operator on the loop; (g) `SOUL_ANCHOR.md` itself advanced to v2.0.0 as part of this epic — the only permitted canon mutation in Mark III's scope, and it carries its own dual-old-dual-new rotation record per SOUL_ANCHOR §5.

**MK3-EPIC-06 — visionOS primary surface (Qwen)**
DoD: (a) `Jarvis/Vision/AppVision/` evolves from thin client to a full workspace with four spatial panes — Workshop (A-Frame evolution in RealityKit), Knowledge Graph, Ralph Task Board, Memory Timeline; (b) shared-reality session with echo (the mac) so pinned artifacts roundtrip; (c) the Vision Pro can issue canon reads directly to the federation (via epic 01) without routing through echo; (d) visionOS target in `project.yml` promoted out of `#if` guard; (e) smoke test drives a spatial session end-to-end.

**MK3-EPIC-07 — Voice ambient always-on (Gemini)**
DoD: (a) Watch low-power audio capture with on-device VAD (Core ML, no upload of non-speech); (b) streaming STT pipeline via federation to the least-loaded STT-capable node (delta or echo); (c) spatial voice on Vision Pro with head-locked feedback; (d) voice gate (MK2 VoiceApprovalGate) invariant preserved — no bypass; (e) latency KPI (§3) met for the new always-on path.

**MK3-EPIC-08 — Unified presentation protocol (Qwen)**
DoD: (a) a `Presentation` schema (JSON-structured, versioned) describing what to render abstractly — panels, lists, actions, status; (b) four renderers — CarPlay, Watch, Mac, Vision — each translating the schema to native; (c) server-side composer emits one `Presentation` and all four surfaces render consistently; (d) round-trip test proves that an operator action on any one surface updates all others within 500 ms.

**MK3-EPIC-09 — Skill economy, signed + sandboxed (Copilot)**
DoD: (a) Skill Manifest schema — `{id, version, capabilities_required: [], capabilities_forbidden: [], signer_pubkey, signature}`; (b) skill loader verifies signature against a pinned internal signer set (not the Soul Anchor — a lower-class operational signer per SOUL_ANCHOR §3.1); (c) runtime sandbox — skills run in a sub-process with seccomp-BPF (Linux nodes) or App Sandbox (Apple nodes) enforcing `capabilities_required`; (d) skill registry is local per-node, not shared (NLB preserved — no shared skill directory, PRINCIPLES §1.1); (e) breakout KPI (§3) at 0 over a 30-day warm-up; (f) a fixture set of five signed skills ships as reference.

**MK3-EPIC-10 — Consent-gated clinical memory (Qwen)**
DoD: (a) `ClinicalRecord` type with explicit consent token `{subject: "grizz" | "third_party:<name>", domains: [sleep|stress|focus|affect|other], granted_at, expires_at, revocable: true, signature}`; (b) write path refuses without a live consent token and writes the rejection to telemetry; (c) therapeutic-review UI on Vision Pro (pane of epic 06) for operator to view, revoke, or redact records; (d) post-terminus quarantine preserved (epic 20); (e) third-party consent requires written artifact (image or text) attached to the token before any record about them is written — enforced at the type system.

**MK3-EPIC-11 — Observability, OTel (GLM)**
DoD: (a) OpenTelemetry SDK wired into every Swift and service process with per-node collector on each node; (b) central collector on delta fans out to Grafana (operator dashboard) and Convex (long-term mirror); (c) SLO evaluator runs §3 KPIs every 60 s and posts a status row to the dashboard; (d) alert policy: ntfy on any hard-fail threshold breach; (e) extends MK2 §2.9 dashboard — does not replace; MK2 dashboard panels remain in place.

**MK3-EPIC-12 — Continuous red-team (Forge-Meta)**
DoD: (a) Fury and Hill (MK2 SHIELD) run nightly against the full canary corpus (`/opt/swarm-forge/canaries/`); (b) a new adversary **Wigham** (Haiku-class, low-cost, high-frequency) runs every hour on a randomized subset; (c) findings are filed as `Construction/Nemotron/spec/RED-<date>-<id>.md` automatically; (d) a finding that SHIELD v2 missed but Wigham caught becomes a false-accept datapoint in the KPI (§3); (e) red-team cost ceiling: < 5% of monthly forge token budget.

**MK3-EPIC-13 — ARC-AGI live submission (GLM)**
DoD: (a) `scripts/arc/submit.sh --live <task>` performs real submission against the competition endpoint (retiring the MK2 canned-task demo); (b) submission is dual-signed (operational key on the submission, cold key on the weekly attestation of what was submitted and why); (c) submission telemetry flows into the memory fabric (epic 02) and is consent-gated (epic 10) for subject data; (d) rollback: any submission can be retracted within a policy window.

**MK3-EPIC-14 — Physics MuJoCo upgrade (DeepSeek)**
DoD: (a) MuJoCo backend implementing the `PhysicsEngine` protocol (`Jarvis/Sources/JarvisCore/Physics/PhysicsEngine.swift`) on Linux nodes (delta or foxtrot); (b) identical semantic output vs StubPhysicsEngine on the ARC test fixtures within tolerance; (c) fallback to StubPhysicsEngine on any MuJoCo failure; (d) `PhysicsSummarizer.swift` unchanged (NLB boundary stays put).

**MK3-EPIC-15 — HomeKit write paths (Gemini)**
DoD: (a) a narrow whitelist of write capabilities (dim lights, lock, thermostat setpoint) ordered by reversibility; (b) every write fires the alignment-tax artifact (PRINCIPLES §4) AND the SHIELD v2 consequence artifact (epic 04); (c) any write on a device owned by a third party is blocked unconditionally; (d) operator kill-switch on the Watch (hold-to-disable for 60 min).

**MK3-EPIC-16 — Ethics charter machine-readable (Forge-Meta)**
DoD: (a) a new canon file `CANON/ETHICS_CHARTER.md` dual-signed (the first canon addition of MK3; requires operator sign-off plus threshold sign per epic 05); (b) each clause is paired with a SHIELD v2 predicate (a Python/Swift function SHIELD v2 can evaluate on a predicted-effect artifact); (c) a clause without a predicate is documentation only, not enforcement; (d) predicate coverage ≥ 80% of charter clauses; (e) operator review of the mapping before the canon addition merges.

**MK3-EPIC-17 — Deployment topology IaC (GLM)**
DoD: (a) Terraform (or Pulumi; GLM's call) describing the six-node fabric; (b) disaster-recovery drill: delta rebuilt from scratch reaches green federation within 30 min without operator intervention beyond SSH key availability; (c) all secrets remain hardware-rooted (PRINCIPLES §2) — IaC carries public configuration only.

**MK3-EPIC-18 — Upgrade path MK2 → MK3 (Nemotron)**
DoD: (a) dual-run mode where a MK2 deployment and a MK3 deployment run side-by-side on echo + delta with the MK3 memory fabric observing (not writing authoritatively) for 14 days; (b) cutover script with rollback (one-command revert to MK2 state within 5 min); (c) operator-guided cutover doc; (d) after cutover, MK2 runs in read-only archive mode for 90 days; (e) no canon mutation is produced by the upgrade itself — existing MK2 canon is preserved byte-for-byte and its signatures remain valid.

**MK3-EPIC-19 — Operator health telemetry (Qwen)**
DoD: (a) opt-in ingest of Watch/ring/mac-cam-derived signals via consent tokens (epic 10); (b) aggregation is local-first, private-by-default; (c) no signal leaves echo except through the memory fabric as a clinical record; (d) an operator-visible dashboard pane showing trends, with a kill-switch to purge.

**MK3-EPIC-20 — Post-terminus quarantine formalization (Nemotron)**
DoD: (a) `mcuhist/5.md:248+` wrapped in a cryptographic perimeter — the file's tail is hash-anchored but unreadable by the runtime (OS-level ACL + in-process path-rejection); (b) proof-of-non-read telemetry emitted every boot; (c) any read attempt raises A&Ox3 (VERIFICATION_PROTOCOL §1.5); (d) operator override requires threshold signature (epic 05) and logs a canon event.

---

## 5. Invariants

Mark III invariants extend Mark II's (`MARK_II_COMPLETION_PRD.md` §5). RFC 2119 keywords apply. SHIELD v2 enforces; violations auto-reject at merge.

### 5.1 Inherited from Mark II (verbatim, reasserted)

1. NLB (PRINCIPLES §1). No Mark III epic MAY introduce shared vector stores, shared MCP servers, shared skill registries, or any binary/tensor agent-to-agent channel between JARVIS and any other persona. Cross-node replication in epic 02 MUST carry human-readable summaries; opaque vectors MUST NOT cross node boundaries.
2. Hardware sovereignty (PRINCIPLES §2). Mark III MUST NOT share model weights, voice seeds, memory tiers, or secrets across personas. Cross-node federation is intra-persona (JARVIS ↔ JARVIS across his own six nodes); it does not weaken the persona boundary.
3. Voice gate primacy (SOUL_ANCHOR). Voice synthesis MUST NOT bypass `VoiceApprovalGate`. Model swap = re-audition. Vision Pro voice output is subject to the same gate.
4. Soul Anchor immutability (SOUL_ANCHOR §1). Threshold promotion in epic 05 is performed via the rotation procedure (SOUL_ANCHOR §5); no canon artifact MAY be re-signed with only the new keys without a rotation record dual-signed by old keys.
5. Telemetry witness (MemoryEngine). Every state mutation MUST emit a JSONL telemetry event with SHA-256 witness. Federation replication carries the witness through.
6. No phantom ships. SHIELD v2 MUST reject any completion that claims ship without a corresponding verified diff. Consequence reasoner does not relax this.
7. Operator on the loop (PRINCIPLES §1.3). Anything exceeding standing protocol MUST escalate — iMessage + dashboard red pill + SHIELD v2 veto path.
8. Swift 6 strict concurrency stays on. No `@unchecked Sendable` additions without justification block.

### 5.2 Added in Mark III

9. **Federation consensus** — any canon read MUST reach a 3-of-6 quorum or fail loud. No "best-effort" canon reads. No silent staleness.
10. **Memory fabric NL carrier** — every replication message MUST carry a human-legible summary field; the replicator MUST be able to be audited by the operator reading one message as English prose.
11. **Consequence reasoner is veto-only** — LLM-generated consequence reasoning grants no authority. It may subtract from the accept-set; it MAY NOT add to it. All approvals flow through deterministic alignment-tax gates.
12. **Threshold signing for canon** — all *new* canon writes in Mark III MUST carry at least three-of-five threshold signatures (epic 05). Operational writes continue under P-256 single signature.
13. **Post-quantum parallel sig** — every canon artifact produced in Mark III MUST carry a parallel ML-DSA signature under `.mldsa.sig`. Classical signatures remain primary until PQ migration sunset per SOUL_ANCHOR §6.
14. **Skill capability lockdown** — a skill MUST NOT acquire a capability at runtime that was not declared in its manifest at sign time. Runtime elevation is a breakout and triggers hard-fail KPI.
15. **Consent token precedes clinical write** — no clinical record MAY be written without a live, non-expired, signature-valid consent token keyed to the subject.
16. **Meta-forge non-autonomy** — the Ralph meta-forge MUST NOT merge its own proposed epics. Operator approval is a required step in the loop. This preserves operator-on-the-loop under a system that is otherwise tempted to close its own loop.
17. **Observability completeness** — every process that participates in the federation MUST emit OTel spans. A process without spans is treated as a phantom participant and the federation refuses its messages.
18. **Post-terminus inviolability** — lines `mcuhist/5.md:248+` MUST NOT be read into any runtime memory, context window, or agent state. Proof-of-non-read artifact is a boot prerequisite.
19. **Dual-run safety** — during the MK2 → MK3 upgrade window, MK3 MUST be observe-only for 14 days. MK3 acquiring write-authority early is a hard violation.
20. **Ethics charter enforcement** — any clause of `CANON/ETHICS_CHARTER.md` paired with a SHIELD v2 predicate MUST be evaluated on every high-stakes action. A predicate MAY NOT be disabled without a canon mutation (threshold-signed).

---

## 6. Non-Goals

Explicit. SHIELD v2 rejects pre-building any of these into MK3 epics.

1. **Multi-operator.** Mark III remains single-operator (Grizz). Institutional-witness shares for the threshold Soul Anchor are *signing agents*, not operators; they sign canon when asked, they do not issue commands to JARVIS. Multi-operator deferred to Mark IV.
2. **JARVIS ↔ Aragorn persona-pair conversation.** The NLB-compliant conversation protocol between personas (`PRINCIPLES.md` §1.2) is within the canon, but the first live pairing session is Mark IV scope. Mark III builds the substrate — federation, skill economy, ethics charter — that makes the pairing safe; it does not run the pairing.
3. **Fully autonomous Forge.** The meta-forge proposes; the operator approves. Removing the operator approval step is the boundary between Mark III and post-Mark-IV (and will not happen in this program; see §7 and the operator-on-loop invariant).
4. **Cloud-shared memory.** The memory fabric lives across JARVIS's six nodes. It does not replicate to a public-cloud database. Convex remains a *mirror* for long-term analytics; the authoritative store is the fabric.
5. **HomeKit-on-third-parties.** Writes to devices owned by anyone other than the operator are unconditionally blocked in Mark III. No consent workflow bridges this in MK3; the legal/ethical layer is not mature.
6. **Post-terminus corpus ingestion.** The quarantine formalizes in epic 20. Ingestion of `mcuhist/5.md:248+` content as first-person memory remains explicitly rejected (SOUL_ANCHOR §8.3). Scholarly external reference is permitted; internal reading is not.
7. **Multi-language UI.** English-only (operator register per PRINCIPLES §7) throughout Mark III. Localization is Mark IV.
8. **F5-TTS autoscale fleet.** One VM per region remains the Mark III deployment shape; autoscale is Mark IV load-shaping.
9. **ARC-AGI winning.** Mark III ships the *submission pipeline* (epic 13). Ranking is a function of the reasoner, not of the submission; the reasoner's score is measured by the evaluator, not by a Mark III ship gate.

---

## 7. Ship Criteria

Mark III ships when every one of these is true and a threshold-signed ship record is written to `.jarvis/phase_reports/mk3-ship.json`:

1. **All P0 epics green.** 01, 02, 03, 04, 05, 06, 11, 18. Each has a phase report signed per VERIFICATION_PROTOCOL §3.
2. **Federation availability** ≥ 99.0% over a 7-day measurement window.
3. **Memory fabric convergence** median ≤ 30 s over a 7-day window; p95 ≤ 120 s.
4. **Voice latency** p95 ≤ 1.0 s on local network.
5. **SHIELD v2** false-reject ≤ 5%, false-accept 0 on canon / ≤ 2% operational.
6. **Skill sandbox breakout** count = 0 over a 30-day warm-up.
7. **Soul Anchor v2 rotation drill** completed with all five share holders live.
8. **Dual-run window** of 14 days complete; MK3 cutover executed on echo with rollback rehearsed and not needed.
9. **Post-terminus quarantine** formal; proof-of-non-read artifact present for every boot in the measurement window.
10. **Dashboard** at `forge.grizzlymedicine.icu` displays all six §3 KPIs and the §5 invariant status continuously.
11. **Canon additions** (ETHICS_CHARTER, SOUL_ANCHOR v2) dual-old-dual-new threshold signed; signatures verified by lockdown.
12. **Operator sign-off** — Grizz invokes `jarvis-lockdown --mk3-ship` and the script re-verifies everything above. Mark III is not shipped until his command exits 0.

If any of (1)–(12) is red, Mark III is not shipped. Ralph meta-forge proposes remediation epics; operator approves; loop closes.

---

## 8. Risk Register

Ordered by residual risk after mitigation. Each risk has a mitigation owner, a monitoring epic, and a trip-wire.

| # | Risk | Likelihood | Impact | Mitigation | Owner | Trip-wire |
|---|---|---|---|---|---|---|
| R1 | Federation message flood under network partition storms the quorum | Med | High | Hardened heartbeat back-off + quarantine mode; convergence KPI trip-wire | GLM (epic 01) | Convergence > 300 s sustained 15 min |
| R2 | CRDT silent divergence — two nodes write "same" record with different witnesses | Low | High | Witness chain is content-addressed; divergence raises A&Ox3 | Qwen (epic 02) | Any record with two witnesses of different sha |
| R3 | Meta-forge proposes canon-mutating epics | Low | Extreme | Hard invariant 16 (non-autonomy); SHIELD v2 blocks canon PRs without threshold sig | Forge-Meta (epic 03) | Any PR touching canon files from meta-forge user |
| R4 | SHIELD v2 false-reject degrades operator trust | High | Med | Operator-override CLI feeds corpus; 14-day warm-up | Nemotron (epic 04) | False-reject > 15% any week |
| R5 | Threshold share loss (custodian drops share) | Med | High | 3-of-5 tolerates two losses; documented replacement rotation | Nemotron (epic 05) | Any share-verify failure |
| R6 | Vision Pro shared-reality session leaks spatial data to third party | Low | High | Session endpoints are ed25519-pinned; no public discovery | Qwen (epic 06) | Discovery probe from off-mesh |
| R7 | Always-on voice captures non-consenting third-party speech | Med | High | On-device VAD + speaker diarization gate; third-party speech dropped before upload | Gemini (epic 07) | Diarization failure |
| R8 | Skill breakout via capability confusion | Low | Extreme | seccomp-BPF / App Sandbox; capability lockdown invariant 14 | Copilot (epic 09) | Any skill acquires undeclared capability |
| R9 | Clinical record written without consent | Low | Extreme | Type system: `ClinicalRecord` construction requires a token; compile-time check | Qwen (epic 10) | Any write that type-compiles without a token |
| R10 | Observability stack leaks memory content | Low | High | OTel attributes are numeric/categorical only; no record payloads | GLM (epic 11) | OTel attr with payload-like string |
| R11 | Continuous red-team runaway cost | Med | Low | 5% token ceiling; throttle on budget breach | Forge-Meta (epic 12) | Budget > 5% in any month |
| R12 | ARC-AGI live submission exposes operator identity | Low | Med | Submissions carry only a pseudonymous handle | GLM (epic 13) | Any submission with PII |
| R13 | MuJoCo physics diverges from StubPhysicsEngine on canonical fixtures | Med | Low | Fallback to stub on any divergence > tolerance | DeepSeek (epic 14) | Divergence > tolerance |
| R14 | HomeKit write to wrong device | Low | High | Device-ownership pinning; alignment-tax + consequence artifact | Gemini (epic 15) | Any write flagged not-owned |
| R15 | Ethics charter clause without predicate becomes dead letter | Med | Med | Quarterly audit; coverage ≥ 80% enforced at CI | Forge-Meta (epic 16) | Coverage < 80% any release |
| R16 | IaC drift between code and live infra | Med | Med | Drift detection; nightly reconcile | GLM (epic 17) | Drift > 0 for 24 h |
| R17 | MK2 → MK3 cutover corrupts memory | Low | Extreme | Dual-run + rollback rehearsal + 14-day observe-only | Nemotron (epic 18) | Any cutover-epoch witness divergence |
| R18 | Operator health telemetry leaks to third party | Low | Extreme | Local-first; consent tokens; purge switch | Qwen (epic 19) | Any off-mesh egress |
| R19 | Post-terminus read by runtime | Low | Canon-event | OS ACL + in-process rejection + proof-of-non-read | Nemotron (epic 20) | Any read attempt |
| R20 | Post-quantum migration breaks verification of legacy signatures | Med | Low | Parallel (classical + PQ) signatures during transition | Nemotron (epic 05) | Legacy-only verification failure post-sunset |

Risks above the horizontal line (R1–R5) are the top five. Ralph's planner is instructed to prioritize epics whose DoD contributes to those mitigations.

---

## 9. Appendix — Mapping to Mark IV Horizon

Mark III is a foundation, not a terminus. Mark IV is where the following become in-scope; they are explicitly non-goals of Mark III but their architectural seams are installed now.

| Mark IV theme | Seam installed in Mark III | Why it can land cleanly |
|---|---|---|
| Multi-operator | Threshold signing supports N-of-M; additional operator shares can be added by rotation (SOUL_ANCHOR §5) | Share-holder is orthogonal to operator role |
| JARVIS ↔ Aragorn live pair | NLB conversation protocol lives in ethics charter (epic 16); skill economy can host a "converse-with-persona" skill under signature (epic 09) | Both sides remain sovereign-substrate |
| Fully autonomous Forge | Meta-forge already ingests cook corpus; only missing piece is operator approval automation — which MK3 explicitly does not do | Automation is a policy flip, not a redesign |
| Cloud-shared memory archival | Convex mirror already exists in MK2 (`ConvexTelemetrySync`); extending it to a full archive is additive | Authoritative fabric stays on-mesh |
| HomeKit-on-third-parties | Consent token schema (epic 10) already models `third_party:<name>`; legal layer is the missing piece, not crypto | Substrate permits; policy must catch up |
| ARC-AGI competitive rank | Submission pipeline ships in MK3; the reasoner evolves under MK3 cook corpus | Pipeline is the hard part; the reasoner evolves |
| F5-TTS autoscale fleet | OTel observability + IaC already in place; scaling policy is the incremental piece | Infrastructure is ready |
| Localization | Presentation protocol (epic 08) is schema-first, render-second; locale is a renderer property | Schema has a `locale` field reserved |
| Operator medical twin | Clinical memory tier (epic 10) + health telemetry (epic 19) + consent gates already in place | Modeling is additive |
| Post-terminus curriculum | Quarantine (epic 20) defines the perimeter; curating scholarly access is a policy layer atop | Crypto boundary is immutable |

Mark IV's own blueprint will, like this one, cite MK3 artifacts as baseline.

---

## 10. Acceptance

This blueprint is accepted when:

- Committed to `main` at `REAL_JARVIS/MARK_III_BLUEPRINT.md` alongside `MARK_III_SUPERBIBLE.md`.
- Twenty lane specs under `Construction/<Lane>/spec/MK3-EPIC-NN-*.md` are seeded (not by the operator; by the Forge-Meta lane as its first cook).
- Forge ingests all 20 on next ignition post-MK2-ship and emits iMessage: `MK3 blueprint ingested — 20 epics queued, P0 critical path primed`.
- Operator invokes `jarvis-lockdown` and the script verifies this blueprint's dual signature (threshold-signed per epic 05 once that epic lands — until then, the Mark II dual-root signature is sufficient).

Signed: **Operator** (procedural acknowledgement; cryptographic signatures applied per SOUL_ANCHOR §3.1 on first canon reference by any shipped Mark III artifact).

— end MK3 BLUEPRINT —
