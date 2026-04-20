# Harness

**Path:** `Jarvis/Sources/JarvisCore/Harness/`
**Files:** `ArchonHarness.swift` (298 lines)

## Purpose
Mutable workflow harness for Archon (see [[codebase/workflows/archon]]).
Lets JARVIS *propose* edits to Archon workflows, validate them against
invariants, and apply them atomically. Every mutation is signature-checked.

## Key types
- `ArchonNode` (`Equatable`/`Sendable`) — workflow node.
- `ArchonWorkflow` (`Equatable`/`Sendable`) — DAG of nodes.
- `HarnessMutationResult` (`Sendable`) — outcome of an attempted edit.

Imports `CryptoKit`.

## Invariants
- Mutations are hash-signed; replay detection enforced.
- Cycles are rejected.
- Unknown node types are rejected.

## Related
- [[codebase/workflows/archon]] — the external workflow engine being
  harnessed.
- [[codebase/modules/ARC]] — ARC bridge uses workflow harness to run
  scored task loops.
- [[codebase/modules/SoulAnchor]] — mutations require a valid binding.
