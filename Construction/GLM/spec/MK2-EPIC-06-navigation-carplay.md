# MK2-EPIC-06 — Navigation + CarPlay Completion

**Lane:** GLM (infra / nav)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4
**Depends on:** `NAV-001-universal-navigation-engine` (in flight), `UX-001-navigation-surfaces` (in flight), MK2-EPIC-01
**Priority:** P1
**Canon sensitivity:** LOW

---

## Why

The pre-existing `UX-001-build-hardening/spec-sheet.md` enumerated 5 critical CarPlay / navigation build breaks (AnyJSON Codable conflicts, platform-guard misses, SwiftUI palette init collisions). NAV-001 (in flight) builds the universal nav engine. But no epic closes the loop: **navigation rendered on CarPlay and on the PWA with a shared data contract, driven from the host**.

Mark II requires: operator says "navigate home" → route computed → rendered on CarPlay head unit, mirrored on PWA map panel, telemetry logged.

## Scope

### In

1. **Platform-guard sweep** (preserves UX-001 fixes):
   - Verify all files under `Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/` and `.../CarPlay/` compile under each target via EPIC-01's `build-all.sh`.
   - Any remaining `#if canImport(CarPlay)` omissions → add.
   - Audit `AnyJSON`/`AnyCodable` types for `Sendable` compliance; no `@unchecked Sendable`.

2. **End-to-end nav happy path**:
   - Host receives `JarvisRemoteAction.navigate(destination:)` via tunnel.
   - `NAV-001` engine computes route (Mapbox or MapKit based on `NAV-001` output).
   - Response sent back as `JarvisRemoteResponse.navigationRoute(route)` containing polyline + maneuvers.
   - iPhone renders `NavigationCockpitView`; CarPlay renders `CarPlayNavigationScene` — both subscribe to same `NavigationStore`.
   - PWA nav panel consumes the same payload via WebSocket.

3. **CarPlay entitlement smoke**:
   - `scripts/smoke/carplay-entitlement.sh` — reads `*.entitlements` files, asserts `com.apple.developer.carplay-maps` or equivalent is present on the iPhone target (exits 0/1).

4. **Nav smoke**:
   - `scripts/smoke/nav-happy-path.sh` — CLI triggers a fake `navigate` intent with source/destination, asserts a valid polyline comes back and a `nav.route.computed` telemetry event is emitted.

### Out

- Do NOT ship offline tiles (Mark III).
- Do NOT implement turn-by-turn voice announcements inside this epic — coordinate with EPIC-05 voice pipeline (reuse its TTS).
- Do NOT add third-party nav SDKs beyond those already in `NAV-001`.

## Acceptance Criteria

- [ ] `scripts/smoke/nav-happy-path.sh` exits 0.
- [ ] `scripts/smoke/carplay-entitlement.sh` exits 0.
- [ ] `xcodebuild build -scheme RealJarvisPhone` and `-scheme RealJarvisPad` green.
- [ ] New tests ≥ 6: navigation contract roundtrip, platform-guard compile assertions, CarPlay scene init, PWA payload compatibility (JSON shape test), route cache eviction, destination validation.

## Invariants

- PRINCIPLES §2: prefer Mapbox creds from env-only path (see earlier `mapbox-creds` tests); no hard-coded tokens.
- EPIC-02 auth token required on the nav tunnel request.

## Artifacts

- Potentially modified: `Mobile/Sources/JarvisMobileCore/Navigation/*`, `Mobile/Sources/JarvisMobileCore/CarPlay/*`, `pwa/index.html`, `Shared/TunnelModels.swift`.
- New: `scripts/smoke/nav-happy-path.sh`, `scripts/smoke/carplay-entitlement.sh`, `Tests/NavigationContractTests.swift`.
- Response: `Construction/GLM/response/MK2-EPIC-06.md`.
