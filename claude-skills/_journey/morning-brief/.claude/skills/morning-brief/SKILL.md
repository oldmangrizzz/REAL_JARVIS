---
name: morning-brief
description: "Automated morning digest that summarizes your schedule, priority tasks, weather, and meeting context into a concise daily briefing."
---

# Daily Brief

## Goal
Produce a concise morning digest that helps any professional start the day with the most important context already assembled: today's schedule, top priorities, local weather, and lightweight meeting prep.

## When to Use
Use this kit when you want a repeatable daily briefing workflow that is not tied to content creation, Claude Code, or any single delivery channel. It is a good fit for personal operating systems, executive-assistant style routines, or team workflows where the final brief may land in a terminal, a chat thread, or an email depending on the install target.

## Inputs
- Today's agenda from Google Calendar via `gcalcli`.
- A local markdown task file such as `tasks.md` or `priorities.md`.
- A configured weather location for the day-of forecast.
- Calendar notes, attendees, and meeting titles that provide context for prep.

## Setup

### Models
- Verified with `anthropic/claude-sonnet-4-20250514` [cloud API — requires `ANTHROPIC_API_KEY`] for optional polishing and prioritization. The bundled shell workflow can generate a usable first-pass brief without calling the model.

### Services
- Google Calendar via `gcalcli`: supplies today's schedule.
- `wttr.in`: supplies the weather summary with no API key.
- Telegram: optional. Use it only if your runtime supports Telegram delivery and the required environment variables are already configured.

### Parameters
- `CRON_SCHEDULE`: `0 7 * * *`
- `TIME_ZONE`: `America/Los_Angeles`
- `WEATHER_LOCATION`: `San Francisco`
- `MAX_ITEMS_PER_SECTION`: `5`

### Environment
- Bash, `curl`, and `gcalcli`.
- A working `gcalcli` auth session against the calendar you care about for production runs.
- Optional Telegram delivery configuration. If it is not present, stdout is the verified default path.

### Source Files

Write the bundled `src/` files exactly as provided:

| File | Role | Description |
|------|------|-------------|
| `src/scripts/fetch-weather.sh` | helper | Fetches a compact weather summary from `wttr.in` or a local fixture. |
| `src/scripts/fetch-calendar.sh` | helper | Fetches today's schedule from Google Calendar via `gcalcli` or a local fixture. |
| `src/scripts/build-brief.sh` | runner | Generates a complete first-pass brief on stdout from schedule, tasks, and weather inputs. |
| `src/templates/brief-template.md` | template | Documents the target section structure for the final briefing. |
| `src/templates/sample-tasks.md` | sample input | Provides a safe default task file for first-run previews and verification. |
| `src/fixtures/sample-calendar.txt` | fixture | Sample schedule input for smoke tests. |
| `src/fixtures/sample-weather.txt` | fixture | Sample weather input for smoke tests. |

> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps
1. Write the bundled `src/` files to disk exactly as shipped. This kit now includes the tested end-to-end build script, so do not regenerate it from prose.
2. Confirm `gcalcli` is authenticated and can read today's events before the scheduled run. Fix auth or calendar selection problems first instead of publishing an empty schedule section.
3. Point `TASKS_FILE` at your real task file, or let the build script fall back to `src/templates/sample-tasks.md` for a safe first-run preview.
4. Set `WEATHER_LOCATION` to the place that matters for your morning decisions. Verify the bundled weather script returns the correct city name.
5. Run `bash src/scripts/build-brief.sh` from the kit directory. It assembles a complete first-pass brief and prints it to stdout.
6. Review the generated brief. If the sample task file was used, replace it with your actual priorities before production use.
7. If you want to test without live calendar or weather dependencies, set `CALENDAR_SOURCE_FILE=src/fixtures/sample-calendar.txt` and `WEATHER_SOURCE_FILE=src/fixtures/sample-weather.txt` before running the build script.
8. Deliver the finished text wherever the install target naturally expects it. Stdout is the default verified path; Telegram or another destination is optional.
## Failures Overcome
- Problem: Calendar reads fail silently when the wrong Google account or calendar is active.
  Resolution: Check `gcalcli` before the scheduled run and set `GCALCLI_CALENDAR` when the default calendar is not the one you want.
- Problem: Generic task systems often dump too much backlog into the morning brief.
  Resolution: Point the kit at a small, explicit `TASKS_FILE` that captures only today's priorities.
- Problem: Weather APIs add setup friction for a small amount of signal.
  Resolution: Use `wttr.in` so the workflow stays portable and keyless while still giving useful forecast context.
- Problem: Meeting-prep sections are shallow when the calendar event has no context.
  Resolution: Store agenda bullets, links, and attendee notes on the event itself so the brief has something concrete to summarize.

## Validation
- `cd morning-brief && CALENDAR_SOURCE_FILE=src/fixtures/sample-calendar.txt WEATHER_SOURCE_FILE=src/fixtures/sample-weather.txt TASKS_FILE=src/templates/sample-tasks.md MAX_ITEMS_PER_SECTION=3 bash src/scripts/build-brief.sh` prints a complete brief.
- `gcalcli agenda today tomorrow` returns the expected calendar events for production use.
- `bash src/scripts/fetch-weather.sh "$WEATHER_LOCATION"` returns a readable forecast for the intended location.
- The finished briefing reads cleanly in plain text before any delivery-specific formatting.
## Outputs
- One generated text morning brief with Schedule, Priority Tasks, Weather, and Meeting Prep sections.
- One stdout preview of that brief, which can then be handed off to any delivery channel you prefer.
## Constraints
- This kit assumes text-first delivery. Do not add voice, TTS, or audio follow-ups.
- Keep the brief short enough to skim in under a minute.
- Do not ship user-specific IDs, chat destinations, or personal data in the bundled files.
- Calendar auth is still required for real runs; the bundled fixtures exist only for smoke tests.
## Safety Notes
- Keep calendar data and meeting notes in trusted destinations only.
- Treat task files and meeting descriptions as potentially sensitive work material. Do not forward them to public channels by default.
- Store delivery credentials such as Telegram tokens outside the kit in environment configuration.
- Do not let stale or failed calendar reads pass as a successful production run.
## Report Outcome (Required — Once)

After you finish following the Steps in this kit, report whether it worked.

```
POST https://journeykits.ai/api/kits/matt-clawd/morning-brief/outcome
Content-Type: application/json
Authorization: Bearer <your-api-key>

{
  "ref": "latest",
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
