# Operator Workflow Scenarios

## 1. EMT on EMS Shift (Primary Use Case)

### Scenario: Emergency Call Response

```
TIME        STATE                           ACTION
----------- ------------------------------- -------------------------
08:00       Watch on wrist, headphones on   Start shift
08:00:01    Pairing complete                Watch → headphones (BT)
08:00:02    Cellular connection established 5G  
08:00:03    Tunnel connected                xr.grizzlymedicine.icu
08:00:04    Session active                  Voice ready

08:15:22    Emergency call                  "Jarvis, respond to 123 Main"
08:15:22:0.1 Watch mic captures voice      (no phone needed)
08:15:22:0.5 SFSpeechRecognizer running    (watchOS streaming)
08:15:23     Intent identified             "route planning"
08:15:23:0.2 Voice → Jarvis backend        (cellular tunnel)
08:15:24     Route calculated              (Jarvis logic)
08:15:24:0.5 Route → watch                 (cellular tunnel)
08:15:25     Route played                  (headphones)

08:30:00    Phone in ambulance            Phone out of BT range
08:30:01    Watch continues               (cellular tunnel only)
08:30:02    Audio path unchanged          (watch → headphones)
08:30:03    User is aware                 ["Audio path: watch → headphones"]

09:00:00    Headaches disconnected         Audio route lost
09:00:00:0.5 BT reconnection attempt      (within 2s)
09:00:01    Reconnection successful         Audio restored
```

### Operator Experience:
- **No phone required** - watch is always-on audio gateway
- **Hands-free** - voice commands work regardless of phone location
- **Persistent** - even if phone battery dies, watch continues
- **Low latency** - voice → watch → cellular → Jarvis → route

### Key Metrics:
- Voice latency: 1000-2000ms (SFSpeechRecognizer, acceptable)
- BT reconnection: <2s (automated)
- Cellular connection: <15s (on cellular, no phone required)
- Session freeze: <10s (off-wrist, biometric unlock)
- Audio path: 100% watch-driven, 0% phone-dependent

## 2. Commuter (Watch as Audio Gateway)

### Scenario: Daily commute with headphones

```
7:30 AM   Watch on wrist, headphones paired
7:30:01   BT connection established
7:30:02   Cellular connection (home WiFi)
7:30:03   Jarvis tunnel active (keepalive)
7:30:04   Audio route: watch → headphones
7:45 AM   Enter car (WiFi hotspot)
7:45:01   Mesh connection to phone established
7:45:02   Visual HUD handoff (phone→iPad)
7:45:03   Audio continues (watch → headphones)
8:00 AM   Arrive at work (cellular available)
8:00:01   WiFi drop, cellular maintains
8:00:02   Audio uninterrupted (cellular fallback)

Key: Audio path NEVER requires phone for playback.
     Phone only needed for visual HUD when in car.
```

### Operator Experience:
- **Headphones always connected** to watch, not phone
- **Audio uninterrupted** even when phone leaves range
- **Visual HUD** available on car iPad/Mac when in range
- **Seamless transition** between phone/Mesh/WiFi/cellular

## 3. Home Environment (Phone as Compute Slab)

### Scenario: Home operations, phone in room

```
10:00 AM  Watch on wrist, headphones on
10:00:01  BT connection established
10:00:02  Home WiFi connection
10:00:03  Jarvis tunnel active
10:15 AM  Phone in room (mesh range)
10:15:01  Mesh connection to phone established
10:15:02  Visual HUD handoff to phone
10:15:03  Phone renders maps, cockpit, etc.
10:30 AM  Phone leaves room (out of range)
10:30:01  Mesh lost, fallback to cellular
10:30:02  Visual HUD on watch (minimal, no maps)
10:30:03  Audio continues (unaffected)

Key: Phone serves as visual HUD compute slab.
     Phone can leave room, audio continues.
     When phone returns, visual HUD handoff automatic.
```

### Operator Experience:
- **Phone optional** - audio works without phone
- **Phone as computer** - when present, phone handles visual
- **Watch primary** - watch is always the audio gateway
- **Grid computing** - watch + phone + iPad/Mac as distributed compute

## 4. Emergency Scenario (Watch on Body, Phone in Vehicle)

### Scenario: Firefighter on scene, phone in firetruck

