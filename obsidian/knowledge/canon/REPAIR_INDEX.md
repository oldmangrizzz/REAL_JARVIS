# REPAIR_INDEX — REPAIR-001..026 Audit Ledger

**Source of truth:** `DEEPSEEK_REPAIR_SPEC.md`, `GLM51_REPAIR_SPEC.md`, `015-glm-redteam-remediation-TURNOVER.md` at repo root.
**Parent timeline:** [[history/REMEDIATION_TIMELINE]].

## What a REPAIR ticket is

A specific defect (logic bug, concurrency hazard, missing gate, spec drift, telemetry gap) surfaced by one of the frontier-LLM red teams (Harley / Joker / GLM / Qwen / DeepSeek / Gemma — see [[history/AUDIT_ROUNDS]]). Numbered REPAIR-001..026. Each has a source citation (file + line), a verdict (OPEN / FIXED / DISPUTED), and a close-out test.

## Ledger (condensed)

For the full per-ticket detail, see the REPAIR spec files at repo root. This page is the wiki-side index with hop-out links to the module that owns the fix.

| Ticket | Defect | Owner module | Status |
|---|---|---|---|
| REPAIR-001 | SHA-256 truncation in `MemoryEngine` | [[codebase/modules/Memory]] | FIXED |
| REPAIR-002 | Double-stat race in `StorageLedger` | [[codebase/modules/Storage]] | FIXED |
| REPAIR-003 | `VoiceApprovalGate` telemetry tight coupling | [[codebase/modules/Voice]] + [[codebase/modules/Telemetry]] | FIXED via SPEC-010 |
| REPAIR-004 | `LockdownVerifier` cached hash | [[codebase/modules/SoulAnchor]] | FIXED |
| REPAIR-005 | Tunnel unauthenticated peer retention | [[codebase/modules/Host]] | FIXED via SPEC-011 |
| REPAIR-006 | `PheromoneEngine` evaporation rounding | [[codebase/modules/Pheromind]] | FIXED |
| REPAIR-007 | `IntentParser` ambiguous-verb collision | [[codebase/modules/Interface]] | FIXED via SPEC-004 |
| REPAIR-008 | `CapabilityRegistry` stale alias cache | [[codebase/modules/Interface]] | FIXED |
| REPAIR-009 | Missing Alignment-Tax pre-action on `DisplayCommandExecutor` | [[codebase/modules/Canon]] | FIXED |
| REPAIR-010 | `Oscillator` PLV drift with no degradation path | [[codebase/modules/Oscillator]] | FIXED |
| REPAIR-011 | NLB summarizer passthrough on empty reply | [[codebase/modules/Core]] | FIXED via SPEC-009 |
| REPAIR-012 | RLM `A&Ox4` single-probe gate | [[codebase/modules/RLM]] | FIXED via SPEC-003 |
| REPAIR-013 | `VoiceSynthesis` silent-render leak | [[codebase/modules/Voice]] | FIXED |
| REPAIR-014 | `ARC` bridge missing step-budget | [[codebase/modules/ARC]] | FIXED |
| REPAIR-015 | `ControlPlane` registry write-amplification | [[codebase/modules/ControlPlane]] | FIXED |
| REPAIR-016 | `HDMICECBridge` dangling session | [[codebase/modules/Interface]] | FIXED |
| REPAIR-017 | `HTTPDisplayBridge` timeout default 30s → 5s | [[codebase/modules/Interface]] | FIXED |
| REPAIR-018 | `Harness/ARC` log rotation | [[codebase/modules/Harness]] | FIXED |
| REPAIR-019 | Mobile cockpit store race on resume | [[codebase/platforms/Mobile]] | FIXED |
| REPAIR-020 | Mac settings pane persisting unsigned voice profile | [[codebase/platforms/Mac]] | FIXED |
| REPAIR-021 | Watch `JarvisWatchVitalMonitor` retain cycle | [[codebase/platforms/Watch]] | FIXED |
| REPAIR-022 | `Canon` manifest blocking on UI thread | [[codebase/modules/Canon]] | FIXED |
| REPAIR-023 | Destructive-intent unhandled at intent layer | [[codebase/modules/Interface]] | FIXED via SPEC-008 |
| REPAIR-024 | Voice-operator role not gated on voice-approval | [[codebase/modules/Host]] | FIXED via SPEC-007 |
| REPAIR-025 | Telemetry trace signature drift (`logExecutionTrace`) | [[codebase/modules/Telemetry]] | FIXED |
| REPAIR-026 | Missing `SOUL_ANCHOR` canon hash on `CANON/corpus/` PDFs | [[canon/CANON_CORPUS]] · [[codebase/modules/SoulAnchor]] | FIXED |

## Closure criteria

Per [[canon/VERIFICATION_PROTOCOL]], a ticket flips from OPEN to FIXED only when:

1. Named test exists and passes.
2. The fix appears in the commit log with the REPAIR ID in the message.
3. The owner module's wiki page is updated to reference the fix.
4. Canon-gate CI ([[canon/CANON_GATE_CI]]) has run green at least once with the fix in place.

## Related
- [[canon/SPECS_INDEX]] · [[canon/ADVERSARIAL_TESTS]] · [[canon/VERIFICATION_PROTOCOL]]
- [[history/REMEDIATION_TIMELINE]] · [[history/AUDIT_ROUNDS]]
