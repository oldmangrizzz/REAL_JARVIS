# Phase 4 Complete — Jarvis Mind Closeout

**Date**: 2026-04-21
**Commit**: `cf5cc66`
**Status**: ✅ Complete

## What Shipped

### ConversationEngine turn-state wiring (6 TODO sites closed)
- Route update from AmbientAudioFrame.routeHint on ingest.
- `activeTurnID` tracked across transitions.
- `beginTurn` + `defer endTurn` guarantees teardown on throw/cancel in `runTurn`.
- `resetBargeInCount` on new turn; `incrementBargeIn` in `handleBargeIn`.
- `finalizeTurn` emits session.bargeInCount + currentRoute.rawValue into TurnRecord.

### ConversationSession state foundation
- `activeTurnID: UUID?`
- `bargeInCount: Int`
- `currentRoute: AmbientGatewayRoute`
- Methods: `beginTurn(_:)`, `endTurn()`, `incrementBargeIn()`, `resetBargeInCount()`, `updateRoute(_:)`.
- `@unchecked Sendable` — engine owns ordering queue.

### XTTS canon preset
- `TTSRenderParameters.xttsLocked` (temp 0.7, topP 0.85).
- `vibevoiceLocked` marked DEPRECATED but retained (env-var fallback in VoiceSynthesis.swift:189-190).

### Pre-existing breakage fixed (unblocker)
- `TunnelAuthTests.testTamperedTokenMACRejected` — Swift 6 required explicit `Character` cast on ternary.

### Ops: iMessage flood killed
- `com.grizz.jarvis.pulse-subscriber` LaunchAgent disabled (plist → `.disabled`).
- All orphan `jarvis-say` / `pulse-subscriber.sh` processes killed.
- Root cause: `~/.jarvis/pulse-subscriber.sh` spawned unbounded jarvis-say per STUCK pulse event.
- **DO NOT re-enable** without fixing spawn logic.

## Verification
- `xcodebuild build -scheme Jarvis`: **BUILD SUCCEEDED**.
- `xcodebuild test -scheme Jarvis`: **575 passed / 1 skipped / 0 failed**.

## Next
Phase 3 — n8n↔HA bridge.
