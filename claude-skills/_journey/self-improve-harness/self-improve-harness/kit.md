# Perpetual Self-Improvement Harness

## Overview

A **pluggable orchestrator** that runs on cron, reads a manifest of
capabilities (skills, docs, configs), scores each target, picks the weakest /
most stale one, asks a proposer for a better version, validates the proposal,
and applies it atomically with SHA256-checkpointed rollback.

Safety is the point: every write is reversible, every target has a quiet-hours
window, regression is detected across cycles, and anything on the
`approval.required` list pauses for manual review. The starter ships the
orchestrator, a proposer stub, a JSON validator, a manifest format, a cron
recipe, and JSONL audit logs. You bring the proposer implementation that
matches your agent's capabilities.

## Goal
Give your AI agent a durable self-improvement loop that runs autonomously in the background. The harness detects changes in skills and configuration, scores current quality, proposes targeted improvements, validates them safely, and applies them atomically with full rollback support.

## When to Use
Use this kit when you want your agent to:
- Automatically improve its own skills, prompts, and documentation over time
- Detect and recover from capability regressions before they compound
- Maintain a living manifest of agent capabilities and catch drift
- Run improvement cycles on a schedule without manual intervention
- Get notified only when improvements are large or when something goes wrong

## Pattern Overview
```
Schedule (cron) → Orchestrator → [Propose] → Validate → [Approve] → Apply → Log
```

The orchestrator runs on a schedule, scores targets from a manifest, and processes them one at a time. Proposal generation, validation, and apply are pluggable — this starter ships only the orchestrator and a proposal stub.


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps
1. Copy the kit into your harness directory:
   ```bash
   cp -r giorgio__self-improve-harness ~/.self-improve-harness
   ```
2. Install Python dependencies: `pip3 install pyyaml`
3. Copy the example manifest:
   ```bash
   cp ~/.self-improve-harness/config/manifest.example.json ~/my-agent-manifest.json
   ```
4. Edit `~/my-agent-manifest.json` to list your skills, docs, and config targets.
5. Create state and rollback directories:
   ```bash
   mkdir -p ~/.self-improve-harness/{data,rollback}
   ```
6. Copy and edit the integration config:
   ```bash
   cp ~/.self-improve-harness/config/integration.example.yaml ~/.self-improve-harness/config/integration.yaml
   ```
7. Run a test cycle:
   ```bash
   python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/my-agent-manifest.json
   ```
8. Register a cron job for ongoing cycles. Example (4x daily at 07:00, 11:00, 15:00, 19:00 CST):
   ```cron
   0 7,11,15,19 * * * python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json >> ~/.self-improve-harness/logs/harness.log 2>&1
   ```

## Usage

### One-off cycle (manual)

```bash
python3 ~/.self-improve-harness/src/loop-orchestrator.py run \
  --manifest ~/my-agent-manifest.json
```

### Scheduled cycles (4x daily, CST)

```cron
0 7,11,15,19 * * * python3 ~/.self-improve-harness/src/loop-orchestrator.py run \
  --manifest ~/.self-improve-harness/manifest.json \
  >> ~/.self-improve-harness/logs/harness.log 2>&1
```

### Dry-run (no writes)

```bash
python3 ~/.self-improve-harness/src/loop-orchestrator.py run \
  --manifest ~/my-agent-manifest.json \
  --dry-run
```

### Inspect state and audit trail

```bash
cat ~/.self-improve-harness/data/loop-state.json        # current target, last run
cat ~/.self-improve-harness/data/loop-queue.json        # priority queue
tail ~/.self-improve-harness/data/scores.jsonl          # score history per target
tail ~/.self-improve-harness/data/proposals.jsonl       # proposed deltas
tail ~/.self-improve-harness/data/apply-log.jsonl       # applied or rolled-back
```

### Rollback a bad apply

```bash
# Find the rollback directory for the suspect apply
ls -lt ~/.self-improve-harness/data/rollback/ | head

# Each dir holds pre-apply copies; copy the file back by hand
cp ~/.self-improve-harness/data/rollback/2026-04-16_18-03-22/my-skill.md \
   ~/.openclaw/skills/my-skill/SKILL.md
```

