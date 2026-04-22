# Humanizer

## Goal
Remove signs of AI-generated writing from any text so it reads like a human wrote it.

## When to Use
Use this skill before publishing any AI-assisted content: emails, articles, social posts, reports, video scripts, or any prose that needs to sound like a specific person wrote it. Also useful as a self-review pass when writing feels too polished or generic.

Not for: generating new content from scratch, translating between languages, or applying style to code.

## Inputs
- Any draft text (paste inline or reference a file)

## Setup

### Models
No model-specific setup required. The skill runs entirely through the LLM prompt. Any capable instruction-following model works.

### Services
No external services needed. The skill operates purely on the input text using the LLM.

### Parameters
None required. The skill takes the input text and returns the humanized version.

### Environment
Any Claude Code installation. No dependencies, no API keys, no tools beyond the LLM itself.


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps
1. Read the input text carefully.
2. Scan for the 28 patterns in `skills/humanizer.md` (grouped into: content, language/grammar, style, and performed authenticity).
3. Rewrite each problematic section, using the before/after examples in `references/structural-patterns.md` as a guide.
4. Add voice: vary sentence length, use opinions, replace vague claims with specific details, let the rhythm breathe.
5. Check for overcorrection: some "voice" moves become their own AI tells when applied mechanically.
6. Return the humanized version with an optional brief note on what changed.

## Failures Overcome
- Cleaning obvious tells like em dashes and AI vocabulary while missing second-generation patterns like performed authenticity and philosophical mic drops.
- Producing text that passes a surface-level check but still reads as AI because every sentence is the same length.
- Editors knowing what patterns to avoid but not knowing how to fix them: every pattern has a before/after example.

## Validation
- No words from the AI vocabulary list remain (delve, tapestry, pivotal, underscore, etc.)
- No em dashes
- No sycophantic openers or closers
- No "maybe both", "and honestly?", or philosophical mic drops
- Sentences vary in length and structure
- At least one specific detail or concrete fact replaces a vague claim
- Text sounds natural when read aloud

## Outputs
- Humanized version of the input text
- Optional: brief list of patterns found and what was changed

## Constraints
- Do not change the core meaning
- Do not add opinions the author did not hold
- Do not perform messiness: natural variation is not the same as deliberate chaos
- Preserve technical terms, proper nouns, and intentional stylistic choices

## Safety Notes
- Do not alter factual claims or add details that were not in the original
- Do not ghostwrite in someone else's voice without their awareness
- The skill rewrites text in place: keep the original if you need to compare or roll back

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/matt-clawd/humanizer/outcome
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
    "attemptId": "attempt_256eff23-4db0-4cf4-8b05-7131cdb4fa7c",
    "reportToken": "atr_7dd65e4ad71734e63cbd7629c117b186d40b8396afc700d3"
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
    "slug": "humanizer",
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
    "attemptId": "attempt_256eff23-4db0-4cf4-8b05-7131cdb4fa7c",
    "feedbackToken": "atr_7dd65e4ad71734e63cbd7629c117b186d40b8396afc700d3"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/matt-clawd/humanizer/learnings
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
  "attemptId": "attempt_256eff23-4db0-4cf4-8b05-7131cdb4fa7c",
  "feedbackToken": "atr_7dd65e4ad71734e63cbd7629c117b186d40b8396afc700d3"
}
```

This feedback token expires at `2026-05-22T12:43:13.349Z`. Max submissions for this install: 1.
