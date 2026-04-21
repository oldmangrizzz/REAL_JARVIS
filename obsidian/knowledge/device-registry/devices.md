# GMRI Device Registry

**Updated:** 2026-04-21 (Phase 2, partial)
**Source:** HAOS 192.168.7.199:8123 + network scans from Echo
**HA version:** 2026.4.3

## Integrated (live in HA)

### Lighting — Wiz Connected (9 bulbs, all via `wiz` integration)
| IP | MAC | HA entity | Product | State @ scan |
|----|-----|-----------|---------|--------------|
| 192.168.4.21 | 44:4f:8e:02:02:a8 | `light.wiz_rgbw_tunable_0202a8` | RGBW Tunable | on |
| 192.168.4.22 | 44:4f:8e:87:4c:b8 | `light.wiz_rgbw_tunable_874cb8` | RGBW Tunable | on |
| 192.168.4.23 | 44:4f:8e:87:cb:f0 | `light.wiz_rgbw_tunable_87cbf0` | RGBW Tunable | off |
| 192.168.4.24 | d8:a0:11:45:48:6c | `light.wiz_rgbw_tunable_45486c` | RGBW Tunable | on |
| 192.168.4.25 | 44:4f:8e:89:92:d4 | `light.wiz_rgbw_tunable_8992d4` | RGBW Tunable | off |
| 192.168.4.26 | d8:a0:11:9f:4a:ff | `light.wiz_rgbww_tunable_9f4aff` | RGBWW Tunable | on |
| 192.168.4.27 | 44:4f:8e:92:0f:90 | `light.wiz_rgbw_tunable_920f90` | RGBW Tunable | on |
| 192.168.4.61 | 44:4f:8e:92:1f:e6 | `light.wiz_rgbw_tunable_921fe6` | RGBW Tunable | on |
| 192.168.6.116 | 44:4f:8e:92:0e:98 | `light.wiz_rgbw_tunable_920e98` | RGBW Tunable | on |

Room-labeling (downstairs/upstairs) TODO — requires operator to identify which MAC is in which room.
Quick test: `curl -H "Authorization: Bearer $HA_TOKEN" -X POST -H "Content-Type: application/json" \
 -d '{"entity_id":"light.wiz_rgbw_tunable_921fe6"}' http://192.168.7.199:8123/api/services/light/toggle`
— whichever bulb blinks identifies that MAC, record in this file.

## Discovered but NOT yet paired (requires operator on-device action)

### Apple TVs (2)
- `living room apple tv` — zeroconf discovery active, needs PIN entry
- `Mom & Dad's AppleTV` — discovered (family unit, may not be in scope to pair)

### HomePod minis (3 discovered via zeroconf, operator says 4 total)
- `Living Room Right` (HomePod mini)
- `Living Room Left` (HomePod mini)
- `Dad's Side` (HomePod mini)
- 1+ additional HomePod mini not yet announcing on mDNS — may need power-cycle or Home app re-share

Pairing: HA's `apple_tv` integration uses AirPlay PIN. HomePod minis must be shared with the HA user's
AppleID in the Home app before they'll accept PIN pairing.

### Amazon Fire TV (1)
- 2× `_amzn-wplay._tcp` advertisements discovered (FireTV + echo devices both use this)
- HA `androidtv_remote2` integration preferred (pairs via on-screen code, doesn't require ADB enable)
- Requires operator to accept pairing prompt on TV

### eero Pro 6 router (1)
- SSDP discovery active (`upnp` handler)
- HA `eero` integration available but requires Amazon/eero cloud credentials

### Echo Shows (4: 2× Echo Show 8 downstairs, 1× Echo Show mini + 1× Echo Show gen2 upstairs)
- No native HA integration for Echo Shows without HACS + `alexa_media_player`
- Phase 2b: install HACS, then install alexa_media_player, use Amazon credentials

### Nanoleaf (count unknown)
- Did NOT respond to mDNS `_nanoleafapi._tcp` scan from Echo at this time
- May be powered off, on guest subnet, or using older discovery protocol
- Operator to confirm power state; scan will be repeated

## Not present / out of scope
- `device_tracker` for operator phone/laptop — deferred to Phase 5 (presence automation)
