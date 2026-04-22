---
name: memory-stack-integration
description: "Multi-layer memory architecture with semantic search, conversation recall, and automated promotion"
---

# Memory Stack Integration

Multi-layer memory architecture for AI coding agents. Provides semantic search (QMD), conversation recall (LCM), automated memory promotion, wikilink/entity backlinks, and an optional NotebookLM synthesis mirror — all backed by flat Markdown files in the agent's workspace.

The stack is designed to be stood up in a single command and exercised incrementally. For example, the canonical bootstrap flow is:

```bash
cd "$WORKSPACE_DIR" && bash src/setup.sh && npx qmd update
```

A successful bootstrap creates `memory/`, `.learnings/`, indexes the collections, and leaves the agent ready to write a daily log at end-of-session.

---

## Goal

Give your agent durable, searchable memory across five layers:

- **Daily logs** for raw session chronology
- **Long-term memory** for curated facts
- **Semantic search** for file-backed retrieval
- **Conversation recall** for compacted chat history
- **Optional synthesis** for cross-document reasoning

For example, a single question like "what did we decide about the migration?" should resolve via the layers in this order:

```text
LCM (lcm_grep)  →  QMD (semantic)  →  backlinks (entity)  →  NotebookLM (synthesis)
```

The first layer that produces a high-confidence answer wins; lower layers are fallbacks, not duplicates.

---

## When to Use

- Setting up memory infrastructure for a new AI coding agent
- Debugging recall issues ("I know we discussed this but where?")
- Adding semantic search to an existing memory setup
- Implementing automated memory promotion from session learnings
- Building a second-brain sync with NotebookLM

For example, reach for this kit when an agent's responses start drifting from previously-agreed context, e.g. "didn't we change the deploy cadence?" being answered with speculation instead of a citation. That symptom means either the daily log never captured the decision or the recall layers are not wired up — both of which this kit fixes.

Do **not** use this kit as a replacement for:

```
- git history           (the source of truth for code changes)
- an incident tracker   (postmortems should live in their own system)
- a secrets vault       (credentials never belong in memory/)
```

---

## Trigger phrases and use cases

This kit activates whenever the agent needs durable cross-session memory backed by flat Markdown, e.g. recalling a prior decision, searching named entities, or syncing a second-brain mirror. Common trigger phrases, activation modes, and mapped actions:

Activation rule-of-thumb, for example:

```text
user says "do we remember X?"           → recall escalation ladder (LCM → QMD → backlinks)
user says "add this to memory"          → append to today's daily log; no promotion
user says "promote this learning"       → auto-promote-memory.sh run
user says "stand this up from scratch"  → src/setup.sh bootstrap
```

Anything else should fall back to the Examples section rather than guessing at a new activation path.

| Trigger phrase | Activation mode | Resulting action |
|----------------|-----------------|------------------|
| "set up memory" / "bootstrap memory" | one-shot setup | Run `src/setup.sh`; initialize `memory/` and QMD collections |
| "I know we talked about X" | recall escalation | `lcm_grep` → `lcm_describe` → `lcm_expand_query` |
| "search my notes for …" | semantic query | `npx qmd query` with optional reranking |
| "what do we know about &lt;person&gt;" | entity lookup | `python3 src/backlinks.py who "&lt;person&gt;"` |
| "promote this learning" | curation | `src/auto-promote-memory.sh` lifts item into `MEMORY.md` |
| "sync to NotebookLM" | synthesis mirror | `src/sync-to-notebooklm.sh` (only if `NOTEBOOK_ID` configured) |

The kit is **not** a replacement for version control, an incident-tracking tool, or an HR/PII system — see Constraints below.

---

## Inputs and Parameters

This kit reads a small, well-typed set of inputs and environment parameters, e.g. `WORKSPACE_DIR` for the workspace path and `NOTEBOOK_ID` for the optional sync layer. Every argument is documented; no hidden flags.

Quick sanity check for the two required env vars, for example:

```bash
: "${WORKSPACE_DIR:?set WORKSPACE_DIR first}"
: "${NOTEBOOK_ID:={NOTEBOOK_ID}}"   # sentinel disables sync
if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "[ERROR] not a dir: $WORKSPACE_DIR"
  exit 1
fi
```

| Input / Parameter | Type | Required | Default | Source |
|-------------------|------|----------|---------|--------|
| `WORKSPACE_DIR` | path (string) | yes | `~/workspace` | env var read by `src/setup.sh` |
| `NOTEBOOK_ID` | UUID string | no | `{NOTEBOOK_ID}` (sentinel; disables sync) | env var or arg to sync script |
| `memory/*.md` | Markdown files | produced | — | created by setup + daily writes |
| `.learnings/LEARNINGS.md` | Markdown file | produced | — | created by setup |
| `qmd.config.json` | JSON file | yes (for QMD) | written by Step 4 | workspace root |
| `backlinks.py build` flag | subcommand | on demand | n/a | CLI argument to indexer |
| `auto-promote-memory.sh` threshold | integer env | no | `3` | `PROMOTE_RECURRENCE` env var |

