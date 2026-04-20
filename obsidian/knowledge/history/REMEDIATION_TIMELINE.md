# Remediation Timeline

Canonical index of the cross-referenced audit rounds and REPAIR
tickets. Source: `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` (root),
`MEDIUM_REMEDIATION_COMPLETION_REPORT.md`, and the round-specific
findings files (see [[history/AUDIT_ROUNDS]]).

## Totals after dedup
- CRITICAL: 7
- HIGH: 12
- MEDIUM: 13
- LOW: 9
- INFORMATIONAL: 6

## REPAIR ticket list (execution order)

### Phase 1 — CRITICAL (must complete first)
| ID | Subject | Module |
| --- | --- | --- |
| REPAIR-001 | PheromoneEngine data race → actor conversion | [[codebase/modules/Pheromind]] |
| REPAIR-002 | MasterOscillator concurrent onTick → serial dispatch | [[codebase/modules/Oscillator]] |
| REPAIR-003 | MasterOscillator ghost tick → timer guard | [[codebase/modules/Oscillator]] |
| REPAIR-004 | ARCGrid jagged array validation | [[codebase/modules/ARC]] |
| REPAIR-005 | TunnelServer unbounded buffer → per-connection limit | [[codebase/modules/Host]] |
| REPAIR-006 | Keychain error message — remove shell command from prod | [[codebase/modules/SoulAnchor]] |
| REPAIR-007 | VoiceSynthesis unsafe memcpy → safe copy | [[codebase/modules/Voice]] |

### Phase 2 — HIGH
| ID | Subject | Module |
| --- | --- | --- |
| REPAIR-008 | StubPhysicsEngine substep cap | [[codebase/modules/Physics]] |
| REPAIR-009 | PythonRLMBridge timeout | [[codebase/modules/RLM]] |
| REPAIR-010 | TunnelServer accept() → dispatch queue | [[codebase/modules/Host]] |
| REPAIR-011 | ARCHarnessBridge track processed files | [[codebase/modules/ARC]] |
| REPAIR-012 | MemoryEngine graph size limit | [[codebase/modules/Memory]] |
| REPAIR-013 | ArchonHarness "no errors" false-failure | [[codebase/modules/Harness]] |
| REPAIR-014 | VoiceApprovalGate string-match → enum-based error | [[codebase/modules/Voice]] |
| REPAIR-015 | AOxFourProbe complete error classification | [[codebase/modules/Core]] |
| REPAIR-016 | MyceliumControlPlane passphrase via pipe (not env) | [[codebase/modules/ControlPlane]] |
| REPAIR-017 | TelemetryStore `try?` → `try` | [[codebase/modules/Telemetry]] |
| REPAIR-018 | StubPhysicsEngine subnormal mass guard | [[codebase/modules/Physics]] |
| REPAIR-019 | StubPhysicsEngine zero-extent plane guard | [[codebase/modules/Physics]] |

### Phase 3 — MEDIUM
| ID | Subject | Module |
| --- | --- | --- |
| REPAIR-020 | PhaseLockMonitor NaN guard | [[codebase/modules/Oscillator]] |
| REPAIR-021 | ConvexTelemetrySync configurable URL + auth | [[codebase/modules/Telemetry]] |
| REPAIR-022 | ArchonHarness YAML quoting | [[codebase/modules/Harness]] |
| REPAIR-023 | ARCGrid empty-grid guard | [[codebase/modules/ARC]] |
| REPAIR-024 | MyceliumControlPlane HTML escaping | [[codebase/modules/ControlPlane]] |
| REPAIR-025 | PheromoneEngine Infinity clamp | [[codebase/modules/Pheromind]] |
| REPAIR-026 | TunnelServer source verification | [[codebase/modules/Host]] |

### Phase 4 — LOW + INFORMATIONAL
Remaining 15 items — style, logging hygiene, metadata. Executed in
batch once the higher severities clear.

## Notable late-cycle items (CX numbering)

- **CX-044** — `JarvisHostTunnelServer` switched to `SecRandomCopyBytes`
  for nonces (weak PRNG prior). See [[codebase/modules/Host]].
- **CX-047** — final security sweep referenced in
  `adversarial-audit-report-validation.md`.

## RLMREPL execution rule
**READ → EVAL → LOOP → MUTATE → PERSIST.** Every repair ships with a
test that reproduces the bug *before* the fix, and the fix is committed
only after the test flips green on a real build
(`xcodebuild -project Jarvis.xcodeproj -scheme Jarvis test`).

## Anti-regression
- Stubs may not be reintroduced.
- Canon must not drift — `scripts/regen-canon-manifest.zsh` is a
  privileged operation.
- [[concepts/NLB]], [[concepts/Voice-Approval-Gate]],
  [[codebase/modules/SoulAnchor]] invariants are load-bearing;
  any repair that appears to relax them is a bug in the repair.

## See also
- [[history/AUDIT_ROUNDS]]
- [[history/SESSION_LOGS_INDEX]]
- `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` (repo root, authoritative)
- `MEDIUM_REMEDIATION_COMPLETION_REPORT.md`
