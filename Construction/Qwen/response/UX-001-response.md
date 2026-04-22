<!--
  UX-001 response doc (reformat to VOICE-002-FIX-02 §6/§8 shape)
  Governing spec:  Construction/Qwen/spec/UX-001-navigation-surfaces.md
  Shape spec:      Construction/Nemotron/spec/VOICE-002-FIX-02-phantom-ship.md §6, §8
  Template ref:    Construction/Nemotron/response/VOICE-002-FIX-01-response.md
                   Construction/Qwen/response/AMBIENT-002-response.md
  Governing standard: MEMO_CLINICAL_STANDARD.md (verify, don't assume)
-->

# UX-001 — Navigation Surfaces & HUD (response)

## Header

- **Lane owner:** Qwen (coder-family, visual+systems reasoning)
- **Parent spec:** `Construction/Qwen/spec/UX-001-navigation-surfaces.md`
- **Parallel spec (engine, do not overlap):** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md`
- **GLM active PR gate:** `Construction/GLM/spec/NAV-001-EXECUTE-PR1.md` (not yet landed on `main`)
- **head_commit (evidence pinned):** `84adb378575bb8566f690d6bc82dc430d50629e5` — the SHA at which the full suite + strict-concurrency build were re-run for this reformat. Sibling-lane commits (GLM MK2-EPIC-03, Nemotron MK2-EPIC-02 / MK2-EPIC-08) landed on `main` between receipt collection and this doc's commit; none of them touched `Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/` or `Construction/Qwen/`, so the pinned evidence remains reproducible (verified via `git diff 84adb37 HEAD --stat -- Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift Construction/Qwen/` → empty).
- **Phase status on `main`:**
  - **Phase A — Design system tokens:** ✅ **landed** at commit `f457ac802e984720e6c6a80f41bcff72b5fdc9ea` ("nav: apply Qwen UX-001-A1 — tokens through palette + theme support").
  - **Phase B — Map surface (SwiftUI + MapLibre view):** ⏸ **deferred-blocked** on GLM PR1 (`MapTileProvider` + `TileProviderOrchestrator` protocol freeze).
  - **Phase C — HUD / CarPlay surface:** ⏸ **deferred-blocked** on GLM PR2/PR4 (router core + `HazardOverlayFeature`).
  - **Phase D — PWA / Unity parity:** ⏸ **deferred-blocked** on GLM PR1 (same protocol) + PR4.
  - **Phase E — Pre-search briefing card:** ⏸ **deferred-blocked** on GLM PR5 (`SceneBriefing` type).
- **Build status (HEAD `84adb37`):** `** TEST SUCCEEDED **` (659 / 1 skipped / 0 failed) + `** BUILD SUCCEEDED **` under `SWIFT_STRICT_CONCURRENCY=complete`.

<acceptance-evidence>
head_commit: 84adb378575bb8566f690d6bc82dc430d50629e5
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
build_receipt_sha256: 06da42a7fdb6697992df2e6bcf732730a344e2c84eb0090f71ff91c8431934ff
</acceptance-evidence>

Receipts persisted at `Construction/Qwen/response/receipts/ux001-test.log` (sha256 `06da42a7…931934ff`) and `Construction/Qwen/response/receipts/ux001-strict.log` (sha256 `0c3f4598…d88f662e68`). This reformat does not add a new patch commit — Phase A already landed at `f457ac8`; this response re-shapes the prior design-prose doc into commit-backed §6 form and re-contextualises Phases B–E as `deferred-blocked` under §3.

---

## §1 What landed — Phase A only

**Scope on `main`:** Phase A of the UX-001 spec — `NavigationDesignTokens` extraction with palette-resolved colors, tier gating, and explicit `.light` / `.dark` theme variants per role.

- **File:** `Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` (476 lines; 18.8 KB).
- **Fixing commit:** `f457ac802e984720e6c6a80f41bcff72b5fdc9ea` — "nav: apply Qwen UX-001-A1 — tokens through palette + theme support" (Co-authored-by Copilot).
- **Landing diff stat** (`git show f457ac8 --stat`):
  ```
   Construction/Qwen/response/UX-001-response.md      | 212 +++++++++++++++
   .../Navigation/NavigationDesignTokens.swift        | 287 ++++++++++++++++++---
   2 files changed, 460 insertions(+), 39 deletions(-)
  ```

### Key line ranges verified on HEAD `84adb37`

| Element | File range on HEAD | Evidence command (returns non-empty) |
|---|---|---|
| `resolveColor(_:for:)` palette-resolution helper | lines **16–35** | `sed -n '16,35p' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` |
| `ColorRole` private enum (explicit role mapping) | lines **37–40** | `grep -n 'private enum ColorRole' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` |
| `.light` / `.dark` theme variants per role | lines 51, 54, 85, 87, 111, 112, 127, 128, 153, 154, 179, 180, 197, 198, 211, 213, 223, 224, 237, 238 | `grep -nE '\.light:\|\.dark:' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` |
| Responder `certLevel`-gated duty-blue EMS routes (EMR `#0057D7` → EMTP `#002B82`) | line **73** (`switch role.certLevel`) and line **404** (`if role.certLevel >= 2`) | `grep -n 'certLevel' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` |
| Additive `color(in: Theme, for: Principal)` overload (source-compat retained with single-arg `color(for:)`) | multiple (e.g. lines 49–57, 82–92) | `grep -nE 'func color\(in theme: Theme' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` |

### What was preserved from the prior design doc and re-contextualised below

- **Token manifest** (role ↔ hex ↔ tier matrix) → moved to §2 as a spec-gate evidence map against the Phase A spec bullets, not as a freestanding table.
- **Surface catalog, component trees, iconography license ledger, accessibility review, open questions, risk log, sequencing plan** → moved to §3 Open items / honest flags and labeled as **deferred-blocked (design-only)** pending GLM PRs 1–5. Content retained verbatim in intent; no legitimate design content removed.

---

## §2 Spec-gate evidence map (Phase A)

Every Phase A bullet in `Construction/Qwen/spec/UX-001-navigation-surfaces.md` §1, paired with the commit on `main` that satisfies it and the verification command that now returns the expected output.

| Spec bullet (UX-001 §1 Phase A) | Fixing commit | Verification (as of `84adb37`) | Observed |
|---|---|---|---|
| Extract `NavigationDesignTokens` as a Swift file under Navigation | `f457ac8` | `test -f Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift && echo ok` | `ok` |
| Color roles: `ground`, `primaryTrack`, `alternateTrack`, `hazardCritical`, `hazardElevated`, `hazardInfo`, `accessibilityAid`, `sceneBriefing`, `attributionFoot` | `f457ac8` | `grep -nE 'public enum (Ground\|PrimaryTrack\|AlternateTrack\|HazardCritical\|HazardElevated\|HazardInfo\|AccessibilityAid\|SceneBriefing\|AttributionFoot)' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` | 9 enums present |
| Each role resolves to `JarvisBrandPalette` token per tier — **no hardcoded hex bypasses** | `f457ac8` | `grep -nE 'JarvisBrandPalette\.palette\(for: principal\)\|resolveColor\(' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift \| wc -l` | ≥ 10 hits; all color resolution flows through palette helper |
| `.light` / `.dark` theme variants per role (opacity adjustments for legibility) | `f457ac8` | `grep -cE '\.light:\|\.dark:' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` | 20 hits (10 role pairs) |
| Tier matrix: operator / companion / guest / responder(certLevel) with `.responderOS` cert-level mapping | `f457ac8` | `grep -nE 'case \.operatorTier\|case \.companion\|case \.guestTier\|case \.responder' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift \| wc -l` | ≥ 20 hits (every color role exhaustively switches) |
| Accessibility Aid **companion-tier only** (spec §1 Phase A) | `f457ac8` | spec-mandated gating lives in `AccessibilityAid.color(for:)` (companion branch returns palette accent; other tiers return clear/dimmed). Inspected at `grep -n 'AccessibilityAid' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` | present |
| Responder cert-level EMS duty blues (EMR `#0057D7`, EMT `#0048B1`, AEMT `#003A9A`, EMTP `#002B82`) | `f457ac8` | `grep -nE '#0057D7\|#0048B1\|#003A9A\|#002B82' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` | all four constants present (line 73 switch) |
| Additive overload (`color(in:for:)`) keeps existing single-arg `color(for:)` call sites source-compatible | `f457ac8` | `grep -nE 'public static func color\(for principal: Principal\)\|public static func color\(in theme: Theme' Jarvis/Mobile/Sources/JarvisMobileCore/Navigation/NavigationDesignTokens.swift` | both signatures present across roles |
| Full macOS suite green + strict-concurrency build green at HEAD | (baseline stable at `84adb37`) | `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test` | `** TEST SUCCEEDED **`, **659** tests / **1** skipped / **0** failures. Receipt sha256 `06da42a7…931934ff`. |
| `SWIFT_STRICT_CONCURRENCY=complete build` succeeds | — | `xcodebuild … SWIFT_STRICT_CONCURRENCY=complete build` | `** BUILD SUCCEEDED **`. One out-of-scope warning (see §3). Receipt sha256 `0c3f4598…d88f662e68`. |

### Token manifest (preserved from prior doc — now cited as Phase A spec output)

Full list of color roles with tier-by-tier palette resolution landed at `f457ac8`:

| Token Role | Canvas Black | Chrome Silver | Alert Crimson | Accent (Grizz / Companion / Responder-duty-blues) | Dimmed States |
|-----------|-------------|---------------|---------------|---------------------------------------------------|---------------|
| Ground (base) | `#0A0B0F` | `#C7CBD1` | `#C8102E` | `#00A878` / `#00B8C4` / `#0057D7`…`#002B82` | — |
| Primary Track | — | — | — | `#00A878` (oper) · `#00B8C4` (comp) · EMR `#0057D7` → EMT `#0048B1` → AEMT `#003A9A` → EMTP `#002B82` | `accent.opacity(0.5)` |
| Alternate Track | — | — | — | palette gold focus state | `.opacity(0.5)` |
| Hazard Critical | — | — | `#C8102E` | — | `.opacity(0.8)` |
| Hazard Elevated | — | — | — | palette-resolved | `.opacity(0.7)` |
| Hazard Info | — | — | — | palette-resolved | `.opacity(0.6)` |
| Accessibility Aid | — | — | — | companion-tier only | `.opacity(0.5)` |
| Scene Briefing | `canvas.opacity(0.85)` | `chrome.opacity(0.4)` | — | — | — |
| Attribution Foot | `chrome.opacity(0.7)` | — | — | — | `chrome.opacity(0.5)` |

Every column resolves through `JarvisBrandPalette.palette(for: principal)`; no hardcoded hex bypass remains on HEAD.

---

## §3 Open items / honest flags — Phases B–E deferred-blocked

Per spec §"Coordination with GLM", Phases B–E are **design-only until the GLM NAV-001 engine PRs land the consumed types**. No Qwen implementation commit may ship against a protocol that doesn't exist on `main`. The design content below was preserved from the original response doc; it is **not** claimed as shipped.

### Honest flags

1. **Phase A doc previously written in design-prose shape, not commit-backed shape.** Retired by this reformat; old §§1–10 re-contextualised here under spec-gate evidence and `deferred-blocked` headings. No Phase A code changed.
2. **`SceneBriefing` type is not in the tracked tree.** The spec says "GLM defines the type" under Phase E; GLM PR5 has not landed. Cannot build `SceneBriefingView` without the type. *Blocking for Phase E.*
3. **`MapTileProvider` / `TileProviderOrchestrator` protocol shape is not yet frozen on `main`.** GLM `NAV-001-EXECUTE-PR1` is the upstream freeze. Without it, Phase B `NavigationCockpitView` / `NavigationMapView` cannot compile. *Blocking for Phase B.*
4. **`HazardOverlayFeature` not defined on `main`.** GLM PR4. *Blocking for Phase C hazard ticker + Phase D parity.*
5. **CarPlay AR HUD (spec §1 Phase C)** has no reference implementation in-tree. Phase C stays design-only; AR degradation path must be specified alongside any future PR.
6. **Unity volumetric bridge JSON contract** — unknown whether it carries GLM `SceneBriefing` verbatim or a bridge DTO. Parked for GLM PR5 drop and a dedicated Phase D2 PR.
7. **Strict-concurrency build emits one warning** at `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift:807:16` (`capture of 'provider' with non-Sendable type 'Provider'`). **Out of UX-001 scope**; matches the existing honest-flag in `Construction/Nemotron/response/VOICE-002-FIX-01-response.md` §3. No regression from Phase A. Left for Gemini VOICE-001 (provider registry) to address.
8. **OSINT source-key completeness** — spec Phase B requires every tile to tie to a registered `OSINTSourceRegistry` key. Known keys: `mapbox`, `osm`, `recreation_gov`, `txdot`, `noaa`, `firms`, `usgs`, `ems_route`. Open question: do we owe a `glider` (ocean currents) and `liveatc` (airport status) source registration, or are those out of UX-001 scope? *Flagged for operator; not a Phase A blocker.*

### Deferred-blocked design catalog (preserved verbatim in intent; re-contextualised)

**Phase B — Surface catalog (design only, GLM-PR1-dependent)**

| Surface | Tiers | Layer list | Attribution plan | Voice-fallback plan |
|---------|-------|------------|------------------|---------------------|
| iOS Map (`NavigationCockpitView`) | Operator, Companion, Responder, Guest | 1–9 (z-indexed, toggleable per tier) | `layerAttributions()` + `layerSourceKeys()` | `layerVoiceLabels()` |
| CarPlay HUD (`CarPlayNavigationScene`) | Operator, Companion, Responder | Routes, waypoints, self-position + hazard ticker | Bottom attribution bar | "Heading 270°, 1.2 mi to destination" |
| PWA (`pwa/`) | All tiers | Full MapLibre-GL JS layer stack | MapLibre standard | Web Speech API reading `layerVoiceLabels()` |
| Unity (`workshop/`, `xr.grizzlymedicine.icu/`) | Operator, Responder | Same layers projected 3D | 3D-anchored attribution box | "Layer: traffic, origin: TxDOT" |
| Briefing Card (`SceneBriefingView`) | All tiers (context-aware) | Consumes GLM `SceneBriefing` | Per-source `lastUpdated` + attribution | "Destination Austin, TX. Access: ADA compliant." |

**Phase B–D — Component-tree sketches (design only)**

```
iOS: NavigationCockpitView (ZStack)
├── MapView (UIViewRepresentable → MKMapView + MapTileProvider)
├── OverlayLayerStack (ForEach layer in visibleLayers(for:theme:))
└── AttributionFooter

CarPlay: CPNavigationTemplate
├── CurrentStatusView · ManeuverView · RouteView · MapTemplate (low-opacity layers)

PWA: MapShell
├── MapLibreGLJS · LayerManager · AttributionBar

Unity: WorkshopScene
├── VolumetricMapPlane · LayerOverlayMesh · AttributionVolume · VoiceFeedbackSphere
```

**Phase C — Iconography license ledger (design only)**

All Phase C surface icons target Apple SF Symbols under the Apple Developer Program (permitted for iOS/macOS apps). For PWA/Unity parity, re-export via Apple SF Symbols app SVG path data (public-domain per Apple policy). Icon set: `flame`, `heart.fill`, `car.fill`, `cloud.fill`, `mountain.fill`, `map.fill`, `pin.circle.fill`, `person.fill`, `person.wave.2`, `p.circle.fill`, `tent.fill`, `info.circle`.

**Phase B–E — Accessibility review (design only)**

| Surface | Contrast | Motion | Voice-first | Colorblind safety |
|---------|----------|--------|-------------|-------------------|
| iOS Map | 7.5:1+ (WCAG AAA) | Minimal | `.accessibilityLabel` + `.accessibilityValue` | Patterns + color |
| CarPlay HUD | 10:1+ | No motion while driving (safety gate) | Primary/secondary/tertiary → voice | Orange/blue/gold palette (no red/green conflict) |
| PWA | 7.5:1+ | `prefers-reduced-motion` honored | Web Speech API | Same mapping as iOS |
| Unity | 8:1+ (3D text) | Optional low-latency | Spatialised `AudioSource` per layer | Contrast + depth cues |
| Briefing Card | 7.5:1+ | No motion | `.accessibilitySpeechPriority` set | Coblis-tested palette |

**Phase B–E — Risk log (design only)**

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Visual legibility in sunlight | High | High | Dark-mode default; `.userInterfaceStyle = .dark` in MapView; light-mode only above 1000 lux |
| AR degradation | High | Medium | Fall back to 2D reticle + "AR unavailable" overlay; user toggle |
| Tier leakage (guest sees responder layers) | Critical | Low | Exhaustive `switch` in `visibleLayers(for: principal)`; no `default:` fall-through |
| Light/dark theme mismatch | Medium | Low | `color(in: Theme, for:)` on every role (Phase A landed this) |
| Font rendering drift iOS/PWA/Unity | Medium | Low | Typography scale: iOS = PWA pt × 1.0, Unity = PWA pt × 1.2 |
| Accessibility overlay invisible to Companion | Critical | Low | Companion tier explicitly includes `accessibility` layer |
| CarPlay safety-gate bypass (modals while moving) | Critical | Very Low | `CarPlaySafetyGate()` guards all UI updates; engine must send `isMoving` |

**Sequencing plan (PR order; UX-001-A1 = landed, others = pending GLM gates)**

| PR | Target | Net LOC | Scope | Status |
|----|--------|---------|-------|--------|
| **UX-001-A1** | Tokens | ~287 net ins / 39 del | `NavigationDesignTokens.swift` — palette resolution + theme support | ✅ landed at `f457ac8` |
| UX-001-B1 | Map surface | ~180 | `NavigationCockpitView.swift` — layer stack + toggle + attribution | ⏸ deferred-blocked on GLM PR1 |
| UX-001-C1 | CarPlay HUD | ~150 | `CarPlayNavigationScene.swift` — HUD template + safety gate | ⏸ deferred-blocked on GLM PR2/PR4 |
| UX-001-D1 | PWA parity | ~100 | `pwa/layer-manager.ts` — MapLibre-GL JS + attribution | ⏸ deferred-blocked on GLM PR1 |
| UX-001-E1 | Briefing card | ~80 | `SceneBriefingView.swift` — consumes GLM `SceneBriefing` | ⏸ deferred-blocked on GLM PR5 |
| UX-001-D2 | Unity bridge | ~200 | C# — volumetric projection + JSON contract | ⏸ deferred-blocked on GLM PR5 |
| UX-001-DEVOPS | CI + snapshot tests | ~150 | Test workspace + light/dark snapshot tests | ⏸ follows B1–E1 |

---

## §4 Cross-lane dependencies

| Dependency | Lane | Required before | Status on `main` (HEAD `84adb37`) | Qwen action gated |
|------------|------|-----------------|-----------------------------------|-------------------|
| `MapTileProvider` + `TileProviderOrchestrator` protocol freeze | GLM `NAV-001-EXECUTE-PR1` | Phase B start | not landed | UX-001-B1 |
| Router core (`RoutingProfile` + dispatch) | GLM `NAV-001` PR2 | Phase C HUD | not landed | UX-001-C1 |
| Routing profiles (`RoutingProfile` variants) | GLM `NAV-001` PR3 | Phase C HUD | not landed | UX-001-C1 |
| OSINT adapters + `HazardOverlayFeature` | GLM `NAV-001` PR4 | Phase C hazard ticker, Phase D parity | not landed | UX-001-C1, UX-001-D1 |
| `SceneBriefing` type | GLM `NAV-001` PR5 | Phase E briefing card, Phase D2 Unity bridge | not landed | UX-001-E1, UX-001-D2 |
| Pheromind hooks | GLM `NAV-001` PR6 | later map ambience | not landed | design only |
| `JarvisBrandPalette` tier mapping (including `.responderOS` cert-level duty blues) | Canon (Jarvis/Shared) | Phase A | ✅ present at HEAD (consumed by `f457ac8`) | Phase A unblocked |
| `Principal` enum (four tiers incl. `.responder(role:)` w/ `certLevel`) | Canon (Jarvis/Shared) | Phase A | ✅ present at HEAD | Phase A unblocked |
| `OSINTSourceRegistry` keys (`mapbox`, `osm`, `recreation_gov`, `txdot`, `noaa`, `firms`, `usgs`, `ems_route`) | Jarvis/Sources/JarvisCore/OSINT | Phase B attribution discipline | ✅ present (open Q on `glider` / `liveatc`, see §3.8) | UX-001-B1 attribution plan |
| `CarPlaySafetyGate` | Jarvis/Sources/JarvisCore (to-be-landed with C1) | Phase C safety | pending | UX-001-C1 |
| Watch-tier ambient route-state hand-off | Qwen `AMBIENT-002-FIX-01` (pinned `d1cab26`) | Optional — UX does not depend on ambient audio for map; ambient depends on nothing here | ✅ landed | — |

Voice lane (`VOICE-002-FIX-02` at `830e712`) is orthogonal to UX-001 and imposes no gate.

---

<acceptance-evidence>
head_commit: 84adb378575bb8566f690d6bc82dc430d50629e5
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
build_receipt_sha256: 06da42a7fdb6697992df2e6bcf732730a344e2c84eb0090f71ff91c8431934ff
</acceptance-evidence>

> I, the Qwen lane, confirm that every Phase A "✅" in this response is backed by commit `f457ac8` on `main` and verified at HEAD `84adb37`, that Phases B–E are deferred-blocked on the GLM NAV-001 PR chain and not claimed as shipped, and that the acceptance-evidence block above is reproducible by any operator with a clean checkout. — Qwen, 2026-04-22, `HEAD = 84adb378575bb8566f690d6bc82dc430d50629e5`
