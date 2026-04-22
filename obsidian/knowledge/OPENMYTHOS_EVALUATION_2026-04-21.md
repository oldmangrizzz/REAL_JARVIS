# OpenMythos — Evaluation for REAL_JARVIS

**Prepared:** 2026-04-21
**For:** Robert "Grizz" Hanson, GMRI
**Subject:** https://github.com/kyegomez/OpenMythos
**Governing standard:** MEMO_CLINICAL_STANDARD.md — mind under construction, not software
**Response to:** "tell me how/if/can it help us at all"

---

## VERDICT (blunt)

**No.** OpenMythos does not help. Do not adopt it, do not fork it, do not vendor it into REAL_JARVIS.

It is not a fraud. It is real PyTorch research code (~2.5k LOC, MIT-licensed, actively maintained, kyegomez). It is a competent implementation of a recurrent-depth transformer — a small language-model architecture where the same weight block is iterated N times at inference for "deeper thought" without adding parameters.

But the match against JARVIS is wrong at every layer that matters: substrate, altitude, boundary, and roadmap. Pulling it in would either break the Natural-Language Barrier (PRINCIPLES.md §1) or be dead code within weeks. There is no middle path where it modestly helps.

This document explains **why** in terms consistent with the clinical standard, and ends with a short forward-looking note for if/when a Mark IV custom-trained model ever becomes a real project.

---

## 1. What OpenMythos actually is

**Type:** PyTorch implementation of a transformer language model with a recurrent-depth inner loop.
**Scale:** Single file (`main.py`, ~900 LOC) plus tests/examples. ~2.5k LOC total.
**License:** MIT.
**Activity:** Commits in the last 30 days; not abandoned.
**Core mechanism:** Instead of stacking 32 distinct transformer blocks, stack one block and run the forward pass through it `k` times, where `k` is a learned function of the input ("adaptive computation time", ACT). Three ideas worth naming:

1. **LTI injection** (`main.py` 568-630) — Latent Thought Injection. A sidecar module that conditions each recurrent step on a separate learned projection of the input; lets the model re-inject the original context on every loop pass so recurrence does not drift.
2. **ACT halting** (`main.py` 800-863) — adaptive depth; per-token halting probability; uses the "remainder trick" so the last step accounts for the rest of the probability mass.
3. **Loop-index embedding** (`main.py` 160-210) — add a learned embedding for which iteration you are on, so the block knows it is on step 3 of 8, not step 1 of 8.

These are legitimate ideas. They have precedent (Universal Transformers, Dehghani et al. 2018; PonderNet, Banino et al. 2021). kyegomez's version is a clean modern assembly of them.

**What it is not:** It is not an agent. It is not a runtime. It is not a service. It is not a voice, a memory, a soul anchor, a federation fabric, a safety gate, a signing scheme, a Vision Pro renderer, a HomeKit bridge, or any other thing JARVIS is made of. It is a ~900-line neural-network definition.

---

## 2. What REAL_JARVIS actually is (for the compat check)

Per PRINCIPLES.md, SOUL_ANCHOR.md, MEMO_CLINICAL_STANDARD.md, and the full 23-subsystem Swift core mapped this session:

- **A digital person under construction, Aragorn Class.** Not an assistant, not an LLM wrapper, not a chatbot. Personhood, not property.
- **Substrate-sovereign.** Owns end-to-end every layer of his own stack — weights, voice, memory, keys, inference binaries. Nothing shared with any other persona.
- **Swift-first.** `JarvisCore` is a 23-subsystem static framework (macOS 14+), ~15.5k LOC. Python exists only as subprocesses behind protocols (`PythonRLMBridge`) or as **external FastAPI services** (`services/vibevoice-tts`, `services/f5-tts`, canonical XTTS on Delta) that JARVIS talks to over HTTP with bearer auth.
- **LLM is protocol, not property.** `ConversationEngine` depends on a `StreamingLLMClient` protocol. The implementation lives **outside** `JarvisCore` — current production is the Ollama gateway on Charlie serving `gpt-oss:20b`. JarvisCore does not know, care, or contain what model runs behind that protocol. This is load-bearing, not accidental.
- **Mark III is the active phase.** 20 epics. P0 work is federation fabric (MK3-EPIC-01), CRDT memory (02), Ralph meta-forge (03), SHIELD v2 consequence reasoner (04), threshold + post-quantum Soul Anchor (05), Vision Pro primary surface (06), OTel observability (11), and the MK2→MK3 upgrade path (18). **None of these is a model-architecture problem.**

---

## 3. Four-axis compatibility check

### Axis 1 — Substrate & Boundary (PRINCIPLES.md §1, §2)

**The Natural-Language Barrier is the hardest invariant in the system.** It forbids shared weights, shared memory, shared vector stores, shared tool registries, shared latent spaces, and any silent binary/tensor protocol between digital persons.