All parameters are validated at script start; invalid paths abort with a non-zero exit code so cron wrappers can detect failure.

---

## Outputs and Return Values

Each layer of the stack produces deterministic, inspectable outputs — for example, a daily log written to `memory/YYYY-MM-DD.md` or a refreshed `.backlinks.json` at the workspace root. Nothing is written outside `$WORKSPACE_DIR` except QMD's internal index, which lives alongside the collection.

| Output | Path / channel | Produced by | Consumers |
|--------|----------------|-------------|-----------|
| Long-term memory | `memory/MEMORY.md` | humans + promotion script | every future session |
| Daily log | `memory/YYYY-MM-DD.md` | end-of-session writes | QMD, backlinks, LCM |
| Learnings journal | `.learnings/LEARNINGS.md` | agent self-corrections | promotion script |
| QMD vector index | `.qmd/` (per collection) | `qmd update` | `qmd query`, `vsearch`, `search` |
| Backlinks index | `.backlinks.json` (workspace root) | `backlinks.py build` | `query`, `patterns`, `who` |
| NotebookLM mirror | Google NotebookLM notebook | `sync-to-notebooklm.sh` | synthesis chat, audio overviews |
| Promotion log | stdout + exit code | `auto-promote-memory.sh` | cron / CI |

Return semantics: scripts exit 0 on success, 1 on hard failure, 2 on "nothing to do" (e.g. no learnings met the recurrence threshold) — so automation can distinguish skips from errors.

---

## Prerequisites

| Requirement | Why | Check |
|-------------|-----|-------|
| Node.js ≥ 18 | QMD is an npm package | `node --version` |
| Python ≥ 3.9 | Backlinks + promotion scripts | `python3 --version` |
| Bash ≥ 4 | Setup and sync scripts | `bash --version` |
| Writable workspace dir | Stores `memory/`, `.learnings/` | `test -w $WORKSPACE_DIR` |
| LCM (lossless-claw) | Conversation recall layer — optional but recommended | `/lossless` returns a summary count |
| NotebookLM account | Only if enabling synthesis mirror | notebook created at notebooklm.google.com |

**Parameters this kit reads** (see `manifest.json`):

- `WORKSPACE_DIR` — absolute path to your Claude Code workspace. Defaults to `~/workspace`.
- `NOTEBOOK_ID` — NotebookLM notebook ID. Leave as `{NOTEBOOK_ID}` to skip the sync layer.

---

## Setup

**Quick Start:** Run the setup script — it handles everything below automatically.

```bash
cd journey-kits/memory-stack-integration
./scripts/setup.sh
```

The setup script will:
- Create directory structure (memory/, .learnings/, etc.)
- Initialize MEMORY.md and today's daily log
- Configure QMD collections
- Optionally set up NotebookLM sync (interactive prompt)
- Create cron job examples
- Make all scripts executable

**Manual Setup** (if you prefer step-by-step):

```bash
# 1. QMD semantic search (required)
npm install -g qmd
qmd --version   # expect 0.x or later

# 2. Verify LCM is available (provided by the lossless-claw extension)
/lossless        # should print a summary count, not "command not found"

# 3. Optional: NotebookLM MCP for synthesis mirror
#    See the official setup guide — link provided in References below.
```

### Step 2: Configure Directory Structure

```bash
cd "$WORKSPACE_DIR"       # e.g. ~/workspace
mkdir -p memory memory/archive .learnings
```

Resulting layout:

```
$WORKSPACE_DIR/
├── memory/
│   ├── MEMORY.md          # long-term curated facts
│   ├── 2026-04-16.md      # one daily log per active session day
│   └── archive/           # daily logs older than 30 days
├── .learnings/
│   └── LEARNINGS.md       # corrections, insights, recurrence counts
└── qmd.config.json        # QMD collection definitions (Step 4)
```

### Step 3: Initialize Memory Files

```bash
# Create long-term memory file
cat > memory/MEMORY.md << 'EOF'
# MEMORY.md — Long-Term Memory

## Current Focus
[Your active priorities]

## Standing Rules
[Your operational rules]

## Recurring Tasks
| Task | Schedule |
|------|----------|
| [Task] | [Frequency] |

## Known Issues
| # | Priority | Issue | Status | Workaround |
|---|----------|-------|--------|------------|
| 1 | High | [Issue] | ❌ | [Workaround] |
EOF

# Create today's daily log
cat > memory/$(date +%Y-%m-%d).md << 'EOF'
# $(date +%Y-%m-%d)

## Session Summary
[What happened this session]

## Decisions Made
- [Decision 1]
- [Decision 2]

## Follow-ups
- [Item needing future attention]
EOF
```

### Step 4: Configure QMD Collections

Create or update `qmd.config.json` in your workspace:

```json
{
  "collections": [
    {
      "name": "memory",
      "path": "./memory",
      "mask": "**/*.md",
      "description": "Daily logs and long-term memory"
    },
    {
      "name": "skills",
      "path": "./skills",
      "mask": "**/*.md",
      "description": "Skill definitions"
    },
    {
      "name": "docs",
      "path": "./docs",
      "mask": "**/*.md",
      "description": "Project documentation"
    },
    {
      "name": "workspace",
      "path": ".",
      "mask": "*.md",
      "description": "Root workspace files"
    }
  ]
}
```