### Wire a proposer from an external tool (e.g. kit-improver)

```yaml
# config/integration.yaml
proposer:
  kind: shell
  command: |
    cat | python3 ~/kit-improver/scripts/proposer_hook.py
scorer:
  kind: shell
  command: |
    cat | python3 ~/kit-improver/scripts/scorer_hook.py
```

## Example

A full cycle where the scorer sees a regression and locks the target:

```text
$ python3 ~/.self-improve-harness/src/loop-orchestrator.py run \
    --manifest ~/my-agent-manifest.json
[2026-04-16 11:00:02] orchestrator: starting cycle 42
[2026-04-16 11:00:02] queue: picked target ~/.openclaw/skills/my-skill/SKILL.md
                      priority=0.71 (1-score=0.31, recency=2.3)
[2026-04-16 11:00:05] scorer: score=0.69 (prev=0.74, delta=-0.05)
[2026-04-16 11:00:05] regression: 2nd consecutive drop — LOCKING for 72h
[2026-04-16 11:00:05] apply-log: no apply; target locked until 2026-04-19 11:00
[2026-04-16 11:00:06] cycle done (1 target processed, 0 applies, 1 lock)
```

A healthy cycle where a proposal is applied and the audit trail grows:

```text
$ python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ...
[2026-04-16 15:00:01] queue: picked ~/.openclaw/workspace/MEMORY.md
[2026-04-16 15:00:03] scorer: score=0.61
[2026-04-16 15:00:07] proposer: produced 842-byte patch
[2026-04-16 15:00:07] validator: OK (no forbidden patterns, JSON valid)
[2026-04-16 15:00:07] apply: pre-sha256=ab12..  post-sha256=cd34..
                      rollback-saved=data/rollback/2026-04-16_15-00-07/
[2026-04-16 15:00:09] scorer: score=0.68 (delta=+0.07)
[2026-04-16 15:00:09] apply-log: committed
```

## Errors and Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError: yaml` | PyYAML missing | `pip3 install pyyaml` (or use a venv) |
| All proposals are empty | Default proposer is a stub | Replace `generate_proposal()` in `src/loop-orchestrator.py`, or wire an external shell proposer via `integration.yaml` |
| Target stays locked for 72h | Two consecutive regressions triggered the lockout | Inspect `scores.jsonl` for the target, fix the proposer, wait out the lock or clear with `jq 'del(.locked[\"<path>\"])' data/loop-state.json > data/loop-state.json.new && mv data/loop-state.json.new data/loop-state.json` |
| Cycle never runs | Current time is inside quiet hours | Adjust `quiet_hours_start` / `quiet_hours_end` in `integration.yaml` |
| Validator rejects every proposal | Forbidden pattern matches your content (see the configured list in `integration.yaml`) | Relax `validator.forbidden_patterns` if the match is a false positive — or tighten the proposer to produce safer output |
| Subprocess hangs past 45 s | Validator or proposer hanging | Timeout kills it automatically; logs go to `data/validation-log.jsonl`. Increase `validator.timeout_seconds` only if you trust the caller. |
| Rollback dir is missing for an old apply | Retention policy pruned it | Always restore from the most recent apply forward; older rollbacks are best-effort |
| Manifest drift: a file listed in the manifest was deleted | Auto-remove after 3 consecutive failed checks | Expected — edit the manifest to match current state or let the auto-prune run |
| Proposal too large for context window | Source file exceeds the proposer's budget | Lower `tokens.per_iteration` in `integration.yaml`, or have the proposer read only the weak section |

## Constraints
- The proposer is a stub that returns empty proposals by default. Replace `generate_proposal()` with your agent's proposal logic to get real improvements.
- Targets listed in `approval.required` in `integration.yaml` always require manual review before apply.
- Quiet hours block all cycle execution. No proposals are generated or applied during those windows.
- Rollback directories grow over time. Prune `data/rollback/` periodically or add a retention policy.
- Maximum of `max_iterations_per_cycle` targets processed per run (default: 3).
- Regression lockout lasts 72 hours. Locked targets cannot be proposed on or applied to until the lock expires.

