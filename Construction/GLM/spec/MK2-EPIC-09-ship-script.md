# MK2-EPIC-09 — One-Command Deploy + Smoke Suite

**Lane:** GLM (infra)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** MK2-EPIC-01, MK2-EPIC-02, MK2-EPIC-05, MK2-EPIC-06
**Priority:** P0
**Canon sensitivity:** LOW

---

## Why

Mark II ship is declared ONLY when `scripts/ship-mark-ii.sh` produces green on every target + every smoke test + every service redeploy, and posts a single completion artifact. No manual step-dance.

## Scope

### In

1. **Unified smoke runner** `scripts/smoke/all.sh`:
   - Runs, in order, exiting non-zero on first failure:
     - `build-all.sh` (EPIC-01)
     - `carplay-entitlement.sh` (EPIC-06)
     - `nav-happy-path.sh` (EPIC-06)
     - `voice-loop.sh` (EPIC-05)
     - `arc-submit.sh` (EPIC-03)
     - `destructive-confirm-ui.sh` (EPIC-02)
     - `xcodebuild test -workspace jarvis.xcworkspace -scheme all` (EPIC-01, tests)
   - Writes summary to `Storage/mark-ii/last-smoke.json` with per-step ms + pass/fail.

2. **Ship script** `scripts/ship-mark-ii.sh`:
   - Preflight: ensures `git status` clean, branch is `main`, HEAD is signed (EPIC-08 sig gate).
   - Runs `scripts/smoke/all.sh`; aborts on any red.
   - Code-signs + notarizes macOS app (using operator-local Developer ID). Uses existing `scripts/sign/...` if present; else emits a spec-stop requesting operator setup.
   - Deploys F5-TTS service: `services/f5-tts/deploy/gcp-up.sh` (idempotent).
   - Syncs PWA: `rsync` to `grizzlymedicine.icu` static path (creds via `~/.jarvis/deploy-env`).
   - Reloads LaunchAgents: `launchctl bootout … && launchctl bootstrap …` for `com.grizz.jarvis.tts.watchdog` and `com.grizzlymedicine.jarvis-ntfy-bridge` (the operator's ntfy→imsg bridge).
   - Posts completion artifact to Convex `ships:record` with `{version: "MarkII-1.0.0", gitSha, timestamp, smokeSummary, operator}`.
   - Emits iMessage: `MK II shipped — <gitSha> — all smoke green`.

3. **Rollback**: `scripts/ship-mark-ii.sh --rollback <previous-git-sha>`:
   - Force-checkout previous sha locally, re-deploys PWA, re-deploys TTS image with previous tag, restores LaunchAgents.
   - Posts `ships:rollback` to Convex, iMessage `MK II rolled back to <sha>`.

### Out

- Do NOT store Developer ID private keys in the repo. Operator keychain is the source.
- Do NOT run `ship-mark-ii.sh` from the Forge itself — this is an **operator-invoked** command (requires Touch ID, keychain unlock, interactive). Ralph/Forge halts when it reaches this script and escalates via iMessage.

## Acceptance Criteria

- [ ] `scripts/smoke/all.sh` runs on operator machine and exits 0 after all prior EPICs land.
- [ ] `scripts/ship-mark-ii.sh --dry-run` prints the planned actions without executing.
- [ ] Rollback path tested with two successive dry runs.
- [ ] iMessage notification arrives on real run.
- [ ] Convex `ships:record` mutation validates strictly (required fields only).

## Invariants

- Ship is binary: all-green or not-shipped.
- No post-ship mutation of canon without EPIC-08's sig gate.

## Artifacts

- New: `scripts/smoke/all.sh`, `scripts/ship-mark-ii.sh`, `convex/ships.ts`, `Storage/mark-ii/.gitkeep`.
- Response: `Construction/GLM/response/MK2-EPIC-09.md`.
