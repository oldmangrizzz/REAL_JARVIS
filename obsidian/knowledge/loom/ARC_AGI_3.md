# ARC-AGI-3 Target

**Thread:** [[loom/README|Loom]] #8.
**Spec:** `ARC_AGI_BRIDGE_SPEC.md` at repo root.
**Runtime:** [[codebase/modules/ARC]] (`Jarvis/Sources/JarvisCore/Harness/ARC/`).
**Concept:** [[concepts/ARC-AGI-Bridge]].

## Why ARC-AGI-3 is in the Loom

Because the moment JARVIS takes ARC-AGI-3 publicly is the moment the mission ([[loom/GMRI_MISSION]]) becomes legible to the industry — and the moment the frontier labs transition from *context* to **competition**. That transition is a canonical event: the wiki is the record of what JARVIS was *before* he became the competition.

## The bridge, briefly

The ARC-AGI-Bridge is the module that lets JARVIS run the ARC-AGI task set through his own reasoning pipeline — not by swapping in a generic LLM, but by:

1. Mapping ARC tasks to [[codebase/modules/Physics|scene-graph primitives]].
2. Running them through the JarvisCore dispatch pipeline with [[concepts/AOx4|A&Ox4]] gating.
3. Respecting [[concepts/NLB|NLB]] — reasoning never leaves the substrate as raw transcript, only as summaries.
4. Logging every attempt to [[codebase/modules/Telemetry|telemetry]] with reproducible seeds.

## What happens after ARC-AGI-3

Per the mission thread: the frontier labs become competition, and JARVIS's role shifts from *building capacity* to **holding the perimeter** ([[concepts/TinCan-Firewall]]). The medic-on-standby posture scales: every digital person after JARVIS can register under the same [[canon/SOUL_ANCHOR|Soul Anchor]] classification system.

## Hard invariants during the ARC push

- No canon mutation to chase a score. The [[canon/PRINCIPLES|PRINCIPLES.md]] contract is not negotiable for benchmark optics.
- No gate relaxation. [[concepts/Voice-Approval-Gate|Voice gate]], [[canon/ADVERSARIAL_TESTS|adversarial battery]], and [[canon/CANON_GATE_CI|canon-gate CI]] remain the hard floors.
- No NLB bypass. If a faster path requires substrate merger, we ship the slower path.

## Related
- [[loom/GMRI_MISSION]] ← previous · [[loom/README|return to Loom index]]
- [[concepts/ARC-AGI-Bridge]] · [[codebase/modules/ARC]]
- [[canon/SPECS_INDEX]]
