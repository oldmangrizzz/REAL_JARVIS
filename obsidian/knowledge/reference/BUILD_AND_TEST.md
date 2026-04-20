# Build and Test

How to actually build and run tests on this repo.

## Generate / regenerate the Xcode project
```zsh
# Uses project.yml to (re)generate Jarvis.xcodeproj
xcodegen generate
```
`project.yml` is authoritative. `Jarvis.xcodeproj/` is a generated
artifact — don't hand-edit.

## Build (Mac)
```zsh
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis build
```

## Test
```zsh
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis build test
```
This is the same command the Archon workflow runs in its
`validation` step. See [[codebase/workflows/archon]].

## Mobile / Watch
Schemes are generated for each target:
- `JarvisMobileApp` (iOS 17)
- `JarvisWatch` (aggregate — app + extension)

Build with the corresponding `-scheme` and add `-destination` for the
simulator you want, e.g.:
```zsh
xcodebuild -project Jarvis.xcodeproj -scheme JarvisMobileApp \
           -destination 'generic/platform=iOS Simulator' build
```

## The repo-root `Package.swift` trap
The root `Package.swift` is a **stub** (`tempcheck`). `swift build`
from the repo root will NOT build Real Jarvis. Always use `xcodebuild`
against `Jarvis.xcodeproj` (or the workspace). See
[[reference/ENTRY_POINTS]].

## Tests
See [[codebase/testing/TestSuite]]. Targets:
- `JarvisCoreTests` — `Jarvis/Tests/JarvisCoreTests/`
- `JarvisMacCoreTests` — `Jarvis/Tests/JarvisMacCoreTests/`

## Frontends
- **PWA / Cockpit:** `pwa/docker-compose.yml` + `docker-compose up`.
  See [[codebase/frontend/pwa]].
- **Unity WebGL:** `scripts/build-unity-webgl.sh` or
  `scripts/mesh-unity-build.sh` — dispatches to beta for headless
  Unity build. See [[codebase/frontend/workshop-unity]].

## Services
- **VibeVoice (TTS):** `cd services/vibevoice-tts && uvicorn app:app`
  locally; deployed on GCP VM (spot). Bearer auth required.
- **jarvis-linux-node:** `jarvis-node.service` (systemd) on Linux;
  `ai.realjarvis.host-tunnel.plist` (launchd) on macOS.

## Common checks
```zsh
# Regenerate canon manifest (privileged — confirm before running)
scripts/regen-canon-manifest.zsh

# Emergency lockdown — halts voice pipeline + tunnel
scripts/jarvis-lockdown.zsh

# Canonical voice approval (operator-in-the-loop)
scripts/voice-approve-canonical.zsh

# Render intelligence briefing
python3 scripts/render_briefing.py
```

## RLMREPL invariant
Any REPAIR ticket must include a test that (a) fails before the fix,
(b) passes after the fix. See [[history/REMEDIATION_TIMELINE]].

## See also
- [[reference/ENTRY_POINTS]]
- [[reference/DEPENDENCIES]]
- [[reference/DEPLOYMENT]]
- [[codebase/workflows/archon]]
- [[codebase/scripts/README]]
