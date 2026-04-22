# SKILL: self-improve-loop

Use this skill to operate the Self-Improve Harness and interpret its state.

## Use this when

- the user asks what the harness changed
- the user asks why a target was rejected or locked
- the user wants to run one cycle manually
- the user wants to inspect queue, state, or pending approvals
- the user wants to check harness health or detect stale locks
- the user wants to approve or reject pending proposals
- the user wants to reconcile queue drift from manifest
- the user wants to roll back applied changes
- the user wants help wiring a proposer or scorer into the starter kit
- the user wants to clean up old rollback dirs or logs

## Runtime paths

- Harness base: `~/.self-improve-harness/`
- Config: `~/.self-improve-harness/config/integration.yaml`
- Manifest: `~/.self-improve-harness/manifest.json`
- State: `~/.self-improve-harness/data/loop-state.json`
- Queue: `~/.self-improve-harness/data/loop-queue.json`
- Approval queue: `~/.self-improve-harness/data/approval-queue.json`
- Logs: `~/.self-improve-harness/logs/harness.log`

## Commands

```bash
# Core operations
python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py run --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml --dry-run

# Inspection
python3 ~/.self-improve-harness/src/loop-orchestrator.py queue --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py state --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py approvals --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py health --config ~/.self-improve-harness/config/integration.yaml

# Approval and rejection
python3 ~/.self-improve-harness/src/loop-orchestrator.py approve --id <id> --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py reject --id <id> --config ~/.self-improve-harness/config/integration.yaml

# Reconciliation and rollback
python3 ~/.self-improve-harness/src/loop-orchestrator.py reconcile --manifest ~/.self-improve-harness/manifest.json --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py rollback --id <id> --config ~/.self-improve-harness/config/integration.yaml
python3 ~/.self-improve-harness/src/loop-orchestrator.py rollbacks --config ~/.self-improve-harness/config/integration.yaml

# Maintenance
python3 ~/.self-improve-harness/scripts/retain.py --config ~/.self-improve-harness/config/integration.yaml --dry-run
```

## Result meanings

- `applied`: a proposal passed validation and was written
- `apply_failed`: a write was attempted and failed, with rollback logged
- `rejected`: validation blocked the proposal
- `pending_approval`: the proposal was queued for human review
- `no_proposal`: the cycle ran but the proposer returned nothing
- `quiet_hours`: the run was skipped by configured quiet hours
- `idle`: nothing actionable remained in queue
- `locked`: a concurrent run is in progress or a stale lock was detected

## Exit codes

- `0`: success; at least one target processed successfully
- `1`: fatal error
- `2`: skipped due to quiet hours
- `3`: idle, nothing actionable in queue
- `4`: every processed target was rejected or failed to apply
- `5`: locked due to concurrent run or stale lock detection

## Notes

- This starter does not ship a real proposer. `proposer.command` is the primary extension point.
- `scorer.command` is optional, but the built-in scorer is weak and should not be trusted for serious lock policy.
- Approval queue persistence is local JSON, not a UI workflow.
- Sensitive files should stay manual-review only.
- The `delta` field is a word-count heuristic, not a model quality score.
- Use `health` command to diagnose lock state and stale locks before troubleshooting.
- Use `reconcile` command if queue and manifest drift apart.
- Use `rollback` command to restore previous versions from rollback backups.
- Notifications are placeholders only; add your own notification path.
