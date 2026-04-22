# HA Current State Inventory
Generated: 2026-04-21

- HA version: 2026.4.3
- URL: http://192.168.7.199:8123 (HAOS VM on alpha, VMID 200)
- Entities: 48
- Components loaded: 166

## Integrations LOADED (config_entries state=loaded)
- sun, thread, hassio, go2rtc, backup, matter, shopping_list
- google_translate (TTS), radio_browser
- **wiz** — 9 bulbs RGBW/RGBWW tunable (all loaded, healthy)

## Lights onboarded (9)
| entity_id | color_modes |
|---|---|
| light.wiz_rgbw_tunable_0202a8 | color_temp, rgbw |
| light.wiz_rgbw_tunable_874cb8 | color_temp, rgbw |
| light.wiz_rgbw_tunable_87cbf0 | color_temp, rgbw |
| light.wiz_rgbw_tunable_45486c | color_temp, rgbw |
| light.wiz_rgbw_tunable_8992d4 | color_temp, rgbw |
| light.wiz_rgbww_tunable_9f4aff | color_temp, rgbww |
| light.wiz_rgbw_tunable_920f90 | color_temp, rgbw |
| light.wiz_rgbw_tunable_921fe6 | color_temp, rgbw |
| light.wiz_rgbw_tunable_920e98 | color_temp, rgbw |
(rooms not yet labeled — needs operator to walk-identify each bulb)

## Discovered via mDNS (pending pairing)
### Apple TV / AirPlay (zeroconf auto-discovered, flows in progress)
- Abby's TV
- Mom & Dad's AppleTV
- living room apple tv
- Living Room Left / Living Room Right (likely HomePod stereo pair)
- Workshop Echo (Echo Show, not pairable — Amazon)
- Dad's Side

7 `apple_tv` config flows are currently stuck at `step=confirm` awaiting PIN entry.

### HomePod HAP (HomeKit sensors, advertise independent of Apple Home pairing)
- HomePodSensor 362336
- HomePodSensor 498945
- HomePodSensor 122215
(4th HomePod not currently advertising — may be off or already paired)

### Fire TV
- FireTV AFTDCT31 (advertises _hap._tcp — pair via HomeKit Controller OR androidtv integration)

## NOT YET onboarded — requires physical/operator action
| Integration | Count | Blocker |
|---|---|---|
| apple_tv | ≤3 Apple TVs | PIN entry on TV screen |
| homekit_controller (HomePod sensors) | 3–4 | Accept pairing PIN shown on HA UI |
| androidtv / FireTV | 1 | ADB pairing OR HomeKit PIN |
| alexa_media (Echo Show x3) | 3 | Amazon login + 2FA |
| nanoleaf | TBD | button hold on controller for pairing token |
| eero | 1 router | eero account login |

## Auto-operational right now
- 9 Wiz bulbs ✅ (all responsive)
- Thread/Matter network ✅
- go2rtc ✅
