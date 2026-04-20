# Mac

**Path:** `Jarvis/Mac/`
**Files:**
- `AppMac/RealJarvisMacApp.swift` — SwiftUI `@main`.
- `Sources/JarvisMacCore/`:
  - `JarvisMacSystemHooks.swift` — macOS integration (permissions, launchd).
  - `JarvisMacCockpitView.swift` — main UI.
  - `JarvisMacCockpitStore.swift` — view-model + `JarvisRuntime` binding.
  - `JarvisMacSettingsView.swift` — Settings pane.
  - `JarvisMacCockpitStoreTests.swift` — in-module tests.

## Purpose
The primary JARVIS host: Mac SwiftUI app. Runs
[[codebase/modules/Core|JarvisRuntime]] in-process, owns the Secure
Enclave key ([[codebase/modules/SoulAnchor]]), speaks through
[[codebase/modules/Voice]], and hosts the [[codebase/modules/Host|tunnel server]].

## HARD INVARIANT
The Mac app is the **primary Soul-Anchor holder**. Secure-Enclave P-256
operations happen only here (and any other Mac-class sibling).

## Related
- [[codebase/modules/Core]]
- [[codebase/modules/Voice]]
- [[codebase/modules/Host]]
- [[architecture/OVERVIEW]]
- [[codebase/frontend/cockpit]] — external cockpit frontend.
