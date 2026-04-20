# Core

**Path:** `Jarvis/Sources/JarvisCore/Core/`
**Files:** `JarvisRuntime.swift`, `SkillSystem.swift` (211 lines)

## Purpose
Top-level runtime + skill dispatch. `JarvisRuntime` is the long-lived container
that owns subsystem references. `JarvisSkillRegistry` is the pluggable-verb
layer: skills are registered at boot with a descriptor, and dispatched by name.

## Key types
- `JarvisRuntime` — final class; the engine singleton.
- `JarvisSkillDescriptor` — `Sendable` struct describing a skill.
- `JarvisSkillRegistry` — stores descriptors + handlers.
- `SkillHandler` — typealias: `(input, runtime) throws -> [String: Any]`.

## Related
- Dispatched from [[codebase/modules/Interface]] via the command router.
- Skills often delegate to [[codebase/modules/ControlPlane]],
  [[codebase/modules/Memory]], or [[codebase/modules/Voice]].
- Every skill execution is subject to [[architecture/TRUST_BOUNDARIES]]
  (A&Ox4, Alignment-Tax gates).

## Entry points
- `JarvisRuntime()` — constructed by the platform host
  ([[codebase/platforms/App]], [[codebase/platforms/Mac]], etc.).
- Skills registered at boot from platform bootstrappers.

## See also
- [[codebase/CODEBASE_MAP]]
- [[concepts/NLB]] — skills that call LLMs MUST go through the summarizer.
