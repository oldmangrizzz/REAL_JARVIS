# Physics

**Path:** `Jarvis/Sources/JarvisCore/Physics/`
**Files:** 3 (691 lines)
- `PhysicsEngine.swift` — protocol
- `PhysicsSummarizer.swift` — **the NLB summarizer** (see [[concepts/NLB]])
- `StubPhysicsEngine.swift` — real in-process backend (not a TODO)

## Purpose
> JARVIS does not "imagine" what happens when a thing is pushed.
> JARVIS asks the engine. The engine returns ground truth.
> Reasoning is checked against physics before it leaves the host.

## Architecture (locked)
```
Mac (host)              ←  truth-physics, JarvisCore consumer
  └── PhysicsEngine     ← protocol defined here
       └── StubPhysicsEngine   ← today
       └── MuJoCoBackend       ← plugged in later (same protocol)
```

## StubPhysicsEngine properties
- Explicit Euler integrator.
- Gravity-correct: **-9.80665 m/s²**.
- Sphere/box AABB-vs-plane collision, restitution, friction.
- Not articulated; not body-vs-body contact-rich. That's deferred to MuJoCo.

## PhysicsSummarizer — **the NLB**
This is the **only sanctioned way** to inject physics state into an LLM
prompt. The LLM never sees raw arrays.
- Numbers are quantized.
- Counts are bucketed.
- Labels are surfaced.
- Past `maxBodies`, tail collapsed to `(N more)`.
- Output is `PhysicsSummary` — `Codable`, `Sendable`, `Equatable`.

## Related
- [[concepts/NLB]] — the doctrine this enforces.
- [[codebase/modules/ARC]] — feeds grid worlds into this engine.
- [[architecture/TRUST_BOUNDARIES]] — physics is source of truth; LLM is sink.
