# Phase 2 — Home Assistant Device Onboarding

**Status:** PARTIAL COMPLETE (unblocked work done; operator-required pairings deferred)
**Updated:** 2026-04-21

## Done
- [x] HA API auth verified (REST + WebSocket, long-lived token)
- [x] 9× Wiz bulbs integrated via REST `config_entries/flow` (user step, host=IP)
  - HA entities: `light.wiz_rgbw_tunable_{0202a8,874cb8,87cbf0,45486c,8992d4,920f90,921fe6,920e98}` + `light.wiz_rgbww_tunable_9f4aff`
  - Entity count climbed 21 → 48 (light + number + sensor per bulb)
- [x] Network scans complete:
  - Wiz UDP broadcast (port 38899): 9 bulbs found
  - mDNS `_amzn-wplay._tcp`: 2 Amazon devices
  - zeroconf via HA flow/progress: 2 Apple TVs + 3 HomePod minis + 1 eero
- [x] Device registry written: `obsidian/knowledge/device-registry/devices.md`
- [x] Operator pairing guide written: `obsidian/knowledge/operator-tasks/phase-2-pairings.md`

## Blocked on operator (no code work left on my side)
- [ ] Apple TV pairings (PIN entry on device)
- [ ] HomePod mini pairings (PIN; may need Home app re-share for 4th unit)
- [ ] Fire TV pairing (on-screen code)
- [ ] eero cloud auth (email verification code)
- [ ] Nanoleaf pairing (may be powered off)
- [ ] Wiz room labeling (needs physical identification)

## To install later (Phase 2b)
- [ ] HACS on HAOS → alexa_media_player → Echo Shows x4

## Key learnings (carry forward)
- HA REST `/api/config/config_entries/flow` **works** for POST init, but GET returns unreliable output in v2026.4.3. Prefer WebSocket for listing flows, REST for creating/advancing.
- WebSocket does NOT accept `config_entries/flow/init` type (error `unknown_command`) — REST only.
- Wiz integration accepts a manual `host` param when the `user` step is invoked, even though it's normally DHCP-discovery driven.
- HA entity jumped from 21 → 48 post-Wiz; room for O(100s) more after Phase 2 is fully complete.
