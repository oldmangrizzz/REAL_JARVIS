# RLM

**Path:** `Jarvis/Sources/JarvisCore/RLM/`
**Files:** `PythonRLMBridge.swift` (143 lines)

## Purpose
Bridge to a **Python-side retrieval/language model** helper. Bounded
request/response shape; zero Python-ness leaks into Swift.

## Key types
- `RLMQueryResult` — the returned structure (text, citations, scores).
- `PythonRLMBridge` — the launcher/caller.

## Invariants
- All traffic with the Python side is through serialized JSON shapes.
- The bridge is **inbound-only** from JARVIS's perspective — Python
  cannot initiate calls back into the process.
- Python side is expected to be a sandboxed child process or
  a network endpoint. Never `eval`.

## NLB relevance
Anything the RLM returns that goes into an LLM prompt must first pass
through the [[concepts/NLB|NLB]] summarizer.

## Related
- [[codebase/modules/Memory]] — RLM often supplies candidates that become
  knowledge nodes.
- [[concepts/NLB]]
- `scripts/render_briefing.py` — a sibling Python helper.
