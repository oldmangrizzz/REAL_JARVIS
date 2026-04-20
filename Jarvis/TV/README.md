# Jarvis Apple TV target

Read-only Jarvis cockpit surface for tvOS 17+. Pure SwiftUI. No DOM, no
WebView.

The target is **not yet wired into `Jarvis.xcodeproj`** — adding a new Xcode
target for a different SDK (`appletvos`) requires interactive Xcode surgery
that can't be cleanly scripted via the pbxproj patcher pattern we use for
in-scheme Swift files. The scaffold is complete and compiles as a standalone
SwiftPM module if needed.

## Wiring it up (one-time, in Xcode GUI)

1. File → New → Target → tvOS → App
   - Product Name: `RealJarvisTV`
   - Interface: SwiftUI
   - Language: Swift
2. Delete the generated `ContentView.swift` and app entry file.
3. Add these existing sources to the new target:
   - `Jarvis/TV/AppTV/RealJarvisTVApp.swift`
   - `Jarvis/TV/Sources/JarvisTVCore/JarvisTVCockpitStore.swift`
4. Deployment target: tvOS 17.0.
5. Sign with the same team as the Mac / Mobile / Watch targets.

## Why tvOS and not visionOS

User explicitly dropped visionOS pending a Vision Pro purchase. The tvOS
surface is deliberately read-only — it's a glanceable Jarvis dashboard that
shows host status, voice gate state, and the active HUD. Control authority
remains on echo (Mac host) + voice-operator role (SPEC-007).

## Quest 3 cockpit

Interactive XR cockpit lives at `workshop/quest-cockpit/` (Unity + OpenXR,
Meta XR SDK). That's where actual control surfaces belong.
