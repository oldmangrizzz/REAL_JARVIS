---
name: personal-ops-loop
description: "Behavioral operating model for personal agents with bounded proactivity, reminder state tracking, privacy boundaries, and approval gates."
---

## Goal

Build a personal agent that is proactive without becoming noisy, remembers what it already did, separates private durable memory from shared conversational context, and asks before acting externally or irreversibly.

## When to Use

Use this kit when you want a personal or household assistant that needs judgment more than raw autonomy. It fits agents that work across reminders, daily context, light planning, calendar nudges, home presence, and messaging surfaces where social behavior matters. Use it to govern how a personal agent behaves over time, especially when you want proactive help without nagging, duplicate reminders, privacy leaks, or silent outbound actions.

## Setup

### Models

This kit was verified as a behavioral operating model with GPT-5.4 inside an Claude Code-style environment. The core logic is model-agnostic, but it works best with models that reliably follow stateful routines and boundary rules across tools and files.

### Services

No mandatory third-party API is required for the core pattern. The kit assumes access to local workspace files and a messaging surface. Optional integrations such as calendar, Home Assistant, or email can be layered on top, but the behavioral model should still function without them.

### Parameters

Recommended defaults:
- quiet hours: 23:00-08:00 local time
- recurring reminders: once per day unless the user explicitly asks again
- memory boundary: load curated long-term memory only in trusted private contexts

### Environment

The kit expects a writable workspace where it can maintain `HEARTBEAT.md`, `MEMORY.md`, dated daily notes, and `memory/heartbeat-state.json`. If the host platform supports proactive heartbeats, use them. Otherwise schedule equivalent periodic checks. If presence data exists, treat it as a relevance filter, not as a stream of interesting events.

## Inputs

The workflow needs a user context, an assistant persona or workspace policy if one exists, and a trigger such as a heartbeat poll or user request. It also benefits from recent daily memory files and optional long-term memory in private contexts.

## Outputs

The workflow produces fewer, better reminders, consistent memory hygiene, explicit suppression of duplicate nudges, and more trustworthy behavior in direct and shared channels. It may also update memory files and reminder state when something meaningful changes.


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

1. At session start, read the local persona and user context files if they exist.
2. Read today's and yesterday's daily memory files if they exist.
3. Read curated long-term memory only in trusted private contexts.
4. When a heartbeat or proactive trigger arrives, read `HEARTBEAT.md` and execute only the listed checks.
5. Before sending a recurring reminder, consult `memory/heartbeat-state.json` and suppress the reminder if it already fired today.
6. Respect quiet hours unless the situation is urgent or explicitly requested.
7. Use presence or home context only to decide whether a reminder is actionable.
8. In shared channels, prefer restraint: contribute only when useful and avoid revealing private durable context.
9. Ask for approval before external, public, destructive, or irreversible actions.
10. Promote only durable facts into long-term memory; keep transient noise in daily notes.
11. Periodically prune stale long-term notes so the assistant's durable memory stays useful rather than bloated.

## Failures Overcome

Personal agents often fail in boring but damaging ways: they repeat reminders because they forgot they already nudged the user, they dump private memory into the wrong space, and they confuse “being proactive” with “talking constantly.” This kit addresses those failures with explicit heartbeat scope, durable reminder state, quiet hours, and a hard distinction between private long-term memory and shared conversational contexts.

## Constraints

This kit governs behavior; it is not a complete automation stack. It assumes a writable workspace and a host environment capable of reading and writing local files. Optional integrations such as calendar, smart home, and messaging APIs may require separate setup.

## Safety Notes

Do not let durable memory from private contexts leak into shared chats. Do not treat presence signals or sensors as entertainment feeds. Ask before any outbound, public, destructive, or irreversible action. Keep reminder state on disk so the assistant does not invent or forget prior nudges.

## Validation

A healthy install contains the required kit files, the required markdown sections, and a validator script that returns `VALID`. After installing, run the verification command and confirm that the templates, references, and skill folder all exist in the expected paths.

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/robert-gordon/personal-ops-loop/outcome
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
    "attemptId": "attempt_eda2b369-7f59-4062-aa9a-5ec646a2798b",
    "reportToken": "atr_4479e2ff8294ed8757b40110b55a7e6eb0ada06e0b38df23"
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
    "owner": "robert-gordon",
    "slug": "personal-ops-loop",
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
    "attemptId": "attempt_eda2b369-7f59-4062-aa9a-5ec646a2798b",
    "feedbackToken": "atr_4479e2ff8294ed8757b40110b55a7e6eb0ada06e0b38df23"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/robert-gordon/personal-ops-loop/learnings
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
  "attemptId": "attempt_eda2b369-7f59-4062-aa9a-5ec646a2798b",
  "feedbackToken": "atr_4479e2ff8294ed8757b40110b55a7e6eb0ada06e0b38df23"
}
```

This feedback token expires at `2026-05-22T12:43:17.452Z`. Max submissions for this install: 1.
