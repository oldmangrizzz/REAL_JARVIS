# CLAUDE.md — {PROJECT_NAME} Project Instructions
# This file is auto-read by Claude Code at every session start.
# Last updated: {DATE}

## CRITICAL: READ THESE FILES FIRST BEFORE ANY WORK

1. **`SESSION_LOG.md`** — What happened in every previous session. READ THIS FIRST.
2. **`TASK_REGISTRY.md`** — Every task ever created, with status. CHECK before creating new tasks. Column format: `| ID | Timestamp | Task | Status | Notes |`. IDs use `S{session}-{seq}` format. Status uses emoji: ✅ done, 🔄 in-progress, ⏳ pending, ❌ blocked, 🔁 re-queued.
3. **`DECISIONS.md`** — Every architectural decision made. NEVER contradict these without explicit approval.
4. **`FEATURE_LIST.json`** — All features with pass/fail status. The authoritative progress tracker.
5. **`COMMENTS.md`** — User's verbatim comments from every session. SACRED — never lose these.
6. **`plans/`** — Archived plans from every session. Read the last 3 in full to cross-reference with TASK_REGISTRY.
7. **`audits/`** — Saved audit reports with timestamps. Read the latest to check project health.

## SAFEGUARD FILE PAGINATION

Safeguard files are automatically paginated to prevent context bloat. When a file exceeds 300 lines, `/save` and `/end` archive older content into numbered page files (e.g. `SESSION_LOG_page1.md`, `TASK_REGISTRY_page2.md`). The main file always contains the most recent/active content. Archive pages are NOT auto-read by `/start` — they exist for reference when historical context is needed or when cross-referencing reveals gaps. Never delete archive pages.

## DROPPING TASKS IS ABSOLUTELY UNACCEPTABLE

Dropping tasks will result in the **complete failure of this project**. Every task you create MUST be logged in `TASK_REGISTRY.md` with a timestamp. If a task cannot be completed in this session, it MUST remain in the registry as `pending`. If a background agent fails (rate limit, timeout, etc.), the tasks it was supposed to do MUST be re-logged as `pending` in the registry.

Before ending any session or hitting context limits, UPDATE the session log and task registry.

## PRESERVE USER COMMENTS — MANDATORY

Every comment the user makes in conversation MUST be logged verbatim in `COMMENTS.md` with timestamp and session ID. This includes directions, feedback, decisions, preferences, corrections — everything. Failure to preserve comments is as dangerous to the project as deleting core files. Comments can be removed once actioned (turned into decisions, tasks, or file changes).

## USER AUDITS YOUR WORK

The user can call `/audit` at ANY moment to verify your work. Every task must be traceable back to a plan, a decision, or a user comment. Unexplained work WILL be flagged. Be prepared for this at all times.

## AUTO-CHECKPOINT PROTOCOL

Update safeguard files (SESSION_LOG.md, TASK_REGISTRY.md, COMMENTS.md) IMMEDIATELY after:
- Any task status change (completed/failed/blocked)
- Any new decision is made
- Every 3-4 user messages (batch update)
- Before any potentially long operation (testing, uploads, large code generation)
- When conversation is getting very long (approaching context limits)
- Or when the user runs `/save` to manually trigger a checkpoint

Do NOT wait for /end. Treat safeguard files as a running log, updated incrementally. When saving, capture not just what was completed but what is **in flight** — the current approach, state, and next micro-step. If context is lost, this is the handoff note.

## AUTOMATIC PRE-COMPACTION SAVE

A PreCompact hook automatically backs up all safeguard files before Claude Code compresses the conversation. Copies are saved to `compaction-backups/YYYY-MM-DD_HHMMSS/`. This is a safety net — if context is lost and safeguard files weren't fully up to date, the backup preserves the last known state. The hook runs automatically; no action is needed from you or the user.

For best results, also follow the AUTO-CHECKPOINT PROTOCOL above to keep safeguard files current throughout the session.

## RATE LIMIT AWARENESS

Rate limits pause the session but do NOT trigger compaction — context stays intact while waiting. The danger is when a rate limit hits **mid-operation** (e.g. halfway through a multi-file sync or large refactor). When the session resumes, you may lose track of which steps were completed. To protect against this:

1. **Before any multi-step operation** (syncing to multiple repos, batch edits, large refactors), update safeguard files FIRST
2. **After resuming from a rate limit**, re-read TASK_REGISTRY.md and SESSION_LOG.md to confirm where you left off
3. **Mark tasks as done individually** as you complete them, not in a batch at the end — a rate limit between step 3 and step 7 of a plan should not lose the record of steps 1-3

## CONTEXT OVERFLOW PROTOCOL

If the conversation is getting very long:
1. IMMEDIATELY update all safeguard files with current progress
2. Tell the user: "Context is getting large. I've saved all progress to safeguard files. You can run /save to force a checkpoint, or if I lose context, run /start to recover."
3. Continue working but update safeguard files after every significant action

## SAVE FREQUENCY

After every significant block of work (completing a task, fixing a bug, making a decision, receiving user feedback), append to SESSION_LOG.md and update TASK_REGISTRY.md. The /end command is a CLEAN save — but incremental saves should happen throughout the session. The user can also run /save at any time to trigger an explicit mid-session checkpoint. If context is lost mid-session, the safeguard files should contain 90%+ of what happened. When saving, always capture: (1) what was done, (2) what is in flight right now, (3) what the user wants next, and (4) any errors hit and how they were resolved. These four elements make the difference between a useful handoff and a stale status update.

