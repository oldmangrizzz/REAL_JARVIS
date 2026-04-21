# MK2-EPIC-01 — Xcode Workspace Target Wiring

**Lane:** GLM (infra)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** — (must land first, unblocks 02/03/06/07/09/10)
**Priority:** P0
**Canon sensitivity:** LOW (no canon edits)

---

## Why

`GAP_CLOSING_STATUS.md` reports GAP-001 shipped — Mac app files exist at `Jarvis/Mac/AppMac/RealJarvisMacApp.swift` + `Jarvis/Mac/Sources/JarvisMacCore/`. But the workspace (`jarvis.xcworkspace`) has **no MacApp target**. Operator cannot double-click and launch. Similarly the Watch Extension and visionOS stub lack scheme entries. Result: `xcodebuild build` greenlights CLI but not the surfaces the operator actually uses.

Mark II cannot ship until every declared surface compiles via a single `xcodebuild -workspace jarvis.xcworkspace -scheme all` invocation.

## Scope

### In

1. **Add Xcode targets** to `Jarvis.xcodeproj` (and register in `jarvis.xcworkspace`):
   - `RealJarvisMac` — macOS 14.0+, Swift 6, strict concurrency. Entry: `Jarvis/Mac/AppMac/RealJarvisMacApp.swift`. Links `JarvisMacCore`, `JarvisMobileShared`, `JarvisShared`, `JarvisCore`.
   - Verify `RealJarvisPhone`, `RealJarvisPad`, `RealJarvisWatch`, `JarvisCLI` targets exist; add if missing.
   - Add `RealJarvisVision` (visionOS) target **conditionally** — only if `xcodebuild -showsdks` reports visionOS SDK; otherwise skip and emit `Construction/GLM/response/MK2-EPIC-01-vision-skipped.md` documenting the skip reason.
2. **Add a composite `all` scheme** that builds every target. The scheme is committed to `jarvis.xcworkspace/xcshareddata/xcschemes/all.xcscheme`.
3. **Fix any build breaks** surfaced by the new schemes. Do NOT modify business logic; only repair import/target/platform-guard issues. If a fix requires non-trivial logic change, STOP and stage a response doc listing the break + proposed fix.
4. **Smoke script** at `scripts/smoke/build-all.sh`:
   - Runs `xcodebuild build -workspace jarvis.xcworkspace -scheme all -destination 'generic/platform=macOS'`.
   - Exits 0 on green, non-zero on any target failure.
   - Prints a per-target pass/fail table.

### Out

- Do NOT change any Swift source inside `Jarvis/Sources/JarvisCore/` except to add `#if canImport(…)` guards needed for target compilation.
- Do NOT modify `Package.swift`; Xcode targets are the authority for Mark II.
- Do NOT touch canon.

## Acceptance Criteria (verifiable)

- [ ] `scripts/smoke/build-all.sh` exits 0 locally.
- [ ] `xcodebuild -workspace jarvis.xcworkspace -list` lists schemes: `JarvisCLI`, `RealJarvisMac`, `RealJarvisPhone`, `RealJarvisPad`, `RealJarvisWatch`, `all`, and (if SDK present) `RealJarvisVision`.
- [ ] New target additions are reflected in committed project files (`Jarvis.xcodeproj/project.pbxproj` diff reviewed by Fury — must be syntactically valid pbxproj).
- [ ] Existing test count (≥100) unchanged or higher; 0 failures.
- [ ] No `@unchecked Sendable` introduced.

## Invariants

- PRINCIPLES §2 (hardware sovereignty): no external build tooling required beyond Xcode + stock Apple SDKs.
- Strict concurrency remains enabled on every target.

## Tests

- `JarvisMacCoreTests/MacAppEntryTests.swift` — verify `RealJarvisMacApp` scene graph has a `WindowGroup`, `Settings`, and min frame `900x600`.
- `BuildAllSmokeTests` (optional bash test under `scripts/smoke/tests/`) — assert `build-all.sh` returns 0.

## RLM REPL Sequence (hint for Ralph)

```
1. INSPECT Jarvis.xcodeproj/project.pbxproj — identify current targets.
2. BACKUP pbxproj to /tmp before mutation.
3. ADD RealJarvisMac target via `xcodebuild -create-target` OR hand-edit pbxproj with UUIDs; prefer xcodeproj gem or python mod if available.
4. ADD shared scheme `all` aggregating every runnable target.
5. BUILD → identify import/target errors → patch with #if canImport guards.
6. REPEAT until `build-all.sh` green.
7. WRITE Construction/GLM/response/MK2-EPIC-01.md summarizing targets added, schemes added, guards applied.
```

## Artifacts

- `Jarvis.xcodeproj/project.pbxproj` (modified)
- `jarvis.xcworkspace/xcshareddata/xcschemes/all.xcscheme` (new)
- `scripts/smoke/build-all.sh` (new)
- `Construction/GLM/response/MK2-EPIC-01.md` (new, completion summary)
