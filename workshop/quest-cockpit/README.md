# Quest Cockpit (Meta Quest 3 native)

Native Meta Quest 3 Unity build of the Jarvis cockpit. Replaces the (dropped)
visionOS target — Grizz is not buying a $3K headset while a $500 Quest 3
already has Link + OpenXR + passthrough.

## Why Unity (and not native Android XR)

Every REAL_JARVIS UI is Unity-based. The DOM was retired from this project in
the 1990s where it belongs. The cockpit runs on Unity so the XR build is a
reskin of the same scene graph the desktop workshop uses.

## Target stack

- Unity 2022.3 LTS (LTS matches the beta headless build host — see
  `scripts/mesh-unity-build.sh`).
- OpenXR with the Meta XR Feature Group enabled.
- XR Interaction Toolkit 2.5+.
- Meta XR Simulator (for headless CI on beta).
- Build target: Android, arm64, IL2CPP, Vulkan.

## Directory layout

```
workshop/quest-cockpit/
├── README.md                   # you are here
├── Assets/
│   └── Scripts/
│       └── JarvisTunnelClient.cs   # mirror of Shared/TunnelModels over TCP
└── Packages/
    └── manifest.json           # package manifest (XR + OpenXR + Meta + TMP)
```

## Runtime wiring

Apple phone/watch are the canonical mobile surfaces. Quest follows Apple, not
the other way around.

`JarvisTunnelClient.cs` now mirrors the Apple TestFlight cockpit by calling the
same Convex functions used by `JarvisMobileCockpitStore`:

- `jarvis:registerMobileDevice`
- `jarvis:recordMobileHeartbeat`
- `jarvis:sharedMobileState`

The rendered data contract is the same shared state:

- Central Brain: `snapshot.statusLine`, tunnel state, diagnostics.
- Voice Approval Gate: `snapshot.voiceGate`.
- Spatial HUD Elements: `snapshot.spatialHUD`.
- Authorization: commands remain restricted to Obsidian Command Bar and terminal.
- HomeKit Bridge: `homeKitBridge`.
- Obsidian Control Plane: `obsidianVault`.
- Recursive Thoughts: `thoughts` / `snapshot.recentThoughts`.
- Stigmergic Signals: `signals` / `snapshot.recentSignals`.

The encrypted TCP tunnel used by Apple is newline-framed
`JarvisTransportPacket` + `JarvisTunnelCrypto` ChaChaPoly. Unity does not yet
ship a byte-compatible tunnel implementation in this project. Until that exists,
Quest is a cockpit/state surface and Roger Roger/GhostLine control-plane surface;
it is not a privileged command surface.

## Roger Roger / GhostLine parity

Quest exposes the same modes:

- Sentinel -> Watch Haptics/Text
- Push to Talk -> Watch Speaker
- Full Live Speech -> Elehear Beyond

This is state routing, not a surprise live microphone. The live media plane
must be deliberately connected after voice gate approval.

## Release safety

For release builds, the Quest client fails closed if host address, host port, or
shared secret are blank, localhost, or build-setting placeholders. Secrets are
injected locally; never commit them.

## Building

Headless builds go through beta (see top-level memory `unity build`):
```
ssh beta '/usr/local/bin/run-unity-build.sh /mnt/shared/REAL_JARVIS/workshop/quest-cockpit Android'
```

Interactive development: open `workshop/quest-cockpit/` in Unity Hub, pick the
2022.3.62f1 LTS editor, add Android module, point at Quest 3 over Link cable.

## Non-DOM invariant

This project is subject to the canon-gate CI rule: **no WebView / DOM shims**.
UI is built from Unity's scene graph. If you need a text field, use TMP. If
you need a list, use UIToolkit. No `iframe`, no HTML, ever.
