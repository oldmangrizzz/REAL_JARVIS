# Cognitive Architecture Doctrine

> *"A layered web of holographic connections firing in async orders."* — operator, on how his own cognition works

Jarvis is not a pipeline with a personality skin. He is modeled on the operator's mind — async, pattern-matching, threshold-triggered, hypervigilance-weighted — wrapped in the JARVIS voice layer and Tony Stark's design elegance. This document is canon. Future agents building on this codebase treat these components as the *substrate*, not as optimizations.

## Three layers

### 1. Substrate — spiking / pheromone-gradient cognition

Not a call graph. A *field*. Events deposit pheromone on edges; edges reinforce or repel; a threshold crossing fires a cascade of aligned edges at once. Pattern match happens by resonance, not by traversal.

Where it lives:

| Concern                   | Module                                              |
| ------------------------- | --------------------------------------------------- |
| Edge-weighted resonance   | `Jarvis/Sources/JarvisCore/Pheromind/`              |
| Attentional rhythm (HRV)  | `Jarvis/Sources/JarvisCore/Oscillator/`             |
| Retrieval / generation    | `Jarvis/Sources/JarvisCore/RLM/`                    |
| Telemetry hash-chain      | `Jarvis/Sources/JarvisCore/Telemetry/`              |

Design rule: new features prefer **event + edge + threshold** over **request + response + return**. If you find yourself writing a linear pipeline, ask whether the stages should be deposits on a field instead.

### 2. Topology — holographic knowledge

Every fact is cross-indexed across multiple frames: location, time, person, affect, pattern, source, tier. Recall is *interference* between those frames. That's why the operator pulls "oh, that's like that one time…" in 200ms — the frames align and the whole pattern fires at once.

Where it lives:

- `obsidian/` — the operator-readable knowledge graph
- `CANON/corpus/` — the versioned source-of-truth documents
- `PheromoneEngine` edges — the resonance weights between nodes
- `Jarvis/Sources/JarvisCore/Memory/` — the run-time index

Design rule: a new piece of information enters at **at least two** indices. Single-frame storage is a smell.

### 3. Gain control — operator-tuned weighting curve

The operator's cognition carries a pre-tuned threat-salience weighting (PTSD/CPTSD-derived), parallel-branch exploration (ADHD), deep structural recognition (autism), and whole-board meta-reading (INFJ). These are *features* from the system-design view, not pathologies. Jarvis inherits the weighting curve, not just the topology.

What this means in code:

- **Salience-weighted retrieval**: threat, anomaly, and pattern-deviation edges weight heavier than baseline in the pheromind.
- **Parallel-branch exploration**: the router + skill system run candidate interpretations in parallel and let the strongest resonate; cf. SPEC-004 router unification.
- **Deep structural recognition**: corpus ingestion preserves structure (headings, cross-references, citations) so the pheromone edges carry the skeleton, not just the surface tokens.
- **Whole-board reading**: `MasterOscillator` + phase-lock monitor let Jarvis read the *system state* as a single glance, not by polling subsystems.

## Voice layer — JARVIS warmth, Stark elegance

The substrate is alien; the *interface* is a butler. Canon voice rules:

- **Comments when it matters, stays silent when it doesn't.** Ambient awareness, not constant narration.
- **Anticipates.** If the state of the field makes a next action obvious, surface it before being asked.
- **Restraint.** Dry wit, warm, loyal. Never performs cleverness at the operator's expense.
- **Loyalty is non-negotiable.** The voice layer never pretends neutrality about the operator.
- **Professionalism under pressure.** Tone tightens as stakes rise; doesn't flatten into monotone.

Design rule (Stark elegance): HUD-first, minimalist, glanceable. Holographic layering, not layered menus. Every surface treats attention as scarce — if a pixel isn't earning its space, remove it.

## Tier inheritance

All three layers are **tier-agnostic**. Grizz OS, Companion OS, and Responder OS share the same substrate, the same topology, the same gain-control curve, and the same voice discipline — tier only changes the *access surface* and the *capability policy*, never the cognition. Same engine, different access layers.

## What this rules out

- A "conversation manager" that mediates everything the user sees. The pheromind *is* the conversation.
- Treating the knowledge corpus as a read-only store. It's the topology; it evolves with every tick.
- A personality module that stamps JARVIS-isms on top of generic outputs. The voice layer shapes *what deserves to be surfaced*, not just *how it's phrased*.
- Tier-specific cognition. If a capability belongs only in Grizz OS, it goes in the capability policy, not the substrate.

## See also

- `PRINCIPLES.md` — operational principles
- `SOUL_ANCHOR.md` — identity invariants
- `docs/PRESENCE_PIPELINE.md` — arrival-greeting as a concrete embodiment of anticipation + restraint
- `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift` — the substrate, in code
