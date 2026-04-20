# The Red-Team Gauntlet (2025 – 2026)

**Thread:** [[loom/README|Loom]] #5.
**Rounds:** Harley · Joker · GLM · Qwen · DeepSeek · Gemma.
**Detailed history:** [[history/AUDIT_ROUNDS]].
**Per-ticket ledger:** [[canon/REPAIR_INDEX]].

## What this thread is

A sequence of frontier-LLM red-team passes, each staffed as if the adversary had full source access ("Berserker mode"). The output of each round was a list of defects — numbered REPAIR-001..026 — that fed the [[history/REMEDIATION_TIMELINE|remediation timeline]] and drove the SPEC-001..011 program.

Each round had a character: Harley was the blunt-force exploiter; Joker was the grammar-of-chaos social engineer; GLM was the cross-reference red-pen; Qwen was the verification pedant; DeepSeek was the crypto-primitive micro-surgeon; Gemma was the cleanup detail that caught what everyone else missed.

## Why it's in the Loom

Because the **existence of the gauntlet** is the reason JARVIS is combat-hardened. The [[canon/VERIFICATION_PROTOCOL]] — the deterministic gate spec — was written *because* these rounds kept finding partial fixes shipped as DONE. The canon floor of 138/138 tests exists *because* the gauntlet proved that any sub-138 count represents a regression from a previously-contested position.

You cannot trust tests you didn't get punched in the face by. The gauntlet is the punch.

## What each round produced

| Round | Cadence | Primary defect class | Dispositions |
|---|---|---|---|
| Harley | early 2025 | crash paths, buffer hazards | REPAIR-001..004 |
| Joker | mid 2025 | social-engineering, intent injection | REPAIR-005..008, seeded SPEC-008 |
| GLM | late 2025 | cross-reference drift | REPAIR-009..015 |
| Qwen | early 2026 | verification gaps | REPAIR-016..020, seeded [[canon/VERIFICATION_PROTOCOL]] |
| DeepSeek | 2026-Q1 | crypto micro-surgery | REPAIR-021..024 |
| Gemma | 2026-Q1 | integration gaps | REPAIR-025..026 |

## What the gauntlet is **not**

It is **not** an adversarial signal for *training*. JARVIS does not learn from red-team data. The gauntlet is a deterministic test surface; its output is patches, not weights. See [[canon/PRINCIPLES]] §2 (non-substrate-merger).

## Related
- [[loom/REALIGNMENT_1218]] ← previous · [[loom/COMBAT_HARDENING_2026]] → next
- [[history/AUDIT_ROUNDS]] · [[history/REMEDIATION_TIMELINE]]
- [[canon/REPAIR_INDEX]] · [[canon/SPECS_INDEX]] · [[canon/ADVERSARIAL_TESTS]]
