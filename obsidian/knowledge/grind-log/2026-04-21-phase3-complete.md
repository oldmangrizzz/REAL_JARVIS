# Phase 3 — n8n Workflow Library Complete

**Date**: 2026-04-21
**Phase**: 3 — Jarvis's Hands
**Status**: ✅ Complete

## Deliverables

### Swift client (`Jarvis/Sources/JarvisCore/Integrations/N8NBridge.swift`)
- `N8NTransport` protocol (URLSession-backed default)
- `N8NBridgeError` enum
- `N8NBridge.runWorkflow(webhookPath:payload:timeout:)` — async, strips leading slash, optional basic auth
- 8 unit tests green (mock transport)

### Seed workflows (`n8n/workflows/`)
| Workflow | Trigger | Effect |
|---|---|---|
| `ha-call-service.json` | Webhook `jarvis/ha/call-service` | Generic HA service dispatcher |
| `scene-downstairs-on.json` | Webhook `jarvis/scene/downstairs-on` | `light.turn_on group.downstairs_lights` |
| `scene-upstairs-on.json` | Webhook `jarvis/scene/upstairs-on` | `light.turn_on group.upstairs_lights` |
| `forge-self-heal.json` | Schedule (10 min) | Probe forge healthz, ntfy on failure |

### Test baseline
- 583 tests, 1 skipped, 0 failures (was 575 pre-phase)
- Full suite: 21s

## Operator actions (manual, one-time)
1. n8n UI → Credentials → HTTP Header Auth, name `Home Assistant Bearer`, value `Bearer <HA token>`
2. Import four JSON files from `n8n/workflows/`
3. Activate each
4. Add `group.downstairs_lights` + `group.upstairs_lights` to HA `configuration.yaml`

## Next
- Phase 5 — end-to-end voice → N8NBridge → n8n → HA smoke test
- Phase 6 — zero-TODO sweep, hardening