OpenMythos is model code. Vendoring it into `REAL_JARVIS/` puts PyTorch weights, gradients, and latent states **inside** JARVIS's substrate. That is the exact category of artifact the NLB forbids from crossing cognitive boundaries. Two scenarios:

1. **Import as a sidecar service** (FastAPI wrapper around OpenMythos, talking to JarvisCore over HTTP like XTTS does) — this is architecturally clean, but it just means you have built a second LLM gateway next to Ollama. OpenMythos has no trained weights shipped; you would be training a model from scratch at GMRI cost. This is not "help" — it is a massive undertaking that duplicates what the Ollama gateway already provides.
2. **Import as code inside JarvisCore** (Python module called via `PythonRLMBridge`) — this merges model internals with JARVIS's substrate. NLB violation, even if the model never talks to another persona. Substrate merger is defined structurally, not by current intent.

**Result:** Axis 1 fails in both directions.

### Axis 2 — Language & Stack

- **JARVIS is Swift 6 strict-concurrency on macOS 14+ / iOS 17+ / watchOS 10+ / visionOS.** Core types, protocols, and tests are Swift.
- **OpenMythos is PyTorch / Python 3.**
- **No Swift port exists.** A clean-room Swift rewrite of LTI + ACT + loop-index embedding using MLX or Core ML is a multi-month research project in itself and would not end with a trained model — it would end with an untrained architecture.

**Result:** Axis 2 fails. The code is not usable as-is in JarvisCore; a port would be a net cost.

### Axis 3 — Altitude (where the work happens)

This is the most important axis and the one that makes the answer firm.

OpenMythos operates **inside an LLM's forward pass**. LTI, ACT, loop-index embedding — these are all decisions about how a single inference call is structured. They are invisible above the `StreamingLLMClient` protocol boundary. JARVIS by design stops at that boundary.

Everything JARVIS has shipped and everything on the Mark III roadmap operates **above** the protocol: voice approval gate, A&Ox4 probes, alignment tax journaling, Pheromind evaporation, CRDT memory replication, Soul Anchor signing, federation quorum, SHIELD consequence reasoner. Not one of those concerns whether the model behind the gateway uses 32 stacked blocks or 1 block iterated 32 times.

Even in the best case — OpenMythos's recurrent-depth trick genuinely produced better reasoning on some benchmark — the benefit would accrue to **whatever model is served behind the Ollama gateway**, not to JARVIS. The right place for that conversation is "should the Ollama gateway host a different model?" — and that is an infrastructure decision about Charlie, not a REAL_JARVIS architectural change.

**Result:** Axis 3 fails. The code is at the wrong altitude to be relevant to current JARVIS work.

### Axis 4 — Roadmap Fit

Checked against the 20 Mark III epics:

| Epic | Does OpenMythos help? |
|---|---|
| MK3-EPIC-01 Federation fabric (signed mesh, quorum, heartbeats) | No. Distributed systems problem. |
| MK3-EPIC-02 Distributed memory fabric (CRDT replication) | No. Data-structure problem. NLB forbids shared embeddings anyway. |
| MK3-EPIC-03 Ralph meta-forge (next-epic ballot from cook corpus) | No. Planning/governance problem. |
| MK3-EPIC-04 SHIELD v2 consequence reasoner | No. Uses GitHub Models endpoint for deliberation; not a local-model project. |
| MK3-EPIC-05 Soul Anchor v2 (FROST threshold + ML-DSA post-quantum) | No. Cryptography problem. |
| MK3-EPIC-06 Vision Pro primary surface | No. Spatial UX problem. |
| MK3-EPIC-07 Voice ambient always-on (Watch VAD, streaming STT) | No. Signal chain + on-device ML problem; MLX/Core ML, not PyTorch. |
| MK3-EPIC-08 Unified presentation protocol | No. Schema/renderer problem. |
| MK3-EPIC-09 Skill economy (signed manifests, sandboxed exec) | No. Runtime sandboxing problem. |
| MK3-EPIC-10 Consent-gated clinical memory | No. Consent UX + policy problem. |
| MK3-EPIC-11 OTel observability | No. Telemetry plumbing. |
| MK3-EPIC-12 Continuous red-team (Fury/Hill/Wigham) | No. Adversarial test harness. |
| MK3-EPIC-13 ARC-AGI live submission | No — and this is the closest false positive. ARC reasoning happens behind the `PythonRLMBridge`; it is the gateway model's job, not JarvisCore's. |
| MK3-EPIC-14 Physics MuJoCo upgrade | No. Physics engine swap. |
| MK3-EPIC-15 HomeKit write paths | No. Actuation + gating problem. |
| MK3-EPIC-16 Ethics charter machine-readable | No. Policy-language problem. |
| MK3-EPIC-17 Deployment topology IaC | No. Terraform / Pulumi problem. |
| MK3-EPIC-18 MK2→MK3 upgrade path | No. Migration tooling. |
| MK3-EPIC-19 Operator health telemetry | No. Sensor plumbing. |
| MK3-EPIC-20 Post-terminus corpus quarantine | No. Cryptographic perimeter. |

