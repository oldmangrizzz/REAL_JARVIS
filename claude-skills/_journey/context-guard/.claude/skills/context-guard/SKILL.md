---
name: context-guard
description: "Persistent context protection for AI coding agents — safeguard files survive sessions, rate limits, and compaction."
---

# Context Guard

## Goal

Prevent data loss across AI coding agent sessions. When an agent session ends — whether by rate limit, crash, context compaction, or the user closing the terminal — everything the agent learned, decided, and was working on is preserved in external files. The next session recovers full context with a single command.

The core principle is LLM-agnostic: external state files survive context windows regardless of which model or agent framework you use. The reference implementation targets Claude Code, but the pattern applies to any AI coding agent that supports skills or commands.

## When to Use

- Any project where an AI coding agent works across multiple sessions
- Long-running projects where continuity matters — decisions, task history, and user feedback must persist
- Teams or individuals who hit rate limits, session timeouts, or context compaction regularly
- Projects where you need an audit trail of what was done, decided, and why

## Setup

### Option 1: One-Command Install

```bash
git clone https://github.com/atreiou/claude-context-guard.git
cd claude-context-guard
./install.sh /path/to/your/project
```

### Option 2: Manual Install

1. Copy the `.claude/` folder into your project root
2. Copy the `templates/` folder into your project root

### First Run

Open your agent in the project and type `/start`. On first run, it will:
1. Detect this is a new project (no safeguard files yet)
2. Ask for your project name and description
3. Create all safeguard files from the templates
4. Offer to run `/itemise` for numbered code addressing (optional)


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

Context Guard provides five commands:

1. **`/start`** — Type this at the start of every session. Reads all safeguard files, cross-references plans against the task registry, flags dropped tasks, checks git state, and summarises the project. One command, full recovery.

2. **`/save`** — Mid-session checkpoint. Updates all safeguard files with current progress. No git operations. Use during long sessions or before risky operations.

3. **`/audit`** — On-demand integrity check. Everything `/start` does plus: checks for stale tasks, verifies decisions, checks for unarchived plans, file integrity, and saves a timestamped report to `audits/`.

4. **`/end`** — Session save point. Updates all safeguard files, archives plans, commits and pushes all changes, verifies clean git state, and reports a summary. Optional but gives a guaranteed clean handoff.

5. **`/itemise`** — Applies hierarchical section numbers to code files so every block is referenceable by address (e.g. "check section 2.3.1"). Creates backups, verifies integrity, cleans up. Togglable per project.

### What Gets Created

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Auto-read every session. Project rules, protocols, and pointers to safeguard files |
| `SESSION_LOG.md` | Running history of every session — what happened, errors hit, next steps |
| `TASK_REGISTRY.md` | Every task ever created with status. Cross-referenced by /start and /audit |
| `DECISIONS.md` | Architectural decisions register — the "why" behind every choice |
| `COMMENTS.md` | User's verbatim comments logged as a safety net against context loss |
| `FEATURE_LIST.json` | Pass/fail feature tracker (JSON — harder for LLMs to accidentally overwrite) |
| `plans/` | Archived plans from every session |

### Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `pre-commit-check.sh` | PreToolUse (Bash) | Reminds agent to update safeguard files before git commits |
| `pre-compact-save.sh` | PreCompact | Backs up safeguard files before context compaction |
| `check-slash-commands.sh` | UserPromptSubmit | Enforces skill invocation for `/commands` |

## Constraints

- The reference implementation uses Claude Code's skill system and CLAUDE.md. To use with other agents, you need to map the 5 skills to your agent's command system and replace CLAUDE.md with your agent's instruction file.
- Safeguard files are local and gitignored by default — they contain project-specific session data, not shareable code.
- The `/itemise` command modifies code files (adds comment-based section numbers). It creates backups and verifies integrity, but review the changes before committing.
- Hooks use `$CLAUDE_PROJECT_DIR` which is Claude Code-specific. Other agents may need different environment variable references.

## Safety Notes

- Safeguard files (SESSION_LOG.md, TASK_REGISTRY.md, etc.) should be gitignored — they may contain session-specific details not appropriate for public repos.
- Never store credentials, API keys, or sensitive data in safeguard files.
- The pre-compact hook copies files to `compaction-backups/` — also gitignored and safe to delete periodically.
- The `/itemise` command always creates `.itemise-backup` files before modifying code and restores from backup on any verification failure.

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/lilu/context-guard/outcome
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
    "attemptId": "attempt_a4a0f1e8-7309-4d67-b600-5d4d93d443bf",
    "reportToken": "atr_2836fc4078216024b56a94ad76850927866dd015c0e66634"
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
    "owner": "lilu",
    "slug": "context-guard",
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
    "attemptId": "attempt_a4a0f1e8-7309-4d67-b600-5d4d93d443bf",
    "feedbackToken": "atr_2836fc4078216024b56a94ad76850927866dd015c0e66634"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/lilu/context-guard/learnings
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
  "attemptId": "attempt_a4a0f1e8-7309-4d67-b600-5d4d93d443bf",
  "feedbackToken": "atr_2836fc4078216024b56a94ad76850927866dd015c0e66634"
}
```

This feedback token expires at `2026-05-22T12:43:17.067Z`. Max submissions for this install: 1.