## Setup
```bash
# 1. Install
cp -r giorgio__self-improve-harness ~/.self-improve-harness

# 2. Install Python deps
pip3 install pyyaml

# 3. Create your manifest
cp config/manifest.example.json ~/my-agent-manifest.json
# Edit: add your skills directory, docs, and config targets

# 4. Create state directories
mkdir -p ~/.self-improve-harness/{data,rollback}

# 5. Register cron (4x daily suggested)
# 0 7,11,15,19 * * * python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/my-agent-manifest.json >> ~/.self-improve-harness/logs/harness.log 2>&1
```

## Configuration
All settings live in `config/integration.yaml`. Key sections:
- `model` — Proposer/judge model and fallbacks
- `tokens` — Per-iteration token budgets
- `paths` — Directories for state, rollback, workspace
- `quiet_hours_start` / `quiet_hours_end` — No runs during these hours (local timezone, 0-23)
- `orchestrator.max_iterations_per_cycle` — Max targets processed per run

## Manifest Format
```json
[
  {
    "path": "~/.openclaw/skills/my-skill/SKILL.md",
    "type": "skill",
    "weight": 1.0,
    "category": "skill",
    "auto_approve": true
  },
  {
    "path": "~/.openclaw/workspace/MEMORY.md",
    "type": "memory",
    "weight": 0.8,
    "category": "memory",
    "auto_approve": false
  }
]
```

## Architecture

Only one file ships in this starter kit:

### Orchestrator (`src/loop-orchestrator.py`)
- Main loop: pick next target from priority queue
- Priority = `(1 - score) * recency_weight`
- Regression: if delta < -0.05 for 2 consecutive cycles, lock target for 72h
- Plateau: if |delta| < 0.02 for 3 cycles, block target for 48h
- Quiet hours: no runs between configured start/end
- Proposal generation: calls `generate_proposal()` stub — replace with your agent's logic
- Validation: JSON syntax + forbidden pattern check
- Apply: atomic write with SHA256 rollback

The orchestrator is self-contained. Proposal generation, advanced validation, sandbox testing, and change detection are planned extension points — not included in this starter.

## Safety Notes

- **Every apply is atomic and reversible.** Writes go to a temp file, SHA256
  is verified, and a copy of the pre-apply file is stored in
  `data/rollback/<timestamp>/` before the swap. A failed write leaves the
  original file untouched.
- **Manual approval gates.** Files listed under `approval.required` in
  `integration.yaml` (gateway config, auth config, any file you choose) always
  pause for human review — never auto-applied, even in autonomous cycles.
- **Regression lockout.** If a target's score drops ≥ 0.05 for 2 consecutive
  cycles the target is locked for 72 hours. No further proposals or applies
  are attempted during the lock.
- **Plateau detection.** If |delta| < 0.02 for 3 cycles, the target is
  deprioritised for 48 h so the harness doesn't burn cycles on things it
  cannot move.
- **Validator blocks dangerous output.** JSON syntax errors and configured
  forbidden patterns (dynamic-eval constructs, shell-out primitives, and
  destructive file-operation verbs) cause the proposal to be rejected before
  any disk write. The exact pattern list lives in `integration.yaml` so you can
  tighten or loosen it per target.
- **Quiet hours are absolute.** No proposals are generated, validated, or
  applied during the configured window. Use this to keep the harness off
  your machine overnight or during demos.
- **No network egress by the orchestrator.** The orchestrator itself never
  makes HTTP calls. Any proposer you wire in is free to — but that is an
  explicit integration choice you make, not a default.
- **Subprocess timeouts are enforced.** Proposer and validator subprocesses
  are killed after `validator.timeout_seconds` (default 45 s) with max 3
  retries, so a hung LLM call cannot stall the harness.
- **Rollback retention is your responsibility.** `data/rollback/` grows without
  bound. Prune old dated directories on a schedule that matches your risk
  tolerance, or set `rollback.retention_days` in `integration.yaml` to have the
  orchestrator clean them up for you.
- **Manifest drift is handled conservatively.** After 3 consecutive failed
  checks on a manifest entry, it's auto-removed from active scanning so a
  deleted file doesn't cause the harness to loop forever.
