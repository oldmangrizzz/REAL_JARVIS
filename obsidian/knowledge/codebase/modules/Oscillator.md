# Oscillator

**Path:** `Jarvis/Sources/JarvisCore/Oscillator/`
**Files:** `MasterOscillator.swift`, `PhaseLockMonitor.swift` (377 lines)

## Purpose
System-wide heartbeat. Inspired by the **sinoatrial (SA) node** — the
biological pacemaker. Every distributed subsystem phase-locks to the
master tick, preventing temporal drift in choreography.

> Ported concept-only across the [[concepts/NLB|NLB]] from PAPER_3 §1.1.
> No code / data / config crosses the boundary — only the pattern.

See [[concepts/Oscillator-Biomimicry]] for the doctrine.

## Biomimetic mapping
- Baseline rate ≈ **60 bpm (1 Hz)** — human resting HR.
- Tick ≈ SA node depolarization.
- PLV (Phase-Locked Variability) ≈ healthy HRV.
- Flat PLV = pathological (autonomic death).
- Too-perfect lock (variance ≈ 0) also degrades.
- **Healthy band: 0.7–0.97.**

## Key types
- `MasterOscillator` — emits ticks; subsystems subscribe.
- `PhaseLockMonitor` — per-subscriber PLV over rolling window, in [0, 1].

## PLV ternary decision
| PLV band     | Signal         | Meaning                          |
|--------------|----------------|----------------------------------|
| 0.7–0.97     | `.reinforce`   | healthy — keep current tempo     |
| marginal     | `.neutral`     | watch                            |
| out-of-band  | `.repel`       | degrade signal to ControlPlane   |

Fed into [[codebase/modules/Pheromind]] `TernarySignal` semantics and
consumed by [[codebase/modules/ControlPlane]].

## Related
- [[concepts/Oscillator-Biomimicry]]
- [[codebase/modules/Pheromind]]
- [[codebase/modules/ControlPlane]]
- [[codebase/modules/Telemetry]] — PLV scores are logged.