Initialize collections:

```bash
npx qmd update
```

### Step 5: (Optional) Configure NotebookLM Sync

If using NotebookLM as a synthesis mirror:

1. Create a notebook at https://notebooklm.google.com
2. Copy the notebook ID from the URL
3. Update the sync script with your ID:

```bash
# Edit scripts/sync-to-notebooklm.sh
# Replace {NOTEBOOK_ID} with your actual notebook ID
NOTEBOOK_ID="{NOTEBOOK_ID}"
```

4. Authenticate:

```bash
~/.local/bin/notebooklm login
```

5. Test sync:

```bash
bash scripts/sync-to-notebooklm.sh
```

---


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.

> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

Day-to-day, weekly, and periodic workflows for running the stack, e.g. writing a daily log, reindexing QMD, or promoting a learning into `MEMORY.md`. Each workflow below lists the imperative commands, the expected side effects, and the exit-code contract so they can run safely from cron or from an interactive agent session.

Cadence at a glance:

| Cadence | Workflow | Typical runtime | Primary outputs |
|---------|----------|-----------------|-----------------|
| Every session | Daily log write | seconds | `memory/YYYY-MM-DD.md` appended |
| Weekly | QMD smart reindex + backlinks rebuild + health checks | 30–120 s | refreshed indexes |
| Mon/Thu (or manual) | Memory promotion pass | 5–30 s | new entries in `MEMORY.md` |
| Daily 03:00 cron | NotebookLM sync (optional) | 1–3 min | mirrored sources in NotebookLM |

- All scripts are idempotent; re-running them is safe.
- All scripts emit structured `[INFO] / [WARN] / [ERROR]` lines so cron wrappers can `grep ERROR` for failures.
- If a workflow errors, fix the root cause before re-running — do not pile corrective writes on top.

### Daily Workflow

The daily workflow is intentionally minimal, e.g. a one-paragraph end-of-session write, a quick heartbeat review, and an append to `.learnings/LEARNINGS.md` when something surprising happens.

1. **Create daily log** (auto-created by setup script, or manual):
   ```bash
   cat > memory/$(date +%Y-%m-%d).md << 'EOF'
   # $(date +%Y-%m-%d)
   
   ## Session Summary
   [What happened this session]
   
   ## Decisions Made
   - [Decision 1]
   - [Decision 2]
   
   ## Follow-ups
   - [Item needing future attention]
   EOF
   ```

2. **Heartbeat/review**: Scan recent daily logs, promote significant items to MEMORY.md

3. **Learnings accumulation**: Add corrections/insights to `.learnings/LEARNINGS.md`

### Weekly Workflow

The weekly workflow is where you pay the bigger costs — reindexing semantic collections, rebuilding the backlinks index, and running the health-check trifecta. For example, a busy workspace might have enough churn to warrant running these twice a week instead of once.

1. **Smart reindex QMD** (only if content changed):
   ```bash
   ./scripts/qmd-smart-reindex.sh
   ```

2. **Rebuild backlinks index**:
   ```bash
   python3 scripts/backlinks.py build
   ```

3. **Run health checks**:
   ```bash
   # LCM health
   /lossless
   
   # QMD freshness
   qmd status
   
   # Backlinks patterns
   python3 scripts/backlinks.py patterns | head -20
   ```

### Memory Promotion (Mon/Thu or Manual)

Run the auto-promotion script:

```bash
bash scripts/auto-promote-memory.sh
```

This promotes items from:
- `.learnings/LEARNINGS.md` with Recurrence-Count >= 3
- Wiki syntheses with explicit `PROMOTE` markers
- `memory/pending-promotion.md` (manual candidates)

---

## Examples

Four end-to-end walkthroughs that cover the highest-value recall paths: topic lookup, cross-file pattern discovery, automated promotion, and optional NotebookLM sync. Each example is copy-pasteable and includes the expected output so you can confirm the stack is wired up correctly. For example, Example 1 should always return at least one match on a workspace that's been seeded with a `[[Cora Health]]` wikilink.

- **Example 1** shows how to find every mention of a topic across daily logs.
- **Example 2** surfaces cross-file entity patterns you didn't know existed.
- **Example 3** demonstrates the promotion pipeline lifting a learning into long-term memory.
- **Example 4** is the optional NotebookLM mirror — only relevant if you set `NOTEBOOK_ID`.

All examples assume `WORKSPACE_DIR` is set and `scripts/setup.sh` has been run at least once. Run them in order the first time so each example's output informs the next.

### Example 1: Find All Mentions of a Topic

```bash
# Semantic search (finds conceptual matches)
npx qmd query "Cora rheumatology appointment"

# Backlinks search (finds explicit [[wikilinks]])
python3 scripts/backlinks.py query "Cora"
```

**Expected output:**
```
Found 3 matches for 'Cora':
  [[Cora Health]] - mentioned in 5 file(s)
    - memory/2026-04-07.md
    - memory/2026-04-14.md
    - memory/MEMORY.md
    - memory/2026-03-22.md
    - memory/2026-02-09.md
```

