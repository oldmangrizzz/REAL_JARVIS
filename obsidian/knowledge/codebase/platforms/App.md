# App

**Path:** `Jarvis/App/`
**Files:** `main.swift`

## Purpose
The simplest entry point — a command-line `main.swift`. This is the
headless/dev launcher for JARVIS on macOS, independent of the SwiftUI
[[codebase/platforms/Mac|Mac]] app shell.

## Role
- Boots [[codebase/modules/Core|JarvisRuntime]].
- Registers skills.
- Enters the REPL / event loop.

## Related
- [[codebase/platforms/Mac]] — GUI variant.
- [[codebase/platforms/Mobile]], [[codebase/platforms/Watch]] — other hosts.
- [[reference/ENTRY_POINTS]]
