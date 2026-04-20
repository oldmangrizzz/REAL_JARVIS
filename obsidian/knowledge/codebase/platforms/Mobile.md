# Mobile

**Path:** `Jarvis/Mobile/`
**Files:**
- `AppiPhone/RealJarvisPhoneApp.swift` — iPhone `@main`.
- `AppiPad/RealJarvisPadApp.swift` — iPad `@main`.
- `AppShared/`:
  - `JarvisMobileAppDelegate.swift`
  - `JarvisMobileAppIntent.swift` — App Intents for Siri/Shortcuts.
- `Sources/JarvisMobileCore/`:
  - `JarvisMobileSystemHooks.swift`
  - `JarvisMobileVoiceCloneEngine.swift` — on-device clone scaffolding.
  - `JarvisCockpitView.swift`
  - `JarvisMobileCockpitStore.swift`
- `Resources/voice-reference.txt`

## Purpose
iOS / iPadOS host — thin client relative to [[codebase/platforms/Mac]].
Mobile is **never** the primary Soul Anchor holder. It mostly displays
[[codebase/modules/Interface|cockpit]] state and forwards voice to the
Mac through the tunnel.

## Invariants
- No Secure-Enclave ratification from mobile (Person axis untrusted for
  [[codebase/modules/SoulAnchor]] ops).
- Voice synthesis must still pass [[concepts/Voice-Approval-Gate]];
  mobile asks the Mac.

## Related
- [[codebase/platforms/Mac]]
- [[codebase/modules/Host]] — tunnel server mobile connects to.
- [[codebase/modules/Voice]]
