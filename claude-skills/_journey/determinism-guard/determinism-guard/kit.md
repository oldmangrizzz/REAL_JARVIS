# Determinism Guard — Static Analysis for Reproducible Code

## Quick Start

Ask your agent:

```
Run a determinism audit on src/
```

No installation, no configuration, no dependencies. The skill scans your source
files using grep-based pattern matching and contextual code reading, then
produces a structured report.

Other trigger phrases:

- "Scan this project for non-deterministic patterns"
- "Check my simulation code for reproducibility issues"
- "Find sources of flaky test randomness"
- "Audit the game engine for unseeded RNG"

## Goal

Non-deterministic code is a silent killer. A single `Math.random()` call buried
in a utility function can corrupt a replay system, break hundreds of snapshot
tests, and invalidate weeks of simulation tuning. The bug is invisible until
someone asks "why does this save file differ between runs?" — and by then the
non-determinism is woven through the codebase.

This kit gives any AI coding agent a structured audit procedure that finds these
patterns before they cause damage. It detects 25+ non-deterministic anti-patterns
across JavaScript, TypeScript, Python, Go, and Rust, triages each finding to
minimize false positives, and produces a report with specific fix recommendations.

The audit is **read-only** — it never modifies code.

Built from production experience across two simulation games — Mr. Baseball
Dynasty (700+ tests, 16 development phases) and Mr. Football Dynasty (800+ tests,
25+ sprints) — both built entirely by AI agents. In these projects, determinism
is enforced on every commit. This kit extracts that discipline into a reusable,
language-aware audit.

## When to Use

- You are building a **game or simulation** and need deterministic replays, save
  files, or snapshot tests
- You are training **ML models** and need reproducible data pipelines, feature
  engineering, or preprocessing
- You have **flaky tests** that pass locally and fail in CI, and you suspect
  non-deterministic setup or assertions
- You are starting a new project and want to **establish determinism discipline**
  before non-deterministic patterns accumulate
- You are onboarding to an existing codebase and want to **audit** its
  determinism posture before making assumptions

Do NOT use this kit for:
- Codebases where non-determinism is intentional and desired (randomized UIs,
  A/B test assignment, cryptographic operations)
- Pure display/UI code with no state persistence

## Setup

No setup required. This kit is a pure skill with reference templates. It uses
only the agent's built-in file-reading and grep capabilities.

### Environment

- **Runtime:** Local filesystem only. No network access, no external services.
- **Platforms:** Any OS. Works wherever the agent can read source files.
- **Languages supported:** JavaScript, TypeScript, Python, Go, Rust.
- **Dependencies:** None. Zero packages to install.

### Models

Works with any tool-using LLM agent that can read files and run grep searches.
Designed for and tested with Claude (Opus, Sonnet).


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

The audit follows a five-phase procedure:

### 1. Scope

Determine the target: which directories, which languages, which severity
threshold. Defaults to the entire project source at all severity levels.

### 2. Scan

Run grep-based pattern detection across all source files, parallelized by
severity tier. The pattern catalog covers three tiers:

| Tier | Patterns | Examples |
|------|----------|---------|
| **Critical** | Unseeded RNG, wall-clock time, crypto RNG | `Math.random()`, `Date.now()`, `uuid.uuid4()` |
| **High** | Unstable sort, unordered iteration, hash randomization | `.sort()`, `for...in`, Go map range, `hash()` |
| **Medium** | Race conditions, timer deps, filesystem order, env vars, float comparison | `Promise.race()`, `setTimeout`, `fs.readdir()`, `process.env` |

### 3. Triage

For every match, read 5-10 lines of surrounding context. Classify each as:

- **TRUE POSITIVE** — Non-deterministic pattern in a deterministic-critical
  path, not mitigated. Needs a fix.
- **GUARDED** — Pattern exists but is properly wrapped (seeded RNG, injected
  clock, sorted collection). Noted, not flagged.
- **FALSE POSITIVE** — Pattern is in a non-critical path (logging, display,
  one-time setup). Dismissed with reason.

Triage is mandatory. The kit never reports raw grep matches.

### 4. Report

Generate a structured report using the REPORT.md template:

- Summary table with counts by severity and classification
- Verdict: PASS, WARN, or FAIL
- Quick Wins section for easy fixes
- Detailed findings with file, line, code context, and fix recommendation
- Deferred section listing guarded and false positive findings for transparency

### 5. Recommend

For each true positive, provide a specific fix using safe alternatives from the
PATTERN_CATALOG.md reference. Fixes are language-specific and use the project's
existing conventions where possible.

## What Ships

| File | Role | Purpose |
|------|------|---------|
| `SKILL.md` | Skill | The audit procedure — scope, scan, triage, report, recommend |
| `templates/PATTERN_CATALOG.md` | Reference | 25+ patterns with severity, detection approach, and safe alternatives |
| `templates/REPORT.md` | Template | Structured output format for audit findings |
| `templates/THREAT_MODEL.md` | Security | Kit-specific threat model covering four attack surfaces |

## Pattern Coverage

### Critical Severity (always breaks determinism)

- **C1: Unseeded RNG** — `Math.random()`, `random.randint()`, `rand.Intn()`,
  `rand::random()`. Safe alternative: seeded PRNG instance.
- **C2: Crypto RNG in logic** — `crypto.randomUUID()`, `uuid.uuid4()`,
  `os.urandom()`. Safe alternative: seeded PRNG for logic, crypto only for
  security.
