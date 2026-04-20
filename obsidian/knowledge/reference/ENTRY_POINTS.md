# Entry Points

Where execution actually starts, per platform. For module-level
structure see [[codebase/CODEBASE_MAP]].

## Mac (primary host)
- **CLI / app entry:** `Jarvis/App/main.swift` — target `JarvisCLI`
  (`type: tool`, macOS 14). Boots `JarvisRuntime`
  ([[codebase/modules/Core]]) and wires Voice → Interface →
  Telemetry.
- **Mac app target:** `Jarvis/Mac/` — target `JarvisMac`
  (`type: application`). AppKit shell around the same `JarvisCore`.

## Mobile (iOS)
- **App target:** `JarvisMobileApp` (`type: application`, iOS 17).
  Sources: `Jarvis/Mobile/`. Links `JarvisMobileCore`
  (`type: framework`). Uses AppIntents + BackgroundTasks for
  voice/tunnel keepalive.

## Watch (watchOS)
- **Watch app:** `JarvisWatchApp` (`type: application.watchapp2`).
- **Extension:** `JarvisWatchExtension` (`type: watchkit2-extension`).
- **Aggregate:** `JarvisWatch` (packages app + extension).
- Core: `JarvisWatchCore` (`type: framework`). Sources: `Jarvis/Watch/`.

## Shared
- **`JarvisShared`** — `Jarvis/Shared/Sources/JarvisShared/`
  (Tunnel wire format + crypto). Consumed by all three platforms.
- **`JarvisMobileShared`** — `Jarvis/MobileShared/Sources/...`.

## Tests
- `JarvisCoreTests` — `Jarvis/Tests/JarvisCoreTests/` (macOS unit
  tests). See [[codebase/testing/TestSuite]].
- `JarvisMacCoreTests` — `Jarvis/Tests/JarvisMacCoreTests/`.

## Services (non-Xcode)
- `services/jarvis-linux-node/` — `jarvis_node.py` launched by
  `jarvis-node.service` (systemd on Linux) or the `.plist` on macOS.
  See [[codebase/services/jarvis-linux-node]].
- `services/vibevoice-tts/` — `app.py` (FastAPI / uvicorn) on
  GCP VM. See [[codebase/services/vibevoice-tts]].

## Frontends (standalone)
- **Cockpit:** `cockpit/` HTML + Vite. See
  [[codebase/frontend/cockpit]].
- **PWA:** `pwa/index.html` + `sw.js` + Unity `Build/`. See
  [[codebase/frontend/pwa]].
- **Workshop Unity:** built by `scripts/build-unity-webgl.sh` /
  `mesh-unity-build.sh`. See [[codebase/frontend/workshop-unity]].
- **xr.grizzlymedicine.icu:** static site in `xr.grizzlymedicine.icu/`.
  See [[codebase/frontend/xr-grizzlymedicine]].

## Top-level oddity
- Root `Package.swift` is a **stub** (`name: "tempcheck"`). The real
  Swift build is driven by `project.yml` → `Jarvis.xcodeproj/`
  (XcodeGen). Don't try to `swift build` from the repo root.

## See also
- [[reference/BUILD_AND_TEST]]
- [[reference/DEPENDENCIES]]
- [[reference/DEPLOYMENT]]
