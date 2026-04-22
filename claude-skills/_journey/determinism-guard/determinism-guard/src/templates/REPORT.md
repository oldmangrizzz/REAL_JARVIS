# Determinism Audit Report

**Project:** [project name]
**Audit date:** [date]
**Scope:** [directories and files scanned]
**Languages detected:** [languages found]
**Severity threshold:** [critical | high | medium]
**Patterns checked:** [count] patterns from Determinism Guard pattern catalog

---

## Summary

| Severity | True Positives | Guarded | False Positives |
|----------|---------------|---------|-----------------|
| Critical | 0 | 0 | 0 |
| High     | 0 | 0 | 0 |
| Medium   | 0 | 0 | 0 |
| **Total** | **0** | **0** | **0** |

**Verdict:** [PASS | WARN | FAIL]

- **PASS** — No true positives found. No known non-deterministic patterns detected in scanned paths.
- **WARN** — True positives found but none in critical-severity category. Review recommended.
- **FAIL** — Critical true positives found in deterministic-critical paths. Fixes required before shipping.

---

## Quick Wins

_Findings fixable in under 5 minutes each, ordered by impact._

1. **[file:line]** — [pattern ID + name] — [one-line fix description]

---

## Findings by Severity

### Critical

#### [Pattern ID]: [Pattern Name]

**Location:** `[file]:[line]`

**Code context:**
```
[5-10 lines of surrounding code with the flagged line marked]
```

**Classification:** TRUE POSITIVE
**Impact:** [specific impact — what breaks if this stays: save files, replays, snapshots, test stability]
**Recommended fix:**
```
[specific code showing the safe alternative, using the project's language and conventions]
```

---

### High

_(same structure as Critical findings)_

---

### Medium

_(same structure as Critical findings)_

---

## Deferred (Guarded and False Positives)

_Patterns detected but not flagged as issues. Listed so you know what was checked._

| Location | Pattern | Classification | Reason |
|----------|---------|---------------|--------|
| `file:line` | [pattern name] | GUARDED | [mitigation: e.g., "wrapped in seeded RNG utility at line N"] |
| `file:line` | [pattern name] | FALSE POSITIVE | [reason: e.g., "only used for log timestamps, does not affect state"] |

---

## Recommendations

1. **[Top priority recommendation]** — [why and what to do]
2. **[Second recommendation]** — [why and what to do]
3. **[Third recommendation]** — [why and what to do]

---

## Scope Limitations

- This audit checked for [count] known non-deterministic patterns. Patterns not in the catalog were not checked.
- Third-party library internals were not scanned — only source files in the scanned directories.
- This audit does not prove determinism. It identifies known sources of non-determinism. A clean report means no known patterns were found, not that the code is guaranteed deterministic.
