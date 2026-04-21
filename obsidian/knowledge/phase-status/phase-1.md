# Phase 1 — Foundation & Knowledge Base

**Goal**: Obsidian scaffold, n8n host decision, n8n install, TTS canon doc.

## Status
- [x] Obsidian scaffold created
- [x] n8n host picked — Alpha LXC 119 on `workshop` ZFS
- [x] n8n installed + reverse-proxied — https://n8n.grizzlymedicine.icu
- [x] Coqui TTS canon documented — `canon/voice.md`

**PHASE 1 COMPLETE.**

## Notes
- LXC 119: unprivileged + nesting, Docker-in-LXC, Debian 12.
- Reverse-proxy path: Charlie Traefik → NetBird 100.98.134.89:5678 → alpha DNAT → 192.168.4.119:5678.
- Credentials (basic-auth + encryption key + LXC root pw) in session-state `files/n8n.env` (chmod 600). Not committed.
- ntfy→iMessage bridge disabled at operator request (was flooding). LaunchAgent renamed to `.disabled`.
