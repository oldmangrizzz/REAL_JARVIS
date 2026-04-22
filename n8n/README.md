# n8n Workflows

## Overview
This directory contains n8n workflow definitions for JARVIS automation:
- **daily-briefing.json** — Morning briefing generation (active, production)
- **forge-self-heal.json** — Forge daemon health monitoring and restart (active, production)
- **ha-call-service.json** — Home Assistant service calls (active, production)
- **mesh-display-broadcast.json** — Broadcast messages to mesh displays (active, production)
- **scene-downstairs-on.json** — Turn on downstairs scenes (active, production)
- **scene-upstairs-on.json** — Turn on upstairs scenes (active, production)

All workflows are marked `"active": true` and ready for production.

## Activation

See `scripts/n8n-activate.sh` for automated workflow import and activation.

Requires:
- `N8N_BASE_URL` env var (e.g., http://n8n.grizzlymedicine.icu)
- `N8N_API_KEY` env var (n8n bearer token)

## Verification

See `scripts/n8n-verify.sh` to list active workflows and compare to expected set.
