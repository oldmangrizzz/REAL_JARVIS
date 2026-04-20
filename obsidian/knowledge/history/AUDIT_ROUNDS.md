# Audit Rounds

Multiple LLM-driven red-team / adversarial audit rounds were run
against the codebase. Each round has a codename and a findings file at
the repository root. They are cross-referenced and deduped in
`VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` (→
[[history/REMEDIATION_TIMELINE]]).

## Rounds

| Round | Findings file | Focus |
| --- | --- | --- |
| **Harley (Qwen)** | `QWEN_HARLEY_FINDINGS.md`, `QWEN_HARLEY_REDTEAM_SPEC.md` | Red-team posture, adversarial inputs, guardrail probing. |
| **Joker (GLM 5.1)** | `GLM51_JOKER_FINDINGS.md`, `GLM51_JOKER_REDTEAM_SPEC.md`, `GLM51_REPAIR_SPEC.md` | Concurrency, crypto misuse, state hazards. |
| **DeepSeek** | `DEEPSEEK_REPAIR_SPEC.md` | Deep-logic review (physics, ARC bridge, RLM). |
| **GLM WebSocket broadcaster** | `GLM_WEBSOCKET_BROADCASTER_SPEC.md` | Tunnel/WS hardening. |
| **Final Push** | `FINAL_PUSH_HANDOFF.md`, `015-glm-redteam-remediation-TURNOVER.md` | Last-mile remediation + handoff. |
| **Production Hardening** | `PRODUCTION_HARDENING_SPEC.md` | Deployment + operational hygiene. |
| **ARC-AGI Bridge** | `ARC_AGI_BRIDGE_SPEC.md` | Spec for the ARC harness and its bridge to Archon. |
| **Gap Closing** | `GAP_CLOSING_SPEC.md`, `GAP_CLOSING_STATUS.md` | Remaining items post-main-sweep. |
| **Adversarial Audit Validation** | `adversarial-audit-report-validation.md` | Validation pass over the whole audit chain. |

## How they chain
- Harley + Joker independently produce findings.
- DeepSeek re-audits.
- Findings are **deduped** into `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md`
  and turned into REPAIR-### tickets.
- Tickets execute via the **RLMREPL** loop
  (see [[history/REMEDIATION_TIMELINE]]).
- "Final Push" and "Gap Closing" capture the tail.

## Principle
> Every round is adversarial. No round is treated as friendly. A finding
> is valid until a test proves otherwise.

## See also
- [[history/REMEDIATION_TIMELINE]]
- [[codebase/testing/TestSuite]]
