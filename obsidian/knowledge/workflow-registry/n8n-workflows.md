# Workflow Registry

| ID | File | Webhook | Auth | Purpose |
|---|---|---|---|---|
| ha-call-service | `n8n/workflows/ha-call-service.json` | `POST /webhook/jarvis/ha/call-service` | HA Bearer | Generic HA service dispatch `{domain,service,data}` |
| scene-downstairs-on | `n8n/workflows/scene-downstairs-on.json` | `POST /webhook/jarvis/scene/downstairs-on` | HA Bearer | Turn on `group.downstairs_lights` |
| scene-upstairs-on | `n8n/workflows/scene-upstairs-on.json` | `POST /webhook/jarvis/scene/upstairs-on` | HA Bearer | Turn on `group.upstairs_lights` |
| forge-self-heal | `n8n/workflows/forge-self-heal.json` | (schedule 10 min) | — | Probe forge health, ntfy on failure |

## Swift client
`Jarvis/Sources/JarvisCore/Integrations/N8NBridge.swift` — call via `bridge.runWorkflow(webhookPath: "jarvis/scene/downstairs-on", payload: [:])`.
