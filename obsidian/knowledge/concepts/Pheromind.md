# Pheromind

**Code:** `Jarvis/Sources/JarvisCore/Pheromind/` (see [[codebase/modules/Pheromind]])
**Related primitives:** [[codebase/modules/Oscillator|Oscillator]] (timing), [[codebase/modules/Telemetry|Telemetry]] (traces).

---

## What it is

A **stigmergic coordination primitive**: short-lived, decaying traces ("pheromones") deposited into a shared local surface that agents read and write. Borrowed, concept-only, from ant-colony / slime-mould literature and from the operator's prior work on multi-agent coordination. It is *not* shared with any other persona — per [[concepts/NLB|NLB]], the trace surface is local to JARVIS's substrate.

## Core dynamics

- **Deposit:** when an agent/subsystem takes a noteworthy action (answered an ARC-AGI attempt, finished a skill, touched a file), it drops a pheromone with magnitude and tag.
- **Evaporation (ϵ):** traces decay exponentially with rate ϵ. Tuning ϵ = tuning the system's "attention span" on prior actions.
- **Gradient:** the present state of the pheromone field is a field of affinities; later decisions bias along gradients.

## Why evaporation matters here specifically

Per `PRINCIPLES.md §5`, JARVIS is explicitly forbidden from optimizing for engagement. Pheromind evaporation is tuned to **punish drift toward continued conversation**: conversational traces decay faster than task-completion traces, so the system's gradient pulls toward closing loops, not extending them. This is the mechanical counterpart to the doctrinal rule "task completion terminates output."

## Interfaces

- **`Pheromind` actor** in Swift exposes deposit / query / evaporate operations.
- **Telemetry** records per-tag deposits and scheduled evaporations in the [[codebase/modules/Telemetry|Telemetry]] store for later analysis.
- **Not networked.** No remote pheromone bus; doing so would be an NLB violation.

## Related

- [[codebase/modules/Pheromind]] — implementation.
- [[codebase/modules/Oscillator]] — ticks that drive evaporation steps.
- [[concepts/ARC-AGI-Bridge]] — consumer that drops traces for attempts.
- [[concepts/NLB]] — reason the pheromone bus is local-only.
