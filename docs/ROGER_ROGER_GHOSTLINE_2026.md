# Roger Roger + GhostLine 2026

## Canon correction

Roger Roger is not radio etiquette, ACK/NACK doctrine, or a communication-discipline layer. Those older interpretations are contaminated early-draft material.

Roger Roger is the bidirectional intelligibility protocol for JARVIS powered by GrizzOS: the system that keeps voice usable when disability, noise, stress, distance, bad networks, or field conditions make ordinary interaction fail.

GhostLine is the delivery fabric: the routing layer that decides where JARVIS voice, alerts, media, haptics, and text render across the operator's devices and physical zones.

Together:

```text
Roger Roger = understand and be understood
GhostLine = deliver the signal to the right endpoint
```

## Operating principle

Voice is the lifeline. Whether the operator is disabled at home, a medic in a hostile acoustic scene, or a companion asking for help, the system must preserve meaning transfer:

```text
If the human speaks, JARVIS must understand or know that he did not.
If JARVIS speaks, the human must understand or receive an adaptive fallback.
If the route fails, GhostLine must reroute without requiring the human to hunt for a phone.
```

## Modes

### Sentinel mode

Quiet, ambient availability.

- Watch remains the primary control surface.
- JARVIS may listen for explicitly configured triggers and push-to-talk events.
- Responses prefer watch-face text and haptics.
- No routine spoken replies unless escalation or operator command requires it.
- Intended for home, family, public spaces, and low-interruption disability support.

### Push-to-talk mode

Deliberate voice exchange.

- Operator initiates speech from the Watch or veil.
- JARVIS responds through the current GhostLine endpoint.
- Best default for battery-sensitive Watch-only situations.
- Critical commands still carry consequence-aware confirmation.

### Full live speech mode

Real-time two-way audio.

- Continuous active conversation channel.
- Barge-in enabled.
- Speech enhancement and route monitoring active.
- Preferred output is Elehear Beyond when available.
- Watch speaker is a first-class fallback when the phone is absent and the Watch is the only reachable body.

## Endpoints

| Endpoint | Role |
| --- | --- |
| Elehear Beyond | Preferred private comms endpoint and hearing-aid route. |
| Watch speaker | First-class Watch-only audio fallback for app-originated JARVIS speech. |
| Watch haptics/text | Sentinel-mode output and silent fallback. |
| iPhone broker | Bluetooth/audio-session owner for Elehear and mobile capture. |
| iPad veil | Rich mobile surface and compute/visual assist. |
| Mac veil | Desktop control, heavy local automation, richer audio tooling. |
| HomePods | Home-zone broadcast route when privacy/household context allows. |
| CarPlay | Vehicle/route HUD and speech endpoint. |

## Device roles

```text
Apple Watch = always-worn trigger, mic, haptic/text surface, Watch-only speech fallback
iPhone = audio route broker, Elehear owner, mobile capture/relay, app-side compute
iPad = large veil, camera/context, mobile workstation
Mac = heavy local control, desktop audio/automation surface
HomePods = home-zone GhostLine renderers
Delta/cluster = cognition, memory, XTTS, routing authority where appropriate
```

The Watch should be treated as the ambient beginning of communication because it is always worn and never occupies the operator's hands. The phone and tablet are compute and broker surfaces, not required hand-held remotes.

## Watch-only rule

There will be times when the Watch is the only device physically present. Therefore Watch speaker output is a first-class GhostLine endpoint for JARVIS-originated audio.

This does not mean the Watch becomes a universal Bluetooth audio router for every Apple device. It means JARVIS must be able to render his own response through the Watch when no better endpoint is reachable, and the Watch must be able to command the iPhone/Mac/HomePod broker when those routes are reachable.

## Elehear Beyond rule

Elehear Beyond is treated as the preferred private endpoint because it presents as Bluetooth streaming hearing aids and already supports phone-mediated audio workflows.

The broker should prefer:

```text
route audio -> reconnect/disconnect -> guided Settings assist -> unpair/re-pair only by explicit operator command
```

Unpairing is not the default. It is a recovery operation.

## Pipeline

```text
Operator speech / Watch command / route event
    -> Roger Roger capture state
    -> enhancement + VAD + confidence
    -> intent + consequence scoring
    -> JARVIS cognition
    -> Roger Roger response contract
    -> GhostLine route decision
    -> Elehear / Watch / iPhone / Mac / HomePods / CarPlay / veil
```

## Relationship to Swivel and LokiCam

Roger Roger and GhostLine are the voice/comms nervous system. Swivel is the situational-awareness engine over memory, Mapbox, legal public OSINT, GIS, sensors, and live visual context. LokiCam is the early edge-camera/sensor concept that feeds Swivel.

For ResponderOS, the target is EMS field safety and real-time situational support. For CompanionOS, the same capability class is aimed at advocacy, disability safety, household context, and family support.

## Implementation status

Current MKII code has first-class shared models for:

- `RogerRogerMode.sentinel`
- `RogerRogerMode.pushToTalk`
- `RogerRogerMode.fullDuplexLiveSpeech`
- `GhostLineEndpoint.elehearBeyond`
- `GhostLineEndpoint.watchSpeaker`
- `GhostLineEndpoint.watchHapticsText`
- `GhostLineEndpoint.iPhoneBroker`
- `GhostLineEndpoint.homePods`

The Watch veil exposes mode controls and sends mode changes into the tunnel. The iPhone Watch bridge can ingest Roger Roger mode changes and publish state for the audio broker.
