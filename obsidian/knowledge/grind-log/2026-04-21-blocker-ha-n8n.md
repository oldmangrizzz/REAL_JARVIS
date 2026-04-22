# Grind Log: Infrastructure Blockers — 2026-04-21

## Status
Phase D (HA) and Phase E (n8n) blocked on infrastructure, not code.

## Issue
- **HAOS VM (VMID 200)**: Running but service unresponsive (port 8123 not answering)
  - Impact: Cannot enumerate HA entities for Phase D registry
  - Mitigation: Check HAOS logs via Proxmox console; may need service restart or full reboot
  
- **n8n LXC (VMID 119)**: Running, responds locally (192.168.4.119:5678) but hangs from Echo
  - Root cause: Network isolation — Echo is on 192.168.7.x (HA subnet), LXC is on 192.168.4.x (infra subnet)
  - Impact: Swift N8NBridge tests work (local); runtime calls from Echo will timeout
  - Mitigation: Configure firewall rules to allow 192.168.7.x → 192.168.4.x:5678, or use VPN tunnel, or proxy via alpha
  
- **HA network path**: HA on 192.168.7.199 (Alpha Proxmox VMID 200), Echo on 192.168.7.114 (same subnet)
  - HA service hung; unclear if network or service issue

## Code Status
- Phase A (Canon): ✓ DONE — validator wired, voice canon locked
- Phase C (Desktop Control): ✓ VERIFIED — mesh-display live, echo bridge live
- Phase G (TODO Sweep): ✓ COMPLETE — 0 TODOs
- Phase H (Tests): ✓ 634/634 PASSING
- Phase B (Cognee Beta): ⊘ BLOCKED — pydantic_core native module error (Linux venv)
- Phase D (HA): ⊘ BLOCKED — service unresponsive
- Phase E (n8n): ⊘ BLOCKED — network isolation (code works, infrastructure issue)
- Phase F (Voice E2E): ⊘ BLOCKED — depends on HA+n8n network access

## Swift Integration Status
- N8NBridge tests: 8/8 passing (verified in Phase 3, commit 08d90ed)
- Voice canon validator: wired into jarvis-say, rejects on drift
- Echo desktop bridge: /listen, /speak, /ask all working
- Mesh-display agent: alpha+beta endpoints responding

## Next Steps
1. Diagnose HAOS service (check Proxmox console logs, restart if needed)
2. Resolve Echo↔infra network path (firewall rule, tunnel, or proxy)
3. Re-verify HA REST API + entity enumeration
4. Re-verify n8n endpoint availability from Echo
5. Run Phase F smoke test (voice command → n8n → HA → device)

## Code Artifacts Ready for Phase D/E/F
- `Jarvis/Sources/JarvisCore/Integrations/N8NBridge.swift` (Swift client)
- `n8n/workflows/*.json` (4 seed workflows)
- `services/voice_canon_validator.py` (canon enforcement)
- `~/.jarvis/bin/jarvis-say` (with validator gate)