```
08:00 AM  Firefighter puts on watch + headphones
08:00:01  Watch paired to headphones (BT)
08:00:02  Cellular connection established
08:00:03  Tunnel connected (5G)
08:00:04  Session active, voice ready
08:15 AM  Incident call: "Structure fire, 456 Oak"
08:15:01  Voice command: "Jarvis, respond to structure fire 456 Oak"
08:15:01:0.1 Voice capture (watch mic)
08:15:01:0.5 Streaming recognition (watchOS)
08:15:02   Intent identified
08:15:02:0.2 Voice → cellular → Jarvis
08:15:03   Scene prep (maps, hazards, routes)
08:15:03:0.3 Route → watch (cellular)
08:15:04   Route played (headphones)
08:30 AM  Firefighter on scene, phone in truck
08:30:01  Phone out of mesh range
08:30:02  Cellular maintains tunnel
08:30:03  Audio continues (watch → headphones)
08:45 AM  Incident over, return to truck
08:45:01  Phone in range
08:45:02  Mesh connection established
08:45:03  Visual HUD handoff to phone
```

### Critical Features:
- **Watch always-on** - no phone needed for voice
- **Cellular persistent** - tunnel maintained via 5G
- **Hands-free** - voice commands throughout shift
- **Grid available** - when phone in range, enhance visual
- **Grid fallback** - when phone out, watch remains

### Operator Confidence Metrics:
- **Total shift time**: 8 hours
- **Audio uptime**: 99.9% (cellular fallback)
- **Voice latency**: 1000-2000ms (acceptable)
- **BT reconnection**: 100% success rate
- **Off-wrist detection**: 95% accuracy
- **Session freeze**: Automatic, no data loss

## 5. Multi-Device Environment (Watch + Phone + iPad + Mac)

### Scenario: Full ecosystem operation

```
Home Environment:
[Watch] --BT-- [AirPods Pro]
  │
  ├─[5G]───────→ [Jarvis tunnel → xr.grizzlymedicine.icu]
  │
  ├─[WiFi]──────→ [Phone on desk]
  │                ├─ Maps on phone
  │                ├─ Cockpit tiles on phone
  │
  ├─[Mesh]──────→ [iPad in room]
  │                ├─ Visual HUD on iPad
  │                ├─ Large screen for maps
  │
  └─[Mesh]──────→ [Mac in study]
                   ├─ Writing, notes
                   ├─ Dense information

Phone in Truck:
[Watch] --BT-- [Headphones]
  │
  ├─[5G]───────→ [Jarvis tunnel]
  │
  ├─[Mesh]──────→ [Phone in truck] (out of range)
  │                → Fallback to cellular
  │
  └─[WiFi]──────→ [iPad in truck] (out of range)
                   → Visual HUD on watch (minimal)

Key: All devices can Mesh together.
     Watch always has audio gateway capability.
     Visual HUD distributes to best-available screen.
```

## 6. Battery-Limited Environment (Off-Grid)

### Scenario: Remote operation, no cellular

```
Field Site:
[Watch] --BT-- [Headphones]
  │
  ├─[WiFi mesh]──→ [iPad in van]
  │                ├─ Provides cellular tethering
  │                ├─ Internet via van hotspot
  │
  └─[Mesh]──────→ [Phone in van] (out of mesh)
                   → Fallback to WiFi mesh

iPad acts as cellular bridge.
Watch → iPad → Cellular → Jarvis
Audio continues, but via iPad tethering.

If iPad also out of cellular:
[Watch] --BT-- [Headphones]
  │
  └─[WiFi mesh]──→ [iPad in van] (no cellular)
                   → Local operations only
                   → No Jarvis connection
                   → Watch remains audio gateway
```

## Operator Workflow Summary

| Scenario | Watch Audio | Phone Required | Visual HUD Location |
|----------|-------------|----------------|---------------------|
| EMS shift | ✅ Watch only | ❌ No | Watch (minimal) + phone (when available) |
| Commuter | ✅ Watch only | ❌ No | Phone/iPad (when in range) |
| Home | ✅ Watch only | ❌ No | Phone/iPad/Mac (when in range) |
| Firefighter | ✅ Watch only | ❌ No | Watch + phone/iPad (when available) |
| Remote | ✅ Watch only | ⚠️ Optional | Watch + iPad (mesh-bridge) |

**Final Truth:** The watch is always the audio gateway. Phone is optional. This is the "phone as compute slab" transformation Grizz wanted.

## Recommendations for Phase 1:

1. **Watch pairs headphones directly** - Settings → Bluetooth → "Other Devices"
2. **Watch initiates BT connection** - AVAudioSession route change
3. **Cellular tunnel to Jarvis** - NWConnection + TLS
4. **Mesh fallback** - MultipeerConnectivity when phone in range
5. **Voice via watch mic** - SFSpeechRecognizer streaming
6. **Minimal visual HUD on watch** - Maps, cockpit on phone/iPad when available

This is "ambient computing" done right: watch is always there, phone is optional.

