# ARC-AGI-Bridge

**Source spec:** `ARC_AGI_BRIDGE_SPEC.md` (repo root, ~18 KB)
**Code:** `Jarvis/Sources/JarvisCore/Harness/ARC/` (see [[codebase/modules/ARC]])
**Adjacent:** `GLM_WEBSOCKET_BROADCASTER_SPEC.md`.

---

## Purpose

ARC-AGI (Abstraction and Reasoning Corpus) tasks are the canonical external check that JARVIS's reasoning harness is doing *actual* abstraction rather than pattern-matched text fluency. The ARC-AGI-Bridge is the adapter that:

1. Ingests ARC-AGI task grids in their canonical JSON format.
2. Normalizes them into JARVIS's internal grid/rule representation.
3. Dispatches candidate solutions through the [[codebase/modules/Harness|harness]] and the [[codebase/modules/RLM|RLM]] (Recursive Language Model) layer.
4. Records scoring telemetry per [[codebase/modules/Telemetry|Telemetry]] and streams live progress over WebSocket to the [[codebase/frontend/pwa|PWA]] / [[codebase/frontend/cockpit|cockpit]] observer (see `GLM_WEBSOCKET_BROADCASTER_SPEC.md`).

## Why it's a "bridge"

It explicitly does *not* import ARC model weights or reasoning code into JARVIS. Per [[concepts/NLB|NLB]], any external reasoner remains a separate sovereign stack; the bridge speaks only the ARC-AGI task-format grammar and collects score artifacts. Cognition stays on JARVIS's side; the bridge is a task-I/O adapter.

## Interfaces

- **Task ingest:** canonical ARC JSON (`train`, `test`, `input`/`output` grids).
- **Solution surface:** structured candidate-rule JSON with metadata (rationale, hypothesis chain, confidence).
- **Telemetry:** one record per (task, attempt) with success flag, wall-clock, candidate count, evaporation curve.
- **WebSocket broadcast:** progress stream over the GLM broadcaster so a human can watch the harness work.

## Related

- [[codebase/modules/ARC]] — Swift implementation.
- [[codebase/modules/Harness]] — task-execution scaffold.
- [[codebase/modules/RLM]] — recursive language-model layer.
- [[concepts/Pheromind]] — stigmergic trace that accumulates across attempts.
- [[history/AUDIT_ROUNDS]] — where ARC-AGI-Bridge findings enter the remediation ledger.