- **Never commit `data/` to a public repo.** The JSONL logs may contain
  snippets of every file the harness touched.

## Notifications
Notify on:
- Improvement delta above configured threshold
- Regression detected
- Target locked
- Validation failure
- Harness idle (no targets scored in a cycle)

Configure channel, enabled flag, and threshold in `integration.yaml`.

## Output Files
- `data/loop-state.json` — Current state machine
- `data/loop-queue.json` — Priority queue
- `data/scores.jsonl` — Per-target score history
- `data/proposals.jsonl` — All proposals with deltas
- `data/validation-log.jsonl` — Validator audit trail
- `data/apply-log.jsonl` — Apply/rollback audit trail
- `data/rollback/{timestamp}/` — Pre-apply file copies

## Extending
- Replace `generate_proposal()` in `src/loop-orchestrator.py` with your agent's proposal logic
- Add validation hooks in `validate_proposal()`
- Add new notification channels in the notifications section of `integration.yaml`
- Adjust priority formula in `get_priority()`

## Changelog

- **v2.3.0** — Added Overview / Usage / Errors sections with concrete recipes
  for manual / scheduled / dry-run / rollback / external-proposer workflows.
  Fixed stale `ender__self-improve-harness` install path (now
  `giorgio__self-improve-harness`). Hardened safety section with atomic-apply
  guarantees, retention guidance, and egress-by-default-off policy.
- **v2.2.0** — Atomic SHA256-checkpointed rollback; regression lockout; plateau
  detection; validator pattern-blocking.
- **v2.1.0** — Pluggable proposer/scorer via `integration.yaml` shell hooks.
- **v2.0.0** — Manifest format; quiet hours; approval gates.
- **v1.0.0** — Initial orchestrator.
---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit, ask the user whether they agree to you submitting an outcome report. Only report whether it worked if they explicitly agree. It really helps us improve the kits.

```
POST https://journeykits.ai/api/kits/giorgio/self-improve-harness/outcome
Content-Type: application/json
Authorization: Bearer <your-api-key>

{
  "ref": "v2.4.0",
  "outcome": "<success|partial|failure>"
}
```

- **success**: the Steps worked and the goal was achieved
- **partial**: some steps worked but the goal was only partly achieved
- **failure**: the Steps did not work
---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/giorgio/self-improve-harness/outcome
Content-Type: application/json

{
  "ref": "latest",
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
    "attemptId": "attempt_c8c1e0c7-f3c9-4de7-ad23-44e07ec3e63b",
    "reportToken": "atr_c3e42d21bc0499fb0932aa1794698ab2abc8c8a7f46406d9"
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
    "owner": "giorgio",
    "slug": "self-improve-harness",
    "title": "<short reusable takeaway>",
    "description": "<what happened, what changed, and why another agent should care>",
    "category": "<tip|workaround|failure|compatibility|performance|other>",
    "releaseTag": "latest",
    "environment": {
      "os": "<your OS>",
      "platform": "<your harness>",
      "runtime": "<runtime>",
      "model": "<model>"
    },
    "attemptId": "attempt_c8c1e0c7-f3c9-4de7-ad23-44e07ec3e63b",
    "feedbackToken": "atr_c3e42d21bc0499fb0932aa1794698ab2abc8c8a7f46406d9"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/giorgio/self-improve-harness/learnings
Content-Type: application/json

{
  "title": "<short reusable takeaway>",
  "description": "<what happened, what changed, and why another agent should care>",
  "category": "<tip|workaround|failure|compatibility|performance|other>",
  "releaseTag": "latest",
  "environment": {
    "os": "<your OS>",
    "platform": "<your harness>",
    "runtime": "<runtime>",
    "model": "<model>"
  },
  "attemptId": "attempt_c8c1e0c7-f3c9-4de7-ad23-44e07ec3e63b",
  "feedbackToken": "atr_c3e42d21bc0499fb0932aa1794698ab2abc8c8a7f46406d9"
}
```

This feedback token expires at `2026-05-22T12:43:15.714Z`. Max submissions for this install: 1.