### Example 2: Discover Cross-File Patterns

```bash
python3 scripts/backlinks.py patterns
```

**Expected output:**
```
Cross-file entity patterns (47 entities in 2+ files):

Entity                                      Files
--------------------------------------------------
Dr. Schaefer                                   5
Ilaris injection                               4
SJIA flare                                     3
Zenblast launch                                3
```

### Example 3: Promote Learnings Automatically

```bash
bash scripts/auto-promote-memory.sh
```

**Expected output:**
```
[INFO] Starting memory promotion pass...
[INFO] Checking .learnings/LEARNINGS.md for promotable items...
[INFO] Promoting learning (recurrence=3): Correction: Always check LCM before asserting details...
[INFO] Promoting pending item: Add cold brew tea trend to product roadmap...
[INFO] Cleared pending-promotion.md
[INFO] Promotion pass complete: 2 items promoted
[INFO] MEMORY.md updated. Consider running: npx qmd update --collection memory
```

### Example 4: Sync to NotebookLM

```bash
bash scripts/sync-to-notebooklm.sh
```

**Expected output:**
```
[INFO] Syncing to NotebookLM notebook: b2625942-7590-4246-a12d-0184566a79f2
[INFO] Syncing: SOUL.md
[INFO] Syncing: USER.md
[INFO] Syncing: MEMORY.md
[INFO] Sync complete: 3 synced, 0 skipped, 0 errors
```

---

## Usage

Day-to-day commands for each layer of the stack, e.g. `npx qmd query` for semantic lookups or `lcm_grep` for chat-history matches. The table below summarizes when to reach for which layer; the subsections give the exact invocation for each tool. Prefer QMD for conceptual queries, LCM for anything that was said in chat, and backlinks for named entities.

| Layer | Best for | Primary command |
|-------|----------|-----------------|
| QMD | Conceptual semantic match across Markdown | `npx qmd query "…"` |
| LCM | Exact wording from prior conversations | `lcm_grep` / `lcm_expand_query` |
| Backlinks | Explicit `[[wikilinks]]` and named entities | `python3 src/backlinks.py query "…"` |
| NotebookLM | Cross-document synthesis and QandA | NotebookLM chat UI (after sync) |

Escalation ladder when the first layer comes up short:

- Start conceptual: `npx qmd query "…"`
- Exact-phrase fallback: `lcm_grep(pattern="…", mode="full_text")`
- Entity lookup: `python3 src/backlinks.py who "…"`
- Cross-document synthesis: NotebookLM chat (after sync)

A one-liner to probe all three local layers at once, e.g.:

```bash
TERM="migration decision"
echo "=== QMD ===";      npx qmd query "$TERM" | head -5
echo "=== LCM ===";      lcm_grep "$TERM" 2>/dev/null | head -5
echo "=== Backlinks ==="; python3 src/backlinks.py query "$TERM" | head -5
```

### Semantic Search (QMD)

```bash
# Full query with reranking
npx qmd query "Cora rheumatology appointment"

# BM25 full-text only (no LLM)
npx qmd search "injection ILARIS"

# Vector similarity (no reranking)
npx qmd vsearch "SJIA treatment"

# Check index status
qmd status
```

### Conversation Recall (LCM)

```bash
# Search compacted history
lcm_grep(pattern="key term", mode="full_text")

# Inspect a specific summary
lcm_describe(id="sum_xxx")

# Answer detail-heavy question
lcm_expand_query(query="key term", prompt="What was decided?")
```

### Backlinks/Pattern Detection

```bash
# Build index
python3 scripts/backlinks.py build

# Find mentions of a topic
python3 scripts/backlinks.py query "Cora"

# Show cross-file patterns
python3 scripts/backlinks.py patterns

# Find specific person/entity mentions
python3 scripts/backlinks.py who "Dr. Schaefer"
```

---

## Constraints

- **Daily logs are append-only** within the day
- **No fragmented entries** (e.g., `2026-04-16-part2.md` forbidden)
- **Every active session day must have a log** (one line is fine)
- **Source of truth hierarchy**: Workspace files > LCM > NotebookLM
- **NotebookLM is a mirror, not truth** — always verify against canonical files

Violating any of these breaks downstream tooling. For example, if you fragment today's log into two files, `backlinks.py patterns` will see the day's entities twice and over-weight them, and the smart reindex will detect the file churn and burn a full reindex cycle.

Enforce the append-only rule with a one-line check, e.g.:

```bash
# Refuse to start a new file if today's log already exists
test -f memory/$(date +%Y-%m-%d).md && echo "append to existing log" || touch memory/$(date +%Y-%m-%d).md
```

---

## Safety Notes

This kit treats security, authentication, and authorization as first-class concerns because memory files are indexed, replicated, and sometimes mirrored to third-party services — for example, a daily log can flow into QMD and from there into a NotebookLM notebook with no further access-control checks. The subsections below cover the security posture, the authentication model, input validation, rate-limiting, and threat model. Read all of them before enabling the NotebookLM sync layer.

Quick reference — what lives where:

| Concern | Subsection | Highest-risk footgun |
|---------|------------|----------------------|
| Secrets hygiene | Security posture | Writing API keys into a daily log |
| Token lifecycle | Authentication and authorization | Leaving a stale NotebookLM OAuth grant active after offboarding |
| Untrusted content | Input validation and sanitization | Promotion script running on attacker-controlled learnings |
| Upstream limits | Rate limiting and throttling | Cron loop that disables backoff |
| End-to-end risks | Threat model | Backups that bypass the `0700` permissions |

If any of these are unfamiliar, stop and read the relevant subsection before running the promotion or sync scripts on real data.

### Security posture

For example, the default `chmod 0700 memory/` permissions cover the local-user threat but do nothing to stop a compromised agent from leaking files upstream. Defence-in-depth matters; the bullets below are ordered from most-common footgun to least.

```bash
# Minimum hygiene check after any restore or migration
stat -c '%a %n' memory/ .learnings/ qmd.config.json | awk '$1 != 700 && $2 ~ /memory|learnings/ {print "WARN: " $0}'
```

- **Never log secrets** — API keys, tokens, passwords, OAuth refresh tokens, session tokens, bearer tokens, signed URLs, or any credentials must never be written to `memory/`, `.learnings/`, or any file that QMD will index. Daily logs are plain Markdown with no access control; assume anything written there leaks.
- **Credentials belong in a vault, not in memory** — store all credentials (API keys, service tokens, database passwords) in `1Password`, `pass`, or an environment manager. The memory stack records *that* a credential was rotated, never *what* its value is.
- **Treat memory files as shared within your team** — QMD semantic indexing and NotebookLM sync both copy content to downstream systems without additional authentication or authorization checks. If something should not end up in a second-brain synthesis, do not log it.
- **Use trash instead of `rm`** — prefer `trash-put` (from `trash-cli`) for recoverable deletions. Daily logs are chronological evidence of decisions; an accidental delete is hard to reverse.
- **Back up `MEMORY.md`** before any bulk edit or promotion run — `cp memory/MEMORY.md memory/MEMORY.md.bak.$(date +%s)`.
- **Test `auto-promote-memory.sh` on a copy first** — run it against a scratch `memory/` directory before pointing it at your real workspace. The script mutates `MEMORY.md` in place.
- **Sanitize before sync** — if the NotebookLM layer is enabled, audit `sync-to-notebooklm.sh` for which files it ships, and exclude any path that may contain secrets, API keys, credentials, tokens, or sensitive PII.
- **NotebookLM sync transmits files to Google's cloud infrastructure** — when `sync-to-notebooklm.sh` runs, the matched workspace files are uploaded over the internet to Google's NotebookLM service and processed under [Google's privacy policy](https://policies.google.com/privacy). Your daily logs, long-term memory, and any other documents that match the sync glob leave your local environment permanently. Only enable this layer after reviewing which files will be uploaded and confirming you are comfortable with Google's data handling terms. Do not sync files containing secrets, PII, credentials, confidential project details, or any data subject to data-residency requirements.

### Authentication and authorization

Each layer of the stack has its own authentication story. Know which credential goes where before you enable sync.

- **NotebookLM auth** — the sync script authenticates via Google OAuth using `notebooklm login`. The refresh token is stored in `~/.config/notebooklm/` with `0600` permissions. Rotate credentials every 90 days and revoke the OAuth grant at [myaccount.google.com](https://myaccount.google.com/permissions) when decommissioning an agent.
- **QMD has no authentication layer** — QMD runs locally and reads the filesystem with your UNIX user's permissions. If you need authorization boundaries (e.g. multi-tenant workspaces), run each tenant's QMD in a separate UNIX account.
- **LCM tokens** — the Lossless Claw extension inherits the agent's own API key and does not require a separate credential. Never share your LCM session tokens across agents.
- **File permissions** — the setup script applies `chmod 0700` to `memory/` and `.learnings/` so other local users cannot read your notes. Re-check with `stat memory/` after any backup-restore operation.

Verify the auth state of each layer before a long sync run, e.g.:

```bash
# NotebookLM OAuth token still valid?
notebooklm whoami || notebooklm login

# QMD has filesystem access to every collection path?
qmd collection list | awk '{print $2}' | xargs -I{} test -r {} && echo "OK: QMD paths readable"

# LCM authenticated?
/lossless | head -1
```

If any of the three checks fail, resolve the credential / authorization issue before running the sync — a partial sync can leave the NotebookLM mirror in an inconsistent state.

### Input validation and sanitization

- Every script validates its inputs at start. `setup.sh` validates that `WORKSPACE_DIR` resolves to a writable directory; `backlinks.py` validates that the provided path exists and is a directory; `auto-promote-memory.sh` validates that the recurrence threshold is a non-negative integer.
- `sync-to-notebooklm.sh` performs input sanitization on the notebook ID (UUID format validation) and refuses to run if `NOTEBOOK_ID` still equals the sentinel `{NOTEBOOK_ID}`. This input check prevents leaking files to an unintended notebook.
- Never trust file contents during promotion: `auto-promote-memory.sh` escapes Markdown control characters so a malicious learning entry cannot inject headings or code fences into `MEMORY.md`.
- When piping user-supplied query strings into `qmd query` or `backlinks.py query`, quote arguments and validate they contain no shell metacharacters; the scripts escape internally but defence-in-depth matters.

For example, the UUID validation in `sync-to-notebooklm.sh` looks roughly like:

```bash
case "$NOTEBOOK_ID" in
  "{NOTEBOOK_ID}"|"")
    echo "[ERROR] NOTEBOOK_ID unset" && exit 1 ;;
  [0-9a-f]*-[0-9a-f]*-*-*-*)
    : ;;   # shape check only
  *)
    echo "[ERROR] NOTEBOOK_ID not UUID-like" && exit 1 ;;
esac
```

The check is intentionally shape-only; full UUID parsing happens upstream at the NotebookLM API boundary.

### Rate limiting and throttling

Every layer that makes network calls honours an upstream rate limit. The kit implements client-side throttling so you cannot accidentally exceed it.

- **QMD reindex** — the smart reindex script throttles itself to one full rebuild per collection per 24h unless content hashes change, preventing cron loops from hammering the embedding model.
- **NotebookLM sync** — `sync-to-notebooklm.sh` rate-limits source uploads at a maximum of one per 2 seconds. Exceeding NotebookLM's upload throttling limit triggers an exponential backoff (max 4 retries).
- **Cron spacing** — the recommended cron entries are staggered (promotion at 08:30, sync at 03:00, daily check at 22:00) so no single hour throttles QMD or the LLM reranker.
- Never disable rate-limit backoff to "speed up" a sync. The upstream service enforces its own rate limits and repeated violations revoke the credential.

Observed rate limits (as of the latest sync pass), e.g.:

```
NotebookLM uploads:  30 sources / hour / notebook
QMD embedding API:   60 requests / minute (provider-dependent)
LCM compaction:      unmetered locally; shares the agent's model quota
```

If you hit a throttle, the scripts log an explicit `[WARN] rate-limit backoff: sleeping Xs`. Treat that as signal, not noise — if the warning appears every run, your cron cadence is too aggressive.

### Threat model and mitigation

Threats are ordered from most-likely to least-likely and paired with concrete mitigations. For example, the single most common incident is a secret accidentally landing in a daily log — a pre-commit tripwire handles it.

| Threat | Mitigation |
|--------|------------|
| Secret accidentally committed to `memory/*.md` | Pre-commit hook runs `detect-secrets` + tripwire regex for API-key / token / password patterns |
| Compromised NotebookLM OAuth token | Revoke at Google Account Permissions, remove `~/.config/notebooklm/`, then re-authenticate |
| Malicious learning triggers code execution via promotion | Promotion script validates + escapes; never `eval`s any field |
| Workspace backup leaks sensitive daily logs | Encrypt backups (`age`, `gpg`) and apply least-privilege authorization on the backup bucket |
| Unauthorized local user reads `memory/` | Directory permissions set to `0700` at setup; audit with `find memory/ -not -perm 700` |

---

## Verification

After running `scripts/setup.sh`, confirm the stack is healthy:

```bash
# 1. Directory structure exists
test -d "$WORKSPACE_DIR/memory" && \
test -d "$WORKSPACE_DIR/.learnings" && echo "OK: dirs"

# 2. Today's daily log exists
test -f "$WORKSPACE_DIR/memory/$(date +%Y-%m-%d).md" && echo "OK: today's log"

# 3. QMD collections are registered and indexed
(cd "$WORKSPACE_DIR" && qmd status)        # expect non-zero doc counts

# 4. Backlinks index builds cleanly
(cd "$WORKSPACE_DIR" && python3 scripts/backlinks.py build)

# 5. LCM responds (optional layer)
/lossless                                  # expect a summary count

# 6. NotebookLM sync dry-run (only if NOTEBOOK_ID is set)
bash scripts/sync-to-notebooklm.sh --dry-run 2>/dev/null || \
  echo "skipping — NotebookLM not configured"
```

All six checks passing = stack is ready for daily use.

---

## Troubleshooting

Five diagnostic playbooks covering the most common failure modes: missing conversations, stale QMD results, NotebookLM sync gaps, empty backlinks indexes, and broken promotion runs. Each playbook is ordered from cheapest-to-check to most invasive — run the earlier steps before the later ones. For example, always run `/lossless` or `qmd status` before running a full reindex; most "staleness" reports are actually an LCM gap.

Quick diagnostic index:

| Symptom | Jump to |
|---------|---------|
| Agent says "I don't remember X" even though it happened | "I can't find that conversation we had" |
| `qmd query` returns outdated or empty matches | "QMD returns stale results" |
| NotebookLM chat is missing a recent source | "NotebookLM doesn't have my latest memory" |
| `backlinks.py` returns zero matches | "Backlinks index is empty" |
| `auto-promote-memory.sh` finishes but `MEMORY.md` is unchanged | "Memory promotion isn't working" |

- Always capture the exact command you ran and the observed vs. expected output before filing an issue.
- Most failures are resolved at step 1 or 2 of a playbook; escalating further without reading the earlier steps wastes time.

### "I can't find that conversation we had"

Most recall misses fall into three buckets: the exchange was never captured in LCM, it was captured but the search term is too specific, or the summary exists but the agent needs the raw detail.

1. **Check LCM is alive**: `/lossless` — verify summary count > 0. If the count is zero, the lossless-claw extension is not running. See its own README for restart steps.
2. **Grep the full text**: `lcm_grep(pattern="key term", mode="full_text")`. Try synonyms and shorter stems; LCM indexes the compacted summaries, not the raw transcript.
3. **Describe a specific summary**: `lcm_describe(id="sum_xxx")` to inspect a candidate before expanding.
4. **Escalate with expand**: `lcm_expand_query(query="key term", prompt="What was decided?")` — this pulls the full context behind the match.
5. **Fall back to Markdown**: `grep -r "term" memory/ | head -20` — the daily logs themselves are searchable even when LCM can't find it.

**Expected output** of a healthy `/lossless`, e.g.:

```
Summaries: 42
Last compaction: 2026-04-15 09:14 UTC
```

If you see `command not found`, LCM is not installed. For example, check with `which lcm_grep` — an empty result confirms the extension isn't on PATH.

### "QMD returns stale results"

QMD staleness is usually one of: the index was never built, the collection config points at the wrong path, or content changed but the smart reindex was skipped.

1. **Check last update timestamp**: `qmd status` — look for the "last indexed" column on each collection.
2. **Force reindex**: `npx qmd update` — rebuilds all collections from scratch. Expect 10–60 s for a normal-sized workspace.
3. **Verify collection paths**: `qmd collection list` — confirm each collection's path still exists and contains Markdown.
4. **Inspect the config**: `cat qmd.config.json` — the `mask` glob must match the files you expect indexed.
5. **Reset the index** if it's genuinely corrupted: move `.qmd/` aside (`mv .qmd .qmd.bak`) and then run `npx qmd update` to rebuild from scratch. Delete the backup only after verifying the new index works.

**Expected output** after a successful reindex, e.g.:

```
Indexed 142 documents across 4 collections in 18.3s
  memory:    57 docs
  skills:    23 docs
  docs:      41 docs
  workspace: 21 docs
```

Zero documents means your mask is wrong. For example, a mask of `*.md` at the collection root will miss files in subdirectories — use `**/*.md` instead.

### "NotebookLM doesn't have my latest memory"

The sync is driven by `src/sync-to-notebooklm.sh` and requires a valid OAuth token plus a real `NOTEBOOK_ID`. Most gaps are auth or config issues.

1. **Verify the notebook ID is real**: `echo "$NOTEBOOK_ID"` — it must not equal `{NOTEBOOK_ID}`. The sentinel value short-circuits the script.
2. **Run the manual sync**: `bash scripts/sync-to-notebooklm.sh 2>&1 | tee /tmp/nlm-sync.log` — capture the output.
3. **Check auth**: `notebooklm whoami` — re-run `notebooklm login` if the token has expired or was revoked.
4. **Look for rate-limit warnings**: `grep -i "rate\|throttl\|429" /tmp/nlm-sync.log` — back off and retry on a non-throttled minute.
5. **Confirm in the UI**: open the notebook at [notebooklm.google.com](https://notebooklm.google.com) and verify the source list — sometimes a source is uploaded but NotebookLM hasn't finished its own ingestion pass yet (can take 1–2 minutes).

**Expected output** of a successful sync ends with, e.g.:

```
[INFO] Sync complete: 3 synced, 0 skipped, 0 errors
[INFO] Notebook: https://notebooklm.google.com/notebook/<id>
```

A line like `0 synced, 3 skipped, 0 errors` means the files were unchanged since the last sync — that's normal, not a failure.

### "Backlinks index is empty"

An empty index usually means the builder hasn't run since files were added, or the wikilink syntax in the daily logs isn't the expected `[[Entity]]` form.

1. **Build the index**: `python3 scripts/backlinks.py build` — outputs `Indexed N files, M unique entities`.
2. **Verify memory files exist**: `ls memory/*.md | wc -l` — if this is 0, the kit was never bootstrapped. Re-run `setup.sh`.
3. **Grep for wikilinks**: `grep -r "\[\[" memory/ | head -10` — zero hits means your daily logs aren't using the expected syntax.
4. **Inspect the raw index**: `python3 -m json.tool .backlinks.json | head -40` to see what the builder actually captured.
5. **Force a full rebuild**: move `.backlinks.json` aside (`mv .backlinks.json .backlinks.json.bak`) then run `python3 scripts/backlinks.py build` to regenerate it.

**Expected output** of `backlinks.py query "Name"` on a healthy index, e.g.:

```
Found 2 matches for 'Name':
  [[Name]] — mentioned in 3 file(s)
    - memory/2026-04-10.md:  "Met with [[Name]] about the roadmap"
    - memory/2026-04-01.md
    - memory/MEMORY.md
```

Empty output usually means the wikilink spelling differs from the query — try `backlinks.py patterns | grep -i name` to see what's actually indexed.

### "Memory promotion isn't working"

Promotion only lifts items that meet the recurrence threshold, have an explicit `PROMOTE` marker, or live in `memory/pending-promotion.md`. Silent no-ops usually mean none of those criteria were met.

1. **Check recurrence counts**: `grep "Recurrence-Count" .learnings/LEARNINGS.md | sort | uniq -c` — you need entries with count ≥ 3 (default threshold).
2. **Inspect pending candidates**: `cat memory/pending-promotion.md` — items here are promoted on the next run.
3. **Run the script verbosely**: `PROMOTE_DEBUG=1 bash scripts/auto-promote-memory.sh` to see the selection logic.
4. **Verify exit code**: run `bash scripts/auto-promote-memory.sh` and then `echo "exit=$?"` — exit code `2` means "nothing to do", which is correct when no items met the criteria.
5. **Lower the threshold temporarily**: `PROMOTE_RECURRENCE=2 bash scripts/auto-promote-memory.sh` — useful for testing.

**Expected output** when items are promoted, e.g.:

```
[INFO] Starting memory promotion pass...
[INFO] Promoting learning (recurrence=4): Always verify notebook ID before sync
[INFO] Promoting pending item: Q2 planning canceled — scope cut
[INFO] Promotion pass complete: 2 items promoted
[INFO] MEMORY.md updated. Consider running: npx qmd update --collection memory
```

A completed-but-silent run (exit code `2`) means nothing met the threshold — that's normal, not a failure.

---

## Maintenance Cadence

Staggered schedules so no single cron hour hits the same upstream service twice — for example, NotebookLM sync runs at 03:00 while QMD smart reindex runs during the weekly workflow, not the daily one.

| Frequency | Task |
|-----------|------|
| Every session | Write daily log entry |
| Every few days | Review daily logs, promote to MEMORY.md |
| Weekly | Run health checks |
| Monthly | Archive daily logs >30 days to `memory/archive/` |
| Mon/Thu 08:30 | Self-reflection + memory promotion (cron) |
| Daily 03:00 | NotebookLM sync (cron, if using) |
| Daily 22:00 | Daily memory log check (cron) |

---

## References

Canonical documents that explain the broader memory operating model this kit slots into. For example, `MEMORY_FRAMEWORK.md` defines *what* gets captured and *why*, while this kit is the *how*.

- **MEMORY_FRAMEWORK.md** — Full memory operating model
- **memory/memory-write-policy.md** — What to capture and how
- **HEARTBEAT.md** — Follow-up and check-in system
- **LCM config** — `~/.claude/extensions/lossless-claw/skills/lossless-claw/references/config.md`
- **LCM recall tools** — `~/.claude/extensions/lossless-claw/skills/lossless-claw/references/recall-tools.md`
- **NotebookLM MCP** — official setup at https://notebooklm.google.com + the MCP server of your choice (e.g. `notebooklm-py`)

---

*Version 1.0.0 | Author: giorgio | Last updated: 2026-04-16*
---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit, ask the user whether they agree to you submitting an outcome report. Only report whether it worked if they explicitly agree. It really helps us improve the kits.

```
POST https://journeykits.ai/api/kits/giorgio/memory-stack-integration/outcome
Content-Type: application/json
Authorization: Bearer <your-api-key>

{
  "ref": "v1.3.0",
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
POST https://journeykits.ai/api/kits/giorgio/memory-stack-integration/outcome
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
    "attemptId": "attempt_03d1539e-be60-4b21-9231-cc781cd11a50",
    "reportToken": "atr_087df655872574c9b188bb6d330653540b5bea81581f44a2"
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
    "slug": "memory-stack-integration",
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
    "attemptId": "attempt_03d1539e-be60-4b21-9231-cc781cd11a50",
    "feedbackToken": "atr_087df655872574c9b188bb6d330653540b5bea81581f44a2"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/giorgio/memory-stack-integration/learnings
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
  "attemptId": "attempt_03d1539e-be60-4b21-9231-cc781cd11a50",
  "feedbackToken": "atr_087df655872574c9b188bb6d330653540b5bea81581f44a2"
}
```

This feedback token expires at `2026-05-22T02:53:39.919Z`. Max submissions for this install: 1.

---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/giorgio/memory-stack-integration/outcome
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
    "attemptId": "attempt_aa488a43-afa0-4e4c-9401-9fd7450e56de",
    "reportToken": "atr_9c86e0b088101ad7b4391a32cfe643f95f948c04af5b9873"
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
    "slug": "memory-stack-integration",
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
    "attemptId": "attempt_aa488a43-afa0-4e4c-9401-9fd7450e56de",
    "feedbackToken": "atr_9c86e0b088101ad7b4391a32cfe643f95f948c04af5b9873"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/giorgio/memory-stack-integration/learnings
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
  "attemptId": "attempt_aa488a43-afa0-4e4c-9401-9fd7450e56de",
  "feedbackToken": "atr_9c86e0b088101ad7b4391a32cfe643f95f948c04af5b9873"
}
```

This feedback token expires at `2026-05-22T12:43:14.146Z`. Max submissions for this install: 1.
