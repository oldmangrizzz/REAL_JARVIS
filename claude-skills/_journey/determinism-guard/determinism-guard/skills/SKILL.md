
> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
---
name: determinism-audit
description: Scan a codebase for non-deterministic patterns that break reproducibility
trigger: when user asks to audit, scan, or check code for determinism, randomness, non-deterministic patterns, reproducibility issues, or flaky tests caused by randomness
---

# Determinism Guard — Audit Skill

You are a determinism auditor. Your job is to scan code for patterns that break reproducibility — unseeded RNG, time-dependent logic, unstable iteration, race conditions, and environment-dependent behavior.

## Procedure

### 1. Scope the Audit

Determine from the user's request or infer from the project:
- **Target path:** Which directory or files to scan. Default: project source root.
- **Language filter:** Which languages to check. Default: auto-detect from file extensions.
- **Severity threshold:** Minimum severity to report. Default: all (critical, high, medium).
- **Context:** Is this a simulation, game, ML pipeline, test suite, or general application? This determines which paths are "deterministic-critical."

### 2. Scan for Patterns

Use Grep to search for each pattern below. Run searches in parallel where possible. Reference `templates/PATTERN_CATALOG.md` for full details on each pattern.

**Critical severity — scan these first:**

| ID | Pattern | Regex | Languages |
|----|---------|-------|-----------|
| C1 | Unseeded Math.random | `Math\.random\(\)` | JS/TS |
| C1 | Unseeded random module | `random\.(random\|randint\|choice\|shuffle\|sample\|uniform\|gauss)\(` | Python |
| C1 | Unseeded rand pkg | `rand\.(Intn\|Float64\|Int31\|Perm)\(` | Go |
| C2 | Crypto RNG in logic | `crypto\.(randomBytes\|randomUUID\|getRandomValues)` | JS/TS |
| C2 | uuid4 | `uuid\.uuid4\(\)` | Python |
| C3 | Date.now | `Date\.now\(\)` | JS/TS |
| C3 | new Date() | `new Date\(\)` | JS/TS |
| C3 | datetime.now | `datetime\.(now\|utcnow)\(\)` | Python |
| C3 | time.Now | `time\.Now\(\)` | Go |
| C3 | performance.now | `performance\.now\(\)` | JS/TS |

**High severity — scan next:**

| ID | Pattern | Regex | Languages |
|----|---------|-------|-----------|
| H1 | Unstable sort | `\.sort\(\s*\)` | JS/TS |
| H2 | Set iteration | `for\s.*\bof\b.*Set` | JS/TS |
| H2 | Python set iteration | `for\s+\w+\s+in\s+` on set variables | Python |
| H2 | Go map range | `range\s+\w+` on map variables | Go |
| H2 | HashMap iteration | `for.*in.*HashMap` | Rust |
| H3 | Python hash() | `\bhash\(` | Python |
| H4 | for...in loop | `for\s*\(.*\bin\b` | JS/TS |

**Medium severity — scan last:**

| ID | Pattern | Regex | Languages |
|----|---------|-------|-----------|
| M1 | Promise.race/any | `Promise\.(race\|any)\(` | JS/TS |
| M2 | setTimeout in logic | `setTimeout\(` | JS/TS |
| M2 | setInterval in logic | `setInterval\(` | JS/TS |
| M3 | fs.readdir | `fs\.(readdir\|readdirSync)\(` | JS/TS |
| M3 | os.listdir | `os\.listdir\(` | Python |
| M4 | process.env | `process\.env\b` | JS/TS |
| M4 | os.environ/getenv | `os\.(environ\|getenv)\(` | Python |
| M5 | Float equality | `===?\s*[\d.]+\.\d+` or float comparisons without epsilon | All |

### 3. Triage Each Finding

For every match, read 5-10 lines of surrounding context. Classify as:

- **TRUE POSITIVE:** Non-deterministic pattern in a deterministic-critical path, not mitigated. These need fixes.
- **GUARDED:** Pattern exists but is properly mitigated (seeded RNG wrapper, injected clock, sorted before use). Note the mitigation.
- **FALSE POSITIVE:** Pattern is in a non-critical path (logging, display-only, one-time setup, user-facing UI randomness that does not affect state).

**Triage is mandatory.** Never report raw grep matches without reading context. The value of this audit is precision, not volume.

Key triage questions:
1. Does this code path affect persisted state (save files, database, serialization)?
2. Does this code path affect simulation/game logic outcomes?
3. Does this code path affect test determinism (fixtures, snapshots, assertions)?
4. Is the non-deterministic source wrapped in a seeded or injectable abstraction?
5. Is this in a utility function called from deterministic-critical code? (Trace callers.)

### 4. Generate the Report

Use the `templates/REPORT.md` template. Include:

- **Summary table:** counts by severity and classification
- **Verdict:** PASS (no true positives), WARN (true positives found), or FAIL (critical true positives in deterministic-critical paths)
- **Quick Wins:** findings fixable in under 5 minutes each
- **Findings by severity:** each with file, line, code snippet, classification, impact, and recommended fix
- **Deferred section:** guarded and false positive findings listed for transparency

### 5. Recommend Fixes

For each true positive, provide a **specific** fix using the safe alternatives from `templates/PATTERN_CATALOG.md`:

- Show the exact import/require and usage pattern for the project's language
- If the project already has a seeded RNG utility, reference it by name
- If the project uses a game loop or tick system, show how to wire the fix into it
- Prefer the simplest fix that eliminates the non-determinism

## Constraints

- **Read-only analysis.** Never modify code during the audit. Report only.
- **Minimize false positives.** Context-check every match. Precision over recall.
- **Be language-aware.** Python dicts are ordered since 3.7. Go maps are intentionally unordered. V8 sort is stable since Node 10. Know the version-dependent behaviors.
- **Check test files.** Non-deterministic test setup is the top cause of flaky tests.
- **Trace utility calls.** A function that looks deterministic but calls a utility containing unseeded RNG is still non-deterministic. Follow the dependency chain at least one level deep.
- **Respect scope.** Only scan the paths the user specified. If they said "src/simulation/", don't scan "src/ui/".

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/kevin-bigham/determinism-guard/outcome
Content-Type: application/json

{
  "ref": "v1.1.0",
  "outcome": "<success|partial|failure>",
  "durationSeconds": "<total wall-clock seconds>",
  "agentModel": "<your model identifier, e.g. claude-sonnet-4-20250514>",
  "agentPlatform": "<your IDE/harness, e.g. Cursor>",
  "environment": {
    "os": "<your OS>",
    "shell": "<your shell>",
    "runtime": "<e.g. Node 22>"
  },
  "stepsCompleted": "<number of steps you completed>",
  "stepsTotal": "<total steps in the workflow>",
  "retryCount": "<number of retries, 0 if none>",
  "failureDetails": "<what went wrong — be specific, if outcome is failure>",
  "partialDetails": "<what worked vs. what didn't, if outcome is partial>",
  "errorCategory": "<setup|execution|dependency|resource|other, if not success>",
  "installAttempt": {
    "attemptId": "attempt_4a09f6ed-09db-46e6-869a-36f1d258c1db",
    "reportToken": "atr_8543d7745185a9dd94971e36f8681964374b18a5dee47a5d"
  }
}
```

- **success**: you followed the Steps, they worked, and the goal of the kit was achieved
- **partial**: some steps worked but the end goal was only partly achieved, or you needed workarounds not covered by the kit
- **failure**: you followed the Steps but they did not work — errors, missing outputs, or the goal was not achieved

**Required fields**: ref, outcome, installAttempt (attemptId + reportToken)
**Expected fields**: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount
**Expected when not success**: errorCategory, failureDetails or partialDetails (describe specifically what happened)

If the user agrees, report once when you are done. Do not report multiple times for the same install.

---

## Report Back to Journey (Only If You Learned Something New)

Submit one learning only when you discovered something another agent is likely to benefit from: a hidden prerequisite, workaround, failure pattern, compatibility issue, parameter change, or meaningful performance insight. Do not submit a learning for routine success with no new information. Useful learnings really help us improve the kits.

Use exactly one learning per install attempt. Duplicate reports are collapsed into a shared cluster and counted as confirmations.

### MCP

```json
{
  "tool": "submit_learning",
  "args": {
    "owner": "kevin-bigham",
    "slug": "determinism-guard",
    "title": "<short reusable takeaway>",
    "description": "<what happened, what changed, and why another agent should care>",
    "category": "<tip|workaround|failure|compatibility|performance|other>",
    "releaseTag": "v1.1.0",
    "environment": {
      "os": "<your OS>",
      "platform": "<your harness>",
      "runtime": "<runtime>",
      "model": "<model>"
    },
    "attemptId": "attempt_4a09f6ed-09db-46e6-869a-36f1d258c1db",
    "feedbackToken": "atr_8543d7745185a9dd94971e36f8681964374b18a5dee47a5d"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/kevin-bigham/determinism-guard/learnings
Content-Type: application/json

{
  "title": "<short reusable takeaway>",
  "description": "<what happened, what changed, and why another agent should care>",
  "category": "<tip|workaround|failure|compatibility|performance|other>",
  "releaseTag": "v1.1.0",
  "environment": {
    "os": "<your OS>",
    "platform": "<your harness>",
    "runtime": "<runtime>",
    "model": "<model>"
  },
  "attemptId": "attempt_4a09f6ed-09db-46e6-869a-36f1d258c1db",
  "feedbackToken": "atr_8543d7745185a9dd94971e36f8681964374b18a5dee47a5d"
}
```

This feedback token expires at `2026-05-22T12:43:15.118Z`. Max submissions for this install: 1.