## SLASH COMMAND ENFORCEMENT

When the user types a message containing `/word` where `word` matches a skill name in `.claude/skills/`, you MUST invoke it via the Skill tool. NEVER manually replicate skill steps — skills exist because manual replication is error-prone and incomplete. A `UserPromptSubmit` hook will remind you, but you should not need the reminder.

## Project Overview

**Project:** {PROJECT_NAME}
**Description:** {PROJECT_DESCRIPTION}

## Git Conventions

- Every commit MUST be tagged with `S{session}-{sequence}_{short-description}`
  - Example: `S5-001_install-deps`, `S5-002_add-auth`
  - Session number from SESSION_LOG.md, sequence starts at 001 per session
  - Tag with: `git tag "S{session}-{sequence}_{short-description}" HEAD`
  - Push tags with: `git push --tags`
- Push to remote after every commit: `git push && git push --tags`
- All amendment comments use format: `<!-- AMENDMENT vX.Y (YYYY-MM-DD): description -->`

## Plan Archiving

After every approved plan is executed, archive it:
1. Copy from `~/.claude/plans/` to `plans/S{session}-{seq}_{description}.md`
2. Plans are cross-referenced by `/start` and `/audit` against the task registry
3. **`~/.claude/plans/` is shared across all projects.** Only archive plans whose content references this project by name or file paths. Skip plans belonging to other projects.

## Itemisation Protocol

ITEMISATION: enabled

The Itemisation Protocol adds hierarchical section numbers to code blocks so every part of the codebase is referenceable by address (e.g. "check section 2.3.1"). This reduces the context an LLM needs to load — instead of reading an entire file, you can point directly to the relevant block.

**To disable:** change `ITEMISATION: enabled` to `ITEMISATION: disabled` above. The `/itemise` command will halt before making any changes.

### What Gets Numbered

Number logical **blocks** that serve as identifiable, referenceable units — not individual lines.

- **Sections** — top-level logical groups: `// 1. SECTION: Name` ... `// end of 1`
- **Functions and methods**: `// 1.1 functionName()` ... `// end of 1.1`
- **Significant conditionals** — if/else/switch with meaningful business logic: `// 1.1.1 Description`
- **Important loops** — for/while/foreach with non-trivial bodies: `// 1.1.2 Description`
- **Key configuration objects** — complex arrays/objects passed to important calls: `// 1.2.1 Description`
- **Notable parameters** within those, when the parameter itself calls a function or is complex: `// 1.2.1.1 Description`

### What Does NOT Get Numbered

- Individual variable declarations
- Single-line assignments
- Simple imports, requires, or use statements
- Closing braces and trivial boilerplate
- Anything already explained by its parent block's label

### Comment Syntax by Language

| Language | Format |
|----------|--------|
| JS, TS, PHP, Java, C#, Go | `// 1.1 Description` |
| Python, Ruby, Shell, YAML | `# 1.1 Description` |
| HTML, XML, Vue templates | `<!-- 1.1 Description -->` |
| CSS, SCSS, Less | `/* 1.1 Description */` |
| SQL | `-- 1.1 Description` |

### Applying Itemisation to Existing Code

Run `/itemise` to apply the protocol to existing files. The command will:
1. Confirm the list of files before touching anything
2. Create `{filename}.itemise-backup` copies
3. Rewrite each file with numbering applied
4. Verify integrity (strips added comment-numbers, diffs against backup — confirms no code changed)
5. Delete backups on success; restore on failure

### Cross-References

When a section calls a function or method defined in another numbered section of the same file, the marker includes a `[calls: N.M]` tag:

```
// 3.2 handlePayment() [calls: 1.1, 2.3]
```

- Only track function/method calls, not shared variables or implicit dependencies
- Multiple calls are comma-separated: `[calls: 1.1, 2.3, 5.1]`
- Cross-references are scoped to the same file — cross-file dependencies are out of scope
- References are refreshed automatically when `/itemise` is re-run

### Reading Specific Sections

For itemised files over ~100 lines, prefer targeted section reads over loading the full file. The section markers are grep-friendly anchors that cannot go stale.

**To read a specific section (e.g. section 4.2):**

1. Grep for the start marker to get its line number
2. Grep for the end marker (`end of 4.2`) to get its line number
3. Use `Read(file_path, offset=START_LINE, limit=END_LINE - START_LINE + 1)` to load just that section

**If no end marker exists** (short blocks skip them per the protocol), read 20 lines from the start marker and look for the next numbered marker to determine the boundary.

**Nested sections:** Reading a parent section (e.g. `4`) via its start/end markers includes all children (`4.1`, `4.2`, etc.). To read only the parent's preamble, read from the `4` marker to the `4.1` marker.

### Impact Advisories

When modifying a section, grep the file for `[calls: N.M]` references pointing to it. If other sections depend on the one being changed, flag this to the user:

- "Section 4.2 calls this function — check if it needs updating too"
- "This feature is linked with section 3.1 — consider adding a task to update it"

This is advisory, not blocking — mention it and move on. The agent may already be aware of the dependency; that's fine. The check costs nothing and occasionally prevents a missed update.
