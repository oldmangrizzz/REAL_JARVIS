# Phase 5 — End-to-End Voice→Intent→n8n→HA Wiring

**Status**: COMPLETE
**Tests**: 592 passing, 1 skipped, 0 failures (baseline was 583; +9 new)

## What shipped

### Code
- `Jarvis/Sources/JarvisCore/Interface/DisplayCommandExecutor.swift`
  - Added optional `n8nBridge: N8NBridge?` init param (backward-compatible default `nil`).
  - Replaced the `routeToHomeKit` stub with a real N8NBridge dispatch that posts
    `{domain, service, entity_id, data}` against the `ha-call-service` webhook.
  - Added pure helpers `mapHomeKitToHA(accessory:characteristic:value:) -> HAMapping`
    and `haEntityID(for:)` with room-group heuristics (downstairs/upstairs/all lights)
    and a slugifier fallback.
  - Fallback preserved: when no bridge is injected, executor returns a `success: true`
    result with spokenText containing `"queued"`.
- `Jarvis/Sources/JarvisCore/Interface/RealJarvisInterface.swift`
  - Composition root now reads `JARVIS_N8N_BASE_URL`, `JARVIS_N8N_USER`,
    `JARVIS_N8N_PASSWORD` from env via `makeN8NBridge()` and injects the bridge
    into `DisplayCommandExecutor`. Absence of the env var = graceful fallback.

### Tests
- `Jarvis/Tests/JarvisCoreTests/DisplayCommandExecutorHAMappingTests.swift` (9 tests)
  - Pure mapping: on/off/brightness (+ clamp), default characteristic fallback.
  - Entity ID resolution: explicit id pass-through, room-group heuristics,
    freeform slugify, nil for unknown/empty.
  - Wire-through: live call through a mock N8NTransport asserts webhook path +
    JSON payload shape.
  - Fallback: executor without bridge returns "queued" stub (auth + routing
    still works).

## Runtime env expected
```
JARVIS_N8N_BASE_URL=http://192.168.4.119:5678
JARVIS_N8N_USER=jarvis
JARVIS_N8N_PASSWORD=<from n8n.env>
```
(Credentials already live in `~/.copilot/session-state/.../files/n8n.env`.)

## Operator-side gates (out of repo)
1. Import `n8n/workflows/ha-call-service.json` into the n8n UI.
2. Create the `ha-bearer` credential in n8n with the HA long-lived token.
3. Activate the workflow.
4. Optional: seed CapabilityRegistry with `group.downstairs_lights`,
   `group.upstairs_lights`, `group.all_lights` for smoother intent parsing
   of generic phrases.

## Next: Phase 6 — hardening + zero-TODO sweep.
