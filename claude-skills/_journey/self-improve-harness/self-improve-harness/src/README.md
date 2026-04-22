# Self-Improve Harness

A small starter kit for recurring self-improvement over agent skills, docs, prompts, and config files.

It ships a real orchestrator, real persistence, real audit logs, and a manual approval queue. It does not claim to ship a magical proposer. You plug that in.

## What ships

```text
self-improve-harness/
├── AUDIT-code.md
├── AUDIT-architecture.md
├── kit.md
├── README.md
├── LICENSE
├── requirements.txt
└── .gitignore
├── config/
│   ├── integration.example.yaml
│   └── manifest.example.json
├── proposals/
│   └── proposer.example.py
├── scorers/
│   └── scorer.example.py
├── scripts/
│   └── retain.py
├── skills/
│   └── self-improve-loop.md
└── src/
    └── loop-orchestrator.py
```

## What works out of the box

- manifest loading and validation
- runtime bootstrap command
- queue and state persistence
- score history logging
- validation logging
- apply logging
- manual approval queue persistence
- quiet-hours gating
- regression lockouts
- plateau lockouts
- atomic writes with rollback copies
- dry-run mode
- command-based proposer hook
- command-based scorer hook
- differentiated exit codes for automation
- approval expiry purge
- fcntl-based concurrent-run lockfile with stale lock detection
- retention utility for rollback dirs and JSONL logs

## What you still need to provide

- a real proposal generator command
- an optional real scorer command if you want better lock decisions
- any outbound notification path you want
- any sandbox or test execution beyond the included file validation

## Quick start

```bash
# 1. Copy the kit
cp -r self-improve-harness ~/.self-improve-harness

# 2. Install dependency
python3 -m pip install -r ~/.self-improve-harness/requirements.txt

# 3. Create runtime files
cp ~/.self-improve-harness/config/integration.example.yaml ~/.self-improve-harness/config/integration.yaml
cp ~/.self-improve-harness/config/manifest.example.json ~/.self-improve-harness/manifest.json

# 4. Point proposer.command at your generator, or leave blank for dry-run-only mode
# Example:
# proposer:
#   command: "python3 ~/.self-improve-harness/proposals/proposer.example.py"

# 5. Bootstrap directories and queue files
python3 ~/.self-improve-harness/src/loop-orchestrator.py bootstrap --config ~/.self-improve-harness/config/integration.yaml

# 6. Edit ~/.self-improve-harness/manifest.json with real targets

# 7. Run a dry run first
python3 ~/.self-improve-harness/src/loop-orchestrator.py run \
  --manifest ~/.self-improve-harness/manifest.json \
  --config ~/.self-improve-harness/config/integration.yaml \
  --dry-run

# 8. Register cron after dry run looks clean
0 7,11,15,19 * * * /usr/bin/python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml >> ~/.self-improve-harness/logs/harness.log 2>&1
```

## Proposer contract

If `proposer.command` is set, the orchestrator:

- sends current file content on stdin
- sets `TARGET_PATH`, `TARGET_TYPE`, `TARGET_CATEGORY`, and `TARGET_NAME`
- expects the full replacement file content on stdout
- treats non-zero exit as no proposal

See `proposals/proposer.example.py` for a starter adapter.

## Scorer contract

If `scorer.command` is set, the orchestrator:

- sends current file content on stdin
- sets `TARGET_PATH`
- expects a single float from `0.0` to `1.0` on stdout
- falls back to the built-in heuristic if the command fails or is unset

See `scorers/scorer.example.py` for the scoring contract.

Use a real scorer if you want plateau and regression locks to mean anything.

## Validation

Three-layer validation prevents broken proposals from being applied:

1. **Syntax validation**: JSON, YAML, and Python files are validated with compile() or parsers before application.
2. **Content size guards**: Proposals must stay within 3x max and 10% min bounds relative to original, with 4x/0.25x tighter validation on application.
3. **Security patterns**: Dangerous proposal patterns (shell injection, credential exposure) are flagged during validation.

## CLI commands

```bash
# Core operations
python3 src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml --dry-run
python3 src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py bootstrap --config ~/.self-improve-harness/config/integration.yaml

# Inspection
python3 src/loop-orchestrator.py queue --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py state --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py approvals --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py health --config ~/.self-improve-harness/config/integration.yaml

# Approval and rejection
python3 src/loop-orchestrator.py approve --id <id> --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py reject --id <id> --config ~/.self-improve-harness/config/integration.yaml

# Reconciliation and rollback
python3 src/loop-orchestrator.py reconcile --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py rollback --id <id> --config ~/.self-improve-harness/config/integration.yaml
python3 src/loop-orchestrator.py rollbacks --config ~/.self-improve-harness/config/integration.yaml

# Maintenance
python3 scripts/retain.py --config ~/.self-improve-harness/config/integration.yaml --dry-run
```

## Exit codes

These are intended for cron, wrappers, and health checks:

- `0`: at least one target processed successfully
- `1`: fatal error
- `2`: skipped due to quiet hours
- `3`: idle, nothing actionable in queue
- `4`: every processed target was rejected or failed to apply
- `5`: locked due to concurrent run or stale lock detection

## Runtime files

After bootstrap and your first run, expect these under `~/.self-improve-harness/`:

- `logs/harness.log`
- `data/loop-state.json`
- `data/loop-queue.json`
- `data/approval-queue.json`
- `data/scores.jsonl`
- `data/proposals.jsonl`
- `data/validation-log.jsonl`
- `data/apply-log.jsonl`
- `data/rollback/`
- `data/archive/` after running retention

## Approval model

A target enters the approval queue when either of these is true:

- the manifest sets `auto_approve: false`
- the path matches one of the `validator.require_manual_approval` rules

Queued approvals are persisted to `approval-queue.json`, expire automatically, and are purged from the queue on later runs.

## Honest limitations

- No real improvements happen until you wire in a proposer command.
- Validation is intentionally file-focused. It is not a full sandbox runner.
- Plateau and regression locking rely on score quality. Weak scoring gives weak locks.
- The `delta` value is a rough word-count heuristic, not a quality metric.

## Good first extensions

1. Replace `proposer.command` with your model or agent adapter.
2. Replace `scorer.command` with a real evaluator.
3. Add a wrapper that sends notifications on `applied`, `pending_approval`, `idle`, and `lock` events.
4. Add a smoke test suite around bootstrap, dry-run, approval expiry, and retention.
5. Add metrics collection for queue depth, approval rate, and rejection rate.

## Audit notes

- `AUDIT-code.md` covers correctness and bug fixes in the shipped orchestrator.
- `AUDIT-architecture.md` covers architecture, extension points, operational gaps, and recommended next refactors.
