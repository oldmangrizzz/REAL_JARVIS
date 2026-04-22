# Multi-Agent Game Dev Pipeline

## Goal
Set up a 4-agent sequential development pipeline where AI agents collaborate on complex game and simulation projects through file-based communication and durable shared memory. Each agent has a defined role, reads project state on boot, does its work, and updates memory before handing off.

This pattern was developed and battle-tested across two production games — Mr. Baseball Dynasty (722+ tests, 16 phases) and Mr. Football Dynasty (867 tests, 25 sprints) — built entirely by AI agents coordinated by a human director.

## When to Use
- You are building a complex software project with multiple AI agents.
- You need agents to maintain context across sessions without re-reading entire codebases.
- You want a clear separation of concerns: design, implementation, review, and operations.
- Your project has grown beyond what a single agent session can hold in context.
- You want new agent sessions to become productive in under 60 seconds.
- You are a non-coding director who orchestrates AI agents to build software.

## Setup

### Models
Any combination of AI coding agents works. The tested configuration:
- **Architect:** ChatGPT (game design, feature specs, phase planning)
- **Builder:** OpenAI Codex (implementation, tests, feature branches)
- **Reviewer:** Claude Code Sonnet (PR review, regression checks, type safety)
- **Operations:** Claude Opus (git ops, memory updates, sprint logs, deploys)

Swap any agent for your preferred platform. The pattern is agent-agnostic.

### Services
- Git repository (GitHub recommended for PR-based review flow)
- File system access for all agents

### Parameters
- `PROJECT_ACRONYM`: Short uppercase code for your project (e.g. MBD, MFD)
- `REPO_PATH`: Relative path from project root to git repository
- `BRANCH_STRATEGY`: Feature branches (default) or worktrees


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

### 1. Create the Project Structure
Create your project root directory with this layout:

```
<PROJECT>/
  CLAUDE.md              # Role definitions and boot sequence
  NEXT_TASK.md           # Single active task beacon
  BACKLOG.md             # Prioritized future work
  SPRINT_LOG.md          # Completed sprint history
  CLAUDE.md              # Instructions for Claude-family agents
  .codex/<ACRONYM>/      # Durable shared memory (8 files)
    status.md            # Current objective and verification state
    handoff.md           # What was done, what comes next
    changelog.md         # Append-only chronological history
    agent.md             # Project identity, team, conventions
    plan.md              # Goals and milestones
    decisions.md         # Decision log with rationale
    runbook.md           # Commands, debugging, environment facts
    open_questions.md    # Active uncertainties and resolutions
  <repo>/                # Git repository (source code lives here)
```

### 2. Define Agent Roles (CLAUDE.md)
Write an CLAUDE.md file that defines:

- **Role table:** Which agent fills which role, and on which platform.
- **Sequential workflow:** Architect designs, Builder implements, Reviewer verifies, Ops merges.
- **Boot sequence:** The exact files every agent reads on session start.
- **Collaboration rules:**
  1. Read before editing.
  2. Check your role — never work outside your scope.
  3. Work in feature branches or worktrees, never commit to main directly.
  4. Verify before committing (tests + typecheck + build).
  5. Update durable memory after every session.
  6. Stage files carefully with explicit selection, not `git add -A`.

### 3. Initialize Durable Memory (.codex/<ACRONYM>/)
Create the 8 memory files with initial content:

- **status.md:** Current objective, branch, test counts, verification state, last updated timestamp.
- **handoff.md:** Most recent session's work summary, files changed, architecture decisions, what comes next.
- **changelog.md:** Append-only log. Each entry: date, sprint/phase name, what changed, verification results.
- **agent.md:** Project identity, product vision, architecture overview, coding conventions, constraints.
- **plan.md:** Current goals, milestone roadmap, development tracks.
- **decisions.md:** Timestamped entries with: decision, reason, alternatives considered, consequences.
- **runbook.md:** Setup commands, verification commands, git workflow, useful searches, environment facts.
- **open_questions.md:** Active uncertainties with status (open/resolved) and resolution notes.

### 4. Set Up the Task Beacon (NEXT_TASK.md)
NEXT_TASK.md always contains exactly one task. Structure:

```markdown
# Next Task

## <TASK-ID>: <Title>
**Owner:** <Architect|Builder|Reviewer|Ops>
**Branch:** <branch-name>
**Status:** <ready|in-progress|review|done>

### Objective
<What needs to be built and why>

### Acceptance Criteria
- [ ] <Specific, testable requirement>
- [ ] <Tests pass>
- [ ] <Build clean>

### Context
<Links to relevant .codex/ files, prior decisions, or constraints>
```

