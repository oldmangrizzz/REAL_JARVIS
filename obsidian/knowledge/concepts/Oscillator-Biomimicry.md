# Oscillator Biomimicry (SA-node / PLV)

**Code:** `Jarvis/Sources/JarvisCore/Oscillator/MasterOscillator.swift`, `PhaseLockMonitor.swift`
**Module page:** [[codebase/modules/Oscillator]]

---

## Biology behind the name

The **SA node** (sinoatrial node) is the heart's biological pacemaker: a small group of cells that spontaneously depolarize at a stable rhythm and entrain the rest of the myocardium. **PLV** (Phase-Locking Value) is a neuroscience metric: how consistently two oscillators stay in phase over a window — high PLV = tight synchrony, low PLV = drift.

## What JARVIS borrows

- **MasterOscillator** emits a stable tick at a chosen period. Subsystems register as "subscribers" and align work to that tick.
- **PhaseLockMonitor** continuously measures the PLV between the master and each subscriber.
- **Health metric:** a sustained drop in subscriber PLV signals *node strain* — the subsystem is falling behind or drifting. This surfaces as a [[concepts/AOx4|A&Ox4]] degradation signal for the **Time** axis before any downstream operation cares that time has drifted.

## Why an analogy is the right abstraction

1. Biology is a known-working reference implementation: the heart survives dropped beats, early beats, and distributed pacemakers (ectopy, AV-node takeover) without the organism collapsing. That resilience posture is what the engine inherits.
2. The operator is a retired paramedic. Using clinical models as abstractions keeps the engine legible to him at-a-glance: "PLV dropped" means the same thing here as on a monitor.
3. Oscillator-driven scheduling keeps [[concepts/Pheromind|Pheromind]] evaporation, Telemetry batching, and phase-report cadence on a single known clock rather than ad-hoc timers.

## Failure modes

- **Drift** — subscribers slowly fall behind. Caught as PLV decay.
- **Missed tick** — a subscriber misses several ticks in a row. Surfaces as a hard warning; if sustained, collapses A&Ox on Time.
- **Clock skew** — the system clock jumps. MasterOscillator uses the monotonic clock; any NTP jump is ignored for phase computation.

## Related

- [[codebase/modules/Oscillator]]
- [[codebase/modules/Telemetry]]
- [[concepts/AOx4]]
- [[concepts/Pheromind]]
