# Session Logs Index

Repo root contains raw session transcripts from prior model
interactions. They are **primary source material** — the audit rounds
([[history/AUDIT_ROUNDS]]) and the remediation timeline
([[history/REMEDIATION_TIMELINE]]) were distilled from these.

## Files

| File | Origin | What's in it |
| --- | --- | --- |
| `claude1.md` | Claude early session | First large-scope architectural discussion / canon alignment. |
| `claudelog1.md` | Claude follow-up | Implementation notes + repair proposals. |
| `claudebullshit.md` | Claude (rejected/contested) | Operator-flagged output that drifted from canon — kept as cautionary example. |
| `gemmalog1.md` | Gemma session | Alt-model perspective; useful for diversity of critique. |
| `glm2.md` | GLM session | Joker round ancestry material. |
| `glmcrash.md` | GLM | Crash/error capture; informed stability fixes. |
| `glmcrossreport.md` | GLM | Cross-round report (compare to other rounds). |

## Companion handoff / brief files
- `FINAL_PUSH_HANDOFF.md` — last-mile handoff doc.
- `015-glm-redteam-remediation-TURNOVER.md` — turnover packet.
- `JARVIS_INTELLIGENCE_BRIEF.md` / `.pdf` / `.docx` / `.mp3` — rendered briefing.
- `JARVIS_INTELLIGENCE_REPORT.md`, `JARVIS_TRAINING_BRIEF.txt` — briefings.

## Reading order (recommended)
1. `claude1.md` — frame the problem space.
2. `glm2.md` → `GLM51_JOKER_FINDINGS.md` — red-team.
3. `DEEPSEEK_REPAIR_SPEC.md` — deep-logic cross-check.
4. `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` — the dedup + plan.
5. `FINAL_PUSH_HANDOFF.md` / `015-...TURNOVER.md` — where we are now.

## Caveat
These logs are **not** canon. Canon lives in `CANON/corpus/` and
`PRINCIPLES.md` / `SOUL_ANCHOR.md`. Logs record process; canon records
truth.

## See also
- [[history/AUDIT_ROUNDS]]
- [[history/REMEDIATION_TIMELINE]]
- [[codebase/modules/Canon]]