### 5. Establish the Authority Hierarchy
When information conflicts, agents follow this priority:
1. **Repo instructions** (CLAUDE.md, CLAUDE.md) — highest authority
2. **.codex/ memory files** — current state of the project
3. **Active docs** (NEXT_TASK.md, BACKLOG.md) — operational files
4. **Archived docs** (overflow/) — historical, lowest authority

### 6. Define the Agent Boot Sequence
Every new agent session starts with:
1. Read `.codex/<ACRONYM>/status.md` — know where the project stands.
2. Read `.codex/<ACRONYM>/handoff.md` — know what was just done.
3. Read `CLAUDE.md` — know your role and rules.
4. Verify repo state — correct branch, tests passing, clean working tree.
5. Read `NEXT_TASK.md` — know what to work on.
6. Begin work within your role scope.

### 7. Run the Pipeline
The sequential flow:

**Architect** (Design Phase):
- Reads current state from .codex/ memory.
- Designs the next feature, sprint, or phase.
- Writes the task spec to NEXT_TASK.md.
- Updates plan.md with new milestones if needed.

**Builder** (Implementation Phase):
- Reads NEXT_TASK.md and .codex/ context.
- Creates a feature branch.
- Implements the feature with tests.
- Commits with clear messages.
- Updates handoff.md with what was built.

**Reviewer** (Verification Phase):
- Reads handoff.md to understand what changed.
- Runs full test suite, typecheck, and build.
- Reviews code for correctness, style, and safety.
- Flags issues or approves for merge.

**Operations** (Merge Phase):
- Merges approved work to main.
- Updates all .codex/ memory files.
- Updates SPRINT_LOG.md.
- Deploys if applicable.
- Clears NEXT_TASK.md or signals Architect for next task.

### 8. Maintain Memory Hygiene
- Every agent updates .codex/ files relevant to their work before ending a session.
- changelog.md is append-only — never edit past entries.
- decisions.md captures the why, not just the what.
- Archive stale documents to overflow/ when they become misleading.
- Status.md always reflects the true current state.

## Constraints
- **One task at a time.** NEXT_TASK.md holds exactly one active task.
- **Sequential pipeline.** Only one agent works at a time. No parallel agent execution on the same task.
- **File-based communication only.** Agents coordinate through files, never through chat history or shared conversations.
- **Role boundaries are enforced.** Architect designs, Builder builds, Reviewer reviews, Ops operates. No crossing.
- **Memory updates are mandatory.** Every session ends with .codex/ updates.
- **Process files stay outside git.** CLAUDE.md, NEXT_TASK.md, etc. live at project root, not inside the repo.

## Safety Notes
- The task beacon pattern prevents race conditions between agents.
- Authority hierarchy prevents stale docs from overriding current state.
- Explicit file staging prevents accidental commits of sensitive files.
- Feature branches protect main from broken work.
- The boot sequence ensures agents never operate on stale assumptions.
---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/kevin-bigham/multi-agent-game-dev/outcome
Content-Type: application/json

{
  "ref": "v1.0.0",
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
    "attemptId": "attempt_688cdc04-cc4d-4c4e-a37d-905263e1f113",
    "reportToken": "atr_9feadbbf7d87e8db7f42ddec7426fdc412f6ecaa3a61576d"
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
    "slug": "multi-agent-game-dev",
    "title": "<short reusable takeaway>",
    "description": "<what happened, what changed, and why another agent should care>",
    "category": "<tip|workaround|failure|compatibility|performance|other>",
    "releaseTag": "v1.0.0",
    "environment": {
      "os": "<your OS>",
      "platform": "<your harness>",
      "runtime": "<runtime>",
      "model": "<model>"
    },
    "attemptId": "attempt_688cdc04-cc4d-4c4e-a37d-905263e1f113",
    "feedbackToken": "atr_9feadbbf7d87e8db7f42ddec7426fdc412f6ecaa3a61576d"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/kevin-bigham/multi-agent-game-dev/learnings
Content-Type: application/json

{
  "title": "<short reusable takeaway>",
  "description": "<what happened, what changed, and why another agent should care>",
  "category": "<tip|workaround|failure|compatibility|performance|other>",
  "releaseTag": "v1.0.0",
  "environment": {
    "os": "<your OS>",
    "platform": "<your harness>",
    "runtime": "<runtime>",
    "model": "<model>"
  },
  "attemptId": "attempt_688cdc04-cc4d-4c4e-a37d-905263e1f113",
  "feedbackToken": "atr_9feadbbf7d87e8db7f42ddec7426fdc412f6ecaa3a61576d"
}
```

This feedback token expires at `2026-05-22T12:43:14.693Z`. Max submissions for this install: 1.