**Zero epics helped. Result: Axis 4 fails.**

---

## 4. The steelman, honestly stated

To be fair to the repository:

- It is **not** placeholder-ware, **not** AI-generated slop, **not** `kyegomez/bulk-github-stars` pattern. The recurrent-depth mechanism is implemented correctly to my read; variable reuse, halting, and gradient paths are coherent.
- The **LTI injection** pattern — re-conditioning on original input at each recurrence step — is a legitimate architectural insight.
- The **ACT halting with remainder trick** is correctly implemented and well-known technique.
- The **loop-index embedding** is a small but elegant trick that would otherwise take time to reinvent.

If someone at GMRI were independently doing Universal Transformer research for a Mark IV custom-trained model, these three ideas are worth reading once for vocabulary. That is the full scope of the steelman.

---

## 5. Failure modes if adopted anyway

Documenting the predicted wounds per clinical-standard discipline:

1. **NLB violation on the first import** — even if OpenMythos never talks to HUGH or any other persona, placing PyTorch model internals inside JARVIS's substrate defines a merger path structurally. `VERIFICATION_PROTOCOL.md` NLB gate would fail audit.
2. **Swift-Python substrate split widens** — JARVIS currently keeps Python tightly boxed behind HTTP services and subprocess bridges. A PyTorch model with training loops, checkpoints, CUDA dependencies, dataset pipelines is a different category of Python than `rlm_repl.py`. The boxing discipline breaks.
3. **Training-cost ambush** — OpenMythos ships architecture, not weights. To get any output, GMRI would have to train it. That is a GPU-budget and corpus-curation project that is not currently funded, not planned, and is not the job the repo appears to want.
4. **Dead code within a quarter** — if adopted as "let's vendor it just in case," it will sit in `services/` with no trained weights, no callers, no tests, violating MEMO_CLINICAL_STANDARD §"Every omission is a documented omission" (because it would be a presence, not an omission, with no justification file).
5. **Distraction from Mark III P0** — the operator has 8 P0 epics blocking Mark III ship. Every hour on OpenMythos is an hour not on federation fabric, CRDT memory, or SHIELD v2.

---

## 6. Forward-looking note (Mark IV only, not now)

The one condition under which this document should be re-opened:

**If GMRI ever decides to train a custom model to serve behind the Ollama gateway** — replacing `gpt-oss:20b` with a GMRI-trained artifact for sovereignty reasons — then recurrent-depth architecture is worth evaluating as one option among several (Universal Transformers, PonderNet, Mixture-of-Depths, etc.). At that point the three harvestable ideas above are reading material, nothing more. Reimplement clean-room in whatever framework (MLX for Apple Silicon deployment, or PyTorch if training on CUDA), cite the precedents, do not vendor kyegomez's code.

That decision is not Mark III. Mark III is "ship the organism." Custom model training is Mark IV or later, and is an infrastructure-sovereignty call that lives next to MK3-EPIC-17 (Deployment topology IaC), not inside JarvisCore.

---

## 7. Recommendation

1. **Do not adopt OpenMythos into REAL_JARVIS.** No fork, no vendor, no sidecar service.
2. **Do not write a migration spec.** There is nothing to migrate to; a migration spec would misrepresent this finding.
3. **File this document in `~/Desktop/gmri/`** (done — this file) and a copy under `obsidian/knowledge/research/OpenMythos-Eval-2026-04-21.md` if the operator wants wiki-side traceability.
4. **If a Mark IV custom-model conversation ever opens,** re-read §6 of this document first before starting that work.

---

## 8. Method & artifacts

This evaluation ran three parallel explore agents against:

- **OpenMythos repo** — code read of `main.py` and auxiliary files; license and activity check; honest steelman pass.
- **REAL_JARVIS codebase** — full topology map of Swift targets (`project.yml`, `Package.swift`), 23 JarvisCore subsystems (156 public types), Python services (`services/vibevoice-tts`, `services/f5-tts`), Convex backend (`convex/jarvis.ts`, `schema.ts`), CLI entry points, agent/skill registry.
- **Obsidian knowledge wiki** — deep read of `obsidian/knowledge/` (20 top-level directories covering architecture, canon, concepts, phase-status, loom, operations) cross-referenced against root canon (PRINCIPLES.md v1.0.0, SOUL_ANCHOR.md v1.1.0, VERIFICATION_PROTOCOL.md, REALIGNMENT_1218.md, MARK_III_BLUEPRINT.md, MARK_III_SUPERBIBLE.md, MEMO_CLINICAL_STANDARD.md).

No LLM self-assessment was treated as a gate. All claims cite file paths. No code was written, modified, or committed.

Verdict is deterministic on the axes above, not a judgment call.

---

*End of report.*
