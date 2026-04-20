# Dependencies

What the codebase links against. Keep this page current when
`project.yml` or external services change.

## Swift package dependencies
From `project.yml`:
- **MLXAudio** — `vendor/mlx-audio-swift` (vendored, not fetched).
  Used by mobile/mac voice paths (on-device audio / ML).

There are **no external SwiftPM registry deps**. `Package.swift` at
the repo root is a stub (`tempcheck`) — see
[[reference/ENTRY_POINTS]].

## Apple SDK frameworks
| Framework | Used by | Purpose |
| --- | --- | --- |
| AppKit | `JarvisCore`, `JarvisMac` | Mac UI. |
| AVFoundation | all platforms | Audio capture + playback. |
| Speech | `JarvisCore` | Speech recognition. |
| CryptoKit | all platforms | ChaCha20-Poly1305, SHA-256, Ed25519. |
| Network | all platforms | Tunnel transport. |
| BackgroundTasks | mobile | Tunnel/keepalive. |
| UserNotifications | mobile | Alerts. |
| AppIntents | mobile | Siri + Shortcuts integration. |
| WatchKit / ClockKit | watch | Complications, watch UI. |

## External runtime services
| Service | Location | Purpose | Doc |
| --- | --- | --- | --- |
| VibeVoice TTS | GCP VM (spot) | Cloned-voice synthesis. | [[codebase/services/vibevoice-tts]] |
| Convex | Convex cloud | Stigmergic signals + execution traces. | [[codebase/backend/convex]] |
| jarvis-linux-node | Linux / macOS LaunchAgent | Out-of-band tunnel node. | [[codebase/services/jarvis-linux-node]] |
| Unity headless build host | `beta` (192.168.4.151) | WebGL builds for PWA. | [[codebase/frontend/workshop-unity]] |

## External tools (build time)
- **XcodeGen** — consumes `project.yml` → `Jarvis.xcodeproj/`.
- **xcodebuild** — builds and tests (Apple).
- **Unity 2022.3.62f1** — headless on beta; see memory entry *"unity build"*.
- **Python** — `services/vibevoice-tts/app.py`, `services/jarvis-linux-node/jarvis_node.py`, `scripts/render_briefing.py`.
- **Docker Compose** — PWA stack (see [[codebase/frontend/pwa]]).

## Secrets / environment
- VibeVoice: `VIBEVOICE_BEARER`, `VIBEVOICE_IDLE_SECONDS` (default 1800).
- Tunnel: shared secret (SHA-256 → key for ChaCha20-Poly1305). Never in
  env; passphrase piped via [[codebase/modules/ControlPlane]].
- Soul Anchor: Secure Enclave P-256 (`P256-OP`) + cold Ed25519 root
  (`Ed25519-CR`). See [[codebase/modules/SoulAnchor]].
- Convex: URL + auth token (REPAIR-021). See
  [[codebase/modules/Telemetry]].

## See also
- [[reference/ENTRY_POINTS]]
- [[reference/BUILD_AND_TEST]]
- [[reference/DEPLOYMENT]]
