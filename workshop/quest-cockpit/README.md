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

`JarvisTunnelClient.cs` is the thin TCP client that speaks the same
`TunnelFrame` protocol as `Jarvis/Shared/Sources/JarvisShared/TunnelModels.swift`.
The frame wire format is JSON + HMAC (see `TunnelCrypto.swift`). Reference
implementation in Swift — keep the Unity client byte-for-byte compatible.

Endpoints:
- Registration: `POST /register` with role `voice-operator` or `mobile-cockpit`.
  Gated by SPEC-007 (voice-approval-gate must be green for `voice-operator`).
- Cockpit snapshot stream: `GET /snapshot` — same payload `JarvisMobileCockpitStore`
  renders.

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
