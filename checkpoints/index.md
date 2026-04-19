# Checkpoints Index

Chronological log of build segments. Each checkpoint is a self-contained
recap with verification steps for cold resume.

| # | File | Title | Status |
|---|------|-------|--------|
| 012 | [012-voice-approval-gate-flipped.md](./012-voice-approval-gate-flipped.md) | Voice Approval Gate Flipped Green | ✅ LOCKED |
| 013 | [013-finish-build-cockpit-telemetry-hardening.md](./013-finish-build-cockpit-telemetry-hardening.md) | Build Finished: Cockpit, Telemetry & Hardening | ✅ COMPLETE |
| 014 | [014-intelligence-report-integration.md](./014-intelligence-report-integration.md) | Intelligence Report Integration & Canon Archive | ✅ COMPLETE |

## Conventions

- Checkpoints are append-only. To correct a prior checkpoint, write a new
  one that supersedes it and note the relationship at the top.
- Every checkpoint must include: TL;DR, locked artifacts with hashes,
  modified files, OPSEC notes, "how to resume cold" runbook.
- The gate file (`.jarvis/voice/approval.json`) is the runtime source of
  truth; checkpoints are the human-readable scaffolding around it.