- **C3: Wall-clock time** — `Date.now()`, `new Date()`, `datetime.now()`,
  `time.Now()`. Safe alternative: injected clock, tick counter, or deterministic
  ID generator.

### High Severity (breaks determinism in many contexts)

- **H1: Unstable sort** — `.sort()` without comparator or tiebreaker.
- **H2: Unordered iteration** — `for...in`, Set/Map iteration, Go map range,
  HashMap/HashSet.
- **H3: Python hash randomization** — `hash()` on strings, randomized per process.
- **H4: for...in enumeration** — Prototype chain traversal with unstable order.

### Medium Severity (context-dependent)

- **M1: Promise.race/any** — Non-deterministic winner driving state.
- **M2: Timer-dependent logic** — setTimeout/setInterval mutating state.
- **M3: Directory listing order** — fs.readdir/os.listdir unsorted.
- **M4: Environment dependencies** — process.env/os.environ in logic.
- **M5: Float comparison** — Direct equality on computed floats.

See `templates/PATTERN_CATALOG.md` for full detection details and safe
alternatives for each pattern.

## Constraints

- **Read-only.** The audit never modifies code. It reports findings only.
- **Precision over recall.** Every match is triaged in context. False positives
  are dismissed with reasons, not silently dropped.
- **Language-aware.** The audit accounts for version-dependent behavior (Python
  3.7 dict ordering, V8 sort stability, Go map randomization).
- **Source-only.** Third-party library internals (node_modules, site-packages)
  are not scanned. Transitive non-determinism through your own utilities is
  traced one level deep.
- **Scope-respecting.** The audit only scans paths the user specifies. No
  surprise expansion into unrelated directories.

## Limitations

- Static analysis detects known patterns. It cannot prove code IS deterministic.
- The pattern catalog covers five languages. Other languages need custom patterns.
- Third-party library internals are out of scope.
- Version-dependent behavior is documented where known but may not cover every
  runtime edge case.

## Safety Notes

This kit performs pure static analysis with no side effects:

- **No file writes.** The audit produces a report as conversation output. It
  never creates, modifies, or deletes files in the project.
- **No network access.** All analysis is local. No data leaves the machine.
- **No code execution.** The audit reads source files and runs grep searches.
  It does not execute, compile, or interpret the code being audited.
- **No external dependencies.** Zero packages, services, or APIs required.

### Shared-Environment Considerations

- The audit reads source files that may contain sensitive code. The report
  includes code snippets from findings. If the audit output is shared (e.g.,
  pasted into a PR or issue), review the snippets for sensitive content first.
- Fix recommendations are advisory. They should be reviewed in context before
  applying. The threat model (templates/THREAT_MODEL.md) documents the risk of
  mechanical fix application and the mitigation (read-only constraint plus
  contextual reasoning in each recommendation).

## Worked Example — simulation game audit

A game simulation uses a `simulateSeason()` function. An agent runs the audit
on `src/simulation/`:

1. **Scope:** `src/simulation/`, JS/TS, all severities.
2. **Scan finds 7 matches:**
   - `Math.random()` in `src/simulation/utils/dice.ts:14` — **C1 Critical**
   - `new Date()` in `src/simulation/engine.ts:203` — **C3 Critical**
   - `.sort()` in `src/simulation/standings.ts:47` — **H1 High**
   - `Math.random()` in `src/simulation/ui/confetti.ts:8` — **C1 Critical candidate**
   - `Date.now()` in `src/simulation/logger.ts:12` — **C3 Critical candidate**
   - `process.env.DEBUG` in `src/simulation/engine.ts:1` — **M4 Medium candidate**
   - `setTimeout` in `src/simulation/ui/animation.ts:22` — **M2 Medium candidate**
3. **Triage:**
   - `dice.ts:14` — TRUE POSITIVE. Called from game logic. No seeded wrapper.
   - `engine.ts:203` — TRUE POSITIVE. `new Date()` used for game event timestamps stored in save file.
   - `standings.ts:47` — TRUE POSITIVE. `.sort()` on team records without tiebreaker. Equal-record teams can reorder between runs.
   - `confetti.ts:8` — FALSE POSITIVE. UI-only visual effect, does not affect state.
   - `logger.ts:12` — FALSE POSITIVE. Pure logging, does not affect state.
   - `engine.ts:1` — GUARDED. Only controls debug logging verbosity, not sim behavior.
   - `animation.ts:22` — FALSE POSITIVE. UI animation timing, does not mutate game state.
4. **Verdict: FAIL.** Three critical/high true positives in simulation-critical paths.
5. **Quick wins:** `standings.ts:47` — add `.sort((a, b) => b.wins - a.wins || a.teamId.localeCompare(b.teamId))`. Takes 2 minutes.

The report lists all 7 findings. 3 true positives get fix recommendations. 4
dismissed findings go in the Deferred section with reasons. The developer fixes
the easy sort first, then plans the RNG and timestamp refactors.

## Threat Model

See `templates/THREAT_MODEL.md` for the full kit-specific threat model covering:

1. **T1: False positives leading to unnecessary refactoring** — mitigated by
   mandatory triage and classification of every finding
2. **T2: Missed patterns creating false confidence** — mitigated by explicit
   scope declarations and "no known patterns found" language (never "code is
   deterministic")
3. **T3: Catalog drift from runtime updates** — mitigated by version-aware
   documentation and catalog versioning
4. **T4: Fix recommendations applied without context** — mitigated by read-only
   constraint and contextual reasoning in each recommendation
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
