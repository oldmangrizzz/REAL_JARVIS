# UX-001 — Navigation UI/UX Surfaces (Qwen Spec Order)

**Target model:** Qwen (Qwen3-Coder-Next)
**Scope owner:** Real Jarvis / QwenTeam
**Response path:** `Construction/Qwen/response/UX-001-response.md`
**Parallel spec:** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md` (engine — do not overlap)
**Canon floor:** 250 tests, Swift 5.9+, SwiftPM + Xcode workspace

---

## 0. Read-First (non-negotiable context)

Before writing a single line, read and internalize:

1. `docs/COGNITIVE_ARCHITECTURE.md` — three-layer doctrine (substrate / topology / gain). Navigation is a consumer of salience, not a replacement for it.
2. `Jarvis/Shared/Sources/JarvisShared/Principal.swift` — tier model (`.operatorTier / .companion / .guestTier / .responder(role:)`). Every capability you expose must honor tier.
3. `Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` — especially `clinicalExecutionFragments`. Responder tier is **advocacy + situational awareness**, never clinical execution.
4. `Jarvis/Sources/JarvisCore/OSINT/OSINTSourceRegistry.swift` — canonical open-source feeds. **You do not fetch from a host that isn't in this registry. Period.**
5. `Jarvis/Sources/JarvisCore/OSINT/WebContentFetchPolicy.swift` — any web read requires `SearchProvenance`. No direct scraping of denied hosts.
6. `Jarvis/Sources/JarvisCore/Credentials/MapboxCredentials.swift` — Mapbox secret token is operator-tier only. Tiles use public token.
7. `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift`, `Oscillator/MasterOscillator.swift` — substrate you will feed and listen to, not replace.

**Mission framing:** "Same engine, different access layers." This is **not** an EMS app. It is a universal navigation engine whose access surface changes per tier. Responder role (EMR/EMT/AEMT/EMTP) gets EMS-preferred routing; Companion tier gets accessibility/parking/traffic; Operator tier gets full open-source fusion. The engine is tier-agnostic; policies gate output.

**Doctrine keywords:** open sources not dark sources. Gray not black. Empowerment not replacement.

---

## 1. Deliverables (in order)

### Phase A — iOS Map Surface
- SwiftUI view `NavigationCockpitView` hosted in existing `JarvisMobileCore/JarvisCockpitView.swift` context.
- Map surface uses `MapKit` with `MKMapView` via `UIViewRepresentable`.
- Tier-based rendering:
  - `.operatorTier`: full route layering, traffic, FIRMS/fire, weather overlays.
  - `.companion`: accessibility tags, park-and-ride, curb cuts, elevator locations.
  - `.guestTier`: only route track + position, no overlays.
  - `.responder`: EMS-preferred route + hazards (fire, quake, weather) with TTL badges.
- CarPlay extension via `CPMapTemplate` optional (flag for later PR if blocked).

### Phase B — CarPlay HUD Surface
- CarPlay template `CPNavigationTemplate` for `CPApplicationTemplate`.
- HUD overlay: ETA, remaining distance, current heading, speed limit, basic guidance (turn icons only).
- No map imagery on HUD (use existing CarPlay map app overlay).
- Tier gating: same as iOS, but guest tier shows only ETA/distance.

### Phase C — PWA Surface
- Enhance existing `pwa/index.html` with map cockpit.
- Map surface uses Mapbox GL JS with public token.
- Overlay data via `HazardOverlayFeature` JSON from engine (same format as native).
- Responsive grid layout: `.mobile` (stacked) vs `.desktop` (sidebar + map).
- No WebGL if WebGPU not available → fallback to raster tiles.

### Phase D — Unity XR Surface (optional, low priority)
- Unity plugin scaffold only (no full implementation).
- Protocol `IXRNavigationService` for future AR overlay hooks.
- Empty implementation files with placeholders: `NavigationXRBridge.cs`, `XRHub.cs`.

### Phase E — Scene Briefing Surface
- Surface `SceneBriefingView` (SwiftUI) for destination pre-search context.
- Displays destination name, jurisdiction, access notes, active hazards, source attestations.
- Tier-gated content: operator tier sees full open-source citations; other tiers see curated summary.

### Phase F — Anti-goals (do NOT build)
- No engine logic. No routing algorithm. No OSINT fetching. (GLM owns all of that under NAV-001.)
- No direct Mapbox token in surface code — consume `MapTileProvider` from engine.
- No direct fetch from any OSINT source. No web scraping.
- No clinical phrasing or clinical decision support surface.

---

## 2. Interfaces you must NOT break

- `Principal` enum cases and `tierToken` encode/decode (existing round-trip tests must stay green).
- `CompanionCapabilityPolicy` voice + tunnel evaluation signatures.
- `OSINTSourceRegistry.canonical` membership checks.
- `WebContentFetchPolicy` signature — you may add overloads, not replace.
- Canon-gate floor in `.github/workflows/canon-gate.yml` — you **will** bump both the comment and the `[ "$EXECUTED" -lt N ]` check with every green test-count increase.

---

## 3. Tests — required shape

- Unit tests with mocked engine (no network, no map SDK).
- For each tier surface: happy-path + principal-gating + fallback-visibility.
- For `SceneBriefingView`: snapshot tests per tier (using `XCTestSnapshotTestCase`).
- Add all new tests under `Jarvis/Tests/JarvisMobileCoreTests/` and bump canon-gate floor once green.

---

## 4. Output format (your response goes here)

Write your response to `Construction/Qwen/response/UX-001-response.md` with sections:

1. **Design summary** (≤ 400 words). Name the abstractions. State what's tier-gated vs engine-consumed.
2. **File manifest** — every file you will create or modify, grouped by phase.
3. **Interface sketches** — Swift/SwiftUI/JS signatures only (no full bodies).
4. **Test matrix** — table: phase → test name → what it proves.
5. **Open questions** — anything in this spec you believe is wrong, ambiguous, or conflicts with existing canon. Cite file + line. Do not silently "fix" canon; flag it.
6. **Risk log** — at least five risks with mitigation. Include at least one UI-pattern risk and one performance/scale risk.
7. **Sequencing** — concrete PR plan (PR1 … PRn) small enough to land independently. Each PR ≤ ~500 net LOC, tests included.

---

## 5. Tone and standards

- Swift 5.9, `swift-format` defaults tolerated, no force-unwraps in new code.
- No third-party dependencies beyond what's already in `Package.swift` without explicit justification in your response.
- Every `struct`/`class` you introduce that crosses a tier boundary must carry a doc comment citing which tier consumes it and why.
- Comments only where they clarify — follow the house style (no narration).
- JavaScript/TypeScript: ES2020+, no `any`, TypeScript-enforced.
- Unity: C# 8.0+, nullable reference types enabled.

---

**Final reminder:** we work in the gray, not the black. Open sources, search-surfaced reads, never scraping a denied host via a back door. If a data capability requires going dark, say so in Open Questions and stop.
