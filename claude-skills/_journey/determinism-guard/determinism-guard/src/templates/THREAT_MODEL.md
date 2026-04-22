# Determinism Guard — Threat Model

Four threat surfaces specific to a static-analysis determinism auditor and the mitigations built into this kit.

---

## T1: False Positives Leading to Unnecessary Refactoring

**Threat:** The auditor flags patterns that are safe in context (e.g., `Date.now()` in a log statement, `Math.random()` in a UI confetti animation that does not affect state). A developer trusts the report and refactors working code, potentially introducing bugs in the process.

**Mitigation:** The audit skill requires reading 5-10 lines of surrounding context for every match before classifying it. Each finding must be triaged as TRUE POSITIVE, GUARDED, or FALSE POSITIVE. The report template includes a Deferred section that explicitly lists dismissed findings with reasons, so the developer sees what was checked and why it was cleared.

**Residual risk:** Low. An auditor that skips the triage step could over-report, but the skill procedure makes triage mandatory and the report format enforces classification of every finding.

---

## T2: Missed Patterns Creating False Confidence

**Threat:** The pattern catalog is incomplete. A developer runs the audit, receives a clean report, and assumes their code is deterministic. Meanwhile, a pattern not in the catalog (e.g., a third-party library's internal use of unseeded RNG, or a language-specific behavior not yet documented) goes undetected.

**Mitigation:** The catalog is explicitly versioned and scoped to 25+ patterns across five languages. The report template states which patterns were checked and includes a Scope Limitations section that declares what was NOT checked. The skill encourages tracing utility calls one level deep to catch transitive non-determinism. The report never claims "this code IS deterministic" — only that "no known non-deterministic patterns were found."

**Residual risk:** Medium. No static analysis tool can guarantee determinism. The kit is transparent about this limitation in both the skill procedure and the report template.

---

## T3: Pattern Catalog Drift from Language and Runtime Updates

**Threat:** Language runtimes change behavior across versions. Python dict ordering became guaranteed in 3.7. V8 sort stability became guaranteed in Node 10. A pattern flagged as "high severity" in an older runtime may be safe in a newer one, and a pattern considered safe today may become unsafe in a future version.

**Mitigation:** The pattern catalog notes version-dependent behavior where known (e.g., H2 documents Python 3.7 dict ordering change, H1 documents V8 sort stability change). The audit skill checks for language version indicators (package.json engines field, pyproject.toml python-requires, go.mod go directive) when available and adjusts severity accordingly.

**Residual risk:** Low. The most impactful version-dependent behaviors are documented. New runtime changes are addressed through catalog updates in new kit versions.

---

## T4: Fix Recommendations Introducing Bugs When Applied Without Context

**Threat:** The auditor suggests a safe alternative that is semantically different from the original code in a way that matters for the specific use case. A developer applies the suggestion mechanically without understanding the full context, introducing a regression.

**Mitigation:** The audit is explicitly read-only — the skill procedure forbids modifying code during the audit. Fix recommendations include both the replacement code and the reasoning for why it is safer, so the developer can evaluate applicability. The skill recommends reviewing each fix in context before applying. The report groups fixes by effort level (Quick Wins vs. detailed findings) to encourage thoughtful prioritization rather than bulk application.

**Residual risk:** Low. The read-only constraint prevents automated damage. Recommendations are advisory and include enough context for informed decision-making.
