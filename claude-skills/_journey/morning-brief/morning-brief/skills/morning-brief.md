---
name: morning-brief
description: Text-only morning briefing workflow for any professional. Run the bundled build script to turn today's calendar, priority tasks, and weather into a concise daily digest on stdout.
---

# Daily Brief

## Goal
Create a concise text morning brief from today's schedule, priority tasks, weather, and meeting prep context.

## When to Use
Use this skill for scheduled daily briefing jobs when you want a general-purpose workflow that is not tied to content metrics, voice output, or any specific agent platform.


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps
1. Confirm `gcalcli` can read today's calendar before composing the brief, or set `CALENDAR_SOURCE_FILE` when you want to smoke-test with bundled fixtures.
2. Point `TASKS_FILE` at a real markdown task file, or let the build script fall back to the bundled sample tasks for a first-run preview.
3. Run `bash src/scripts/build-brief.sh` from the kit directory to generate the brief on stdout.
4. Review the generated sections and swap the sample task file for your real priorities before production use.
5. Deliver the result through the runtime's preferred output channel after the stdout brief looks right.

## Constraints
- This workflow is text-only. Do not add voice notes, TTS, or audio follow-ups.
- Fix broken calendar reads before sending the brief.
- Keep confidential task and meeting context in trusted destinations only.

## Safety Notes
- Do not expose delivery credentials or internal meeting notes in bundled files.
- Treat the task file and meeting context as sensitive work material.
- Do not send the brief to public channels by default.

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/matt-clawd/morning-brief/outcome
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
    "attemptId": "attempt_6d56f6ce-e814-422a-9383-7836df6f474a",
    "reportToken": "atr_fb1925524fdfad7e8798b5a07fa576598897e4b82f64a46b"
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
    "owner": "matt-clawd",
    "slug": "morning-brief",
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
    "attemptId": "attempt_6d56f6ce-e814-422a-9383-7836df6f474a",
    "feedbackToken": "atr_fb1925524fdfad7e8798b5a07fa576598897e4b82f64a46b"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/matt-clawd/morning-brief/learnings
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
  "attemptId": "attempt_6d56f6ce-e814-422a-9383-7836df6f474a",
  "feedbackToken": "atr_fb1925524fdfad7e8798b5a07fa576598897e4b82f64a46b"
}
```

This feedback token expires at `2026-05-22T12:43:12.405Z`. Max submissions for this install: 1.
