# Presence → Greeting Pipeline

## Purpose
When Grizz walks through the front door, JARVIS greets him on host audio +
HomePod intercom + lab/living-room/kitchen displays — within a few seconds
of the arrival signal, deduped against sensor flutter.

## Architecture

```
           HomeKit "Person Arrives Home"  /  CSI sensor HTTP POST
                     │
                     ▼
          JarvisHostTunnelServer.handle(.presenceArrival)
                     │
                     ▼
            PresenceEventRouter.handle(event)
               │
               ├── GreetingOrchestrator.plan(for:context:)   (pure logic)
               ├── telemetry.logExecutionTrace(..)           (always)
               ├── voice.speak(line, persistAs: presence-greeting-<id>.wav)
               │     (VoiceApprovalGate hard-gates identity drift)
               └── fan-out (HomePod / Lab TV / Apple TV / Echo Show / Fire TV)
```

## Suppression rules

- Only `kind == .arrival` triggers speech.
- Cooldown: 5 minutes on-greeting (`cooldownSeconds = 300`).
- `source == .mock` always suppressed.
- `source == .wifiCSI` with `confidence < 0.6` suppressed.
- Suppressed events still hit telemetry.

## Source tagging
Every greeting names the sensor: "via Wi-Fi CSI", "via HomeKit arrival",
"via your Shortcut", "on manual cue". Operator transparency by design.

## Wiring HomeKit "Person Arrives"

1. Open **Shortcuts.app** on the host Mac.
2. **Automation** → **Create New Automation** → **Home** → **People Arrive**.
3. Action: **Get Contents of URL**.
   - URL: `http://localhost:9443/command`
   - Method: `POST`
   - Body (JSON): `action: "presence_arrival"`, `payloadJSON`: an encoded
     `JarvisPresenceEvent` (source=homekit-geofence, kind=arrival).

The tunnel HMAC/authorization flow lives in `JarvisHostTunnelServer.swift`.

## CSI backend

True Wi-Fi CSI on macOS is impossible with stock hardware. Expected backends:
Nexmon (BCM43xx), esp-csi (ESP32-S3), or Intel 5300 csitool. Any of these
POST `presence_arrival` to the tunnel; the router doesn't care where the
signal came from.

## Shipped vs honest stubs

| Surface | Status |
| --- | --- |
| Host audio (Echo Mac) | ✅ real — voice pipeline |
| HomePod intercom | ✅ real — HomeBridge/Shortcuts relay |
| Lab TV | ✅ real — AirPlay |
| Apple TV living room | ✅ real — AirPlay |
| Fire TV | ⚠️ queued/logged — DIAL bridge not yet wired |
| Echo Show kitchen | ⚠️ queued/logged — Alexa routine bridge not yet wired |

The router logs every intended actuation, so when the bridges land they
replay cleanly from telemetry.
