# n8n Workflow Library — Jarvis's Hands

These JSON files are importable n8n workflows that serve as Jarvis's execution
layer ("hands"). Jarvis calls them via `N8NBridge.runWorkflow(webhookPath:)`.

## Host
- **n8n**: LXC 119 on Alpha → `http://192.168.4.119:5678`
- **HA**: VM 200 on Alpha → `http://192.168.7.199:8123`

## Required n8n credential (one-shot operator setup)
Create a credential in n8n UI → Credentials → New → **HTTP Header Auth**:
- Credential name: `Home Assistant Bearer`
- Header name: `Authorization`
- Header value: `Bearer <HA_LONG_LIVED_TOKEN>` (from `~/.copilot/session-state/<sid>/files/ha.env`)
- Credential ID in workflows: `ha-bearer`

Workflows reference `{id: "ha-bearer", name: "Home Assistant Bearer"}` — import
after creating the credential so the binding resolves.

## Workflows
| File | Webhook path | Purpose |
|---|---|---|
| `ha-call-service.json` | `/webhook/jarvis/ha/call-service` | Generic HA service call (body: `{domain, service, data}`) |
| `scene-downstairs-on.json` | `/webhook/jarvis/scene/downstairs-on` | Turn on downstairs lights group |
| `scene-upstairs-on.json` | `/webhook/jarvis/scene/upstairs-on` | Turn on upstairs lights group |
| `forge-self-heal.json` | (schedule, 10 min) | Probe `forge.grizzlymedicine.icu/healthz`, notify on failure |

## Import procedure
1. Open n8n UI → Workflows → Import from File.
2. Select JSON file.
3. Activate toggle ON.
4. Test via `curl -X POST http://192.168.4.119:5678/webhook/<path> -d '{}'`.

## HA group entities expected
`scene-*-on.json` expects HA groups `group.downstairs_lights` and
`group.upstairs_lights`. Create in HA via `configuration.yaml`:
```yaml
light:
  - platform: group
    name: downstairs_lights
    entities:
      - light.living_room
      - light.kitchen
  - platform: group
    name: upstairs_lights
    entities:
      - light.bedroom
      - light.office
```
(Replace member entities with real Wiz/Nanoleaf entity_ids once onboarded.)
