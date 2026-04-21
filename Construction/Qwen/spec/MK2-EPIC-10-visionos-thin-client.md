# MK2-EPIC-10 — visionOS Thin Client (behind SDK gate)

**Lane:** Qwen (UX)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4; follows `GAP_CLOSING_SPEC.md` GAP-005
**Depends on:** MK2-EPIC-01
**Priority:** P2 (ships if green; deferrable to Mark III otherwise)

---

## Why

GAP-005 (visionOS) was skipped because the SDK was not available in the build environment at the time. The protocol stack already supports spatial anchors. Mark II delivers a **thin client** stub that compiles behind an `#if canImport(RealityKit) && os(visionOS)` guard and, when SDK is present, renders the existing `JarvisSpatialHUDElement` payloads in an `ImmersiveSpace`.

The epic is acceptable with "compiles behind guard; does not need to run" — running requires SDK access.

## Scope

### In

1. **Target** `RealJarvisVision` (added via EPIC-01 if SDK present).
2. **App entry** `Jarvis/Vision/AppVision/RealJarvisVisionApp.swift`:
   - `@main` struct with `ImmersiveSpace(id: "cockpit") { JarvisVisionImmersiveView() }`.
   - Fallback `WindowGroup` with an "Enter Immersive" button.
3. **Immersive view** `Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionImmersiveView.swift`:
   - Subscribes to `JarvisTunnelClient` for `HostSnapshot.spatialHUD`.
   - For each `JarvisSpatialHUDElement`, instantiates a `RealityView` entity with text mesh, anchored per element's world-space position.
   - GMRI palette (emerald/silver/black/crimson) applied.
4. **Build guard**: the entire `Jarvis/Vision/` tree is wrapped in `#if canImport(RealityKit) && os(visionOS)` at module level so it does not break non-vision builds.
5. **Conditional target** in `project.pbxproj` (by EPIC-01 conditional-add logic).

### Out

- No hand tracking, no spatial audio (Mark III).
- No persistent immersive — one-shot HUD only.
- No runtime testing required; compile-time green via `xcodebuild -destination 'generic/platform=visionOS'` suffices (if SDK present).

## Acceptance Criteria

- [ ] If visionOS SDK available: `xcodebuild build -scheme RealJarvisVision -destination 'generic/platform=visionOS'` green; smoke passes.
- [ ] If visionOS SDK absent: epic emits `Construction/Qwen/response/MK2-EPIC-10-skipped.md` with clear rationale; shipping Mark II is NOT blocked (P2 allows skip).
- [ ] Guards prevent vision code from polluting other targets.

## Invariants

- PRINCIPLES §2: spatial HUD consumes only tunnel-delivered payloads; no separate persona.
- NLB §1.1: no shared substrate with any other AR experience.

## Artifacts

- New: `Jarvis/Vision/AppVision/RealJarvisVisionApp.swift`, `Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionImmersiveView.swift`, `Tests/VisionBuildGuardTests.swift` (trivial compile test).
- Response: `Construction/Qwen/response/MK2-EPIC-10.md` (or `-skipped.md`).
