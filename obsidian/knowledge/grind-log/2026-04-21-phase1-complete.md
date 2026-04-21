# 2026-04-21 — Phase 1 Complete

## Delivered
1. **Obsidian knowledge base** scaffolded under `obsidian/knowledge/`: grind-log, device-registry, workflow-registry, phase-status, operations, canon.
2. **Voice canon documented** (`canon/voice.md`): Coqui XTTS v2 LOCKED; say/VibeVoice/F5/cloud TTS forbidden. Noted stale `TTSBackend.vibevoiceLocked` symbol to rename in Phase 4.
3. **n8n live** at `https://n8n.grizzlymedicine.icu`:
   - Alpha LXC 119 (2 vCPU / 2 GB / 8 GB on workshop ZFS)
   - Docker container `n8nio/n8n:latest`, data at `/var/lib/n8n`
   - Basic auth + encryption key persisted to session-state (not committed)
   - Reverse-proxied via Charlie Traefik → NetBird → alpha DNAT → LXC
4. **ntfy→iMessage flood stopped** — LaunchAgent booted out + plist disabled.

## Verification
- `curl -I https://n8n.grizzlymedicine.icu/` → **200 OK**
- `docker ps` inside LXC → n8n running
- iMessage flood: halted (PID 1344 killed, KeepAlive agent removed)

## Next
Phase 2 — HA device onboarding. Query HA REST at `http://192.168.7.199:8123` with token from
`~/.copilot/session-state/999bd49a-.../files/ha.env`, inventory current devices, add integrations
for the 6 HomePod minis, 2 Apple TVs, Fire TV, 3 Echo Shows, Wiz + Nanoleaf lights, Eero.
