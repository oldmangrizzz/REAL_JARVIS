# UX-001 — Navigation Surfaces & HUD (Qwen Spec Order)

**Target model:** Qwen (coder-family, visual+systems reasoning)
**Scope owner:** Real Jarvis / Jarvis iOS+CarPlay+PWA+Unity
**Response path:** `Construction/Qwen/response/UX-001-response.md`
**Parallel spec:** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md` (engine — do not overlap)
**GLM active PR:** `Construction/GLM/spec/NAV-001-EXECUTE-PR1.md` — GLM is shipping `MapTileProvider` + `TileProviderOrchestrator` now. Your Phase B surfaces consume that protocol.
**Canon floor:** 250 tests, Swift 6 strict concurrency, SwiftPM + Xcode workspace

## Coordination with GLM (read first)

- **Contract boundary:** GLM defines `MapTileProvider`, `HazardOverlayFeature`, `SceneBriefing`, `RoutingProfile`. You consume them. You do NOT redeclare these types.
- **GLM PR schedule:** PR1 (tiles) → PR2 (router core) → PR3 (profiles) → PR4 (OSINT adapters + `HazardOverlayFeature`) → PR5 (`SceneBriefing`) → PR6 (pheromind).
- **Qwen unblocked NOW:** Phase A (design tokens) has zero GLM dependency. Ship Phase A first — it's what GLM's tile providers need for styling anyway.
- **Phase B (Map surface) is GLM-PR1-dependent.** You can design the SwiftUI view hierarchy and component boundaries in parallel, but the `MapTileProvider` protocol shape is authoritative from GLM's PR1. Do not guess the protocol; wait for GLM's `NAV-001-EXECUTE-PR1` response to freeze the types.
- **Phases C–E (HUD, PWA, Unity, Briefing):** design work only for now. No implementation until GLM PR2/PR4/PR5 lands the types you consume.

---

---

## 0. Read-First (non-negotiable context)

Before rendering anything, read and internalize:

1. `docs/COGNITIVE_ARCHITECTURE.md` — the UI is a **voice layer** surface. Restraint and anticipation matter more than density.
2. `Jarvis/Shared/Sources/JarvisShared/Principal.swift` — four tiers: `.operatorTier / .companion / .guestTier / .responder(role:)`. Every surface you design must declare which tiers see it.
3. `Jarvis/Shared/Sources/JarvisShared/JarvisBrandPalette.swift` — palette is canon. Tier ↔ palette mapping already exists (including `.responderOS`). Do not invent new colors per tier; compose from this.
4. `the_workshop.html`, `xr.grizzlymedicine.icu/`, `pwa/`, `cockpit/` — the GMRIWorkshop aesthetic you're continuing. Study it; don't break it.
5. `Jarvis/Sources/JarvisCore/OSINT/OSINTSourceRegistry.swift` — every tile, overlay, attribution you show ties to a registered source. Mapbox primary, MapLibre/OSM fallback.
6. `workshop/`, `elijah_frames/` — reference aesthetic pulls (volumetric, HUD-style, not flat-Material).

**Visual doctrine:** ATAK information density, taken to a Stark HUD class, rendered in the GMRIWorkshop house style. Readable in a moving ambulance at night and on a Vision Pro in a quiet lab. Both.

**Mission framing:** Same engine (GLM owns it), different access layers. Responder sees EMS-preferred routes + hazard overlays; Companion sees accessibility + parking + traffic; Operator sees full OSINT fusion. The **surface** is tier-shaped; the underlying engine is not.

---

## 1. Deliverables (in order)

### Phase A — Design system tokens
- Extract a `NavigationDesignTokens` doc (Swift file + companion markdown):
  - Color roles: `ground`, `primaryTrack`, `alternateTrack`, `hazardCritical`, `hazardElevated`, `hazardInfo`, `accessibilityAid`, `sceneBriefing`, `attributionFoot`.
  - Each role resolves to a `JarvisBrandPalette` token per tier. **Do not hardcode hex.**
  - Typography scale (HUD / CarPlay / PWA / Unity). Minimum legible size per surface, declared.
  - Iconography set: ATAK-derived pictograms but relicensed/originals only. List every icon + source + license. No copyright drift.

### Phase B — Map surface (SwiftUI + MapLibre view)
- `NavigationMapView` (SwiftUI) wrapping a `MapTileProvider` (defined by GLM — you consume it, do not define it). You accept a provider instance via injection; do not reference `MapboxCredentials` directly.
- Layer stack (ordered, z-indexed, each toggleable per tier):
  1. Base tiles
  2. Protected lands / recreation polygons (low opacity)
  3. Traffic + closures (TxDOT feed)
  4. Weather alerts (NOAA)
  5. Active fires (FIRMS)
  6. Seismic markers (USGS)
  7. Route track(s)
  8. Waypoints / marks
  9. Self-position + heading cone
- Every layer shows attribution automatically at the foot of the view. Attribution is mandatory, not optional.
- **Tier gating:** Responder sees 1–9 with EMS glyph overlays; Companion sees 1–4, 7–9 plus accessibility pins; Guest sees 1, 7, 9 only.

### Phase C — HUD / CarPlay surface
- Design (spec only, no implementation yet) a `CarPlayNavigationScene` using `CPMapTemplate` + overlays:
  - Turn-by-turn band (top), hazard ticker (right rail), pre-search briefing card (bottom, collapsible).
  - AR HUD overlay concept: heading reticle, next-maneuver ghost arrow, hazard halos. Specify how it degrades gracefully when AR isn't available.
- Safety: no modal dialogs while moving. Voice is primary I/O while in motion; touch is confirmatory.
- Declare which tiers can activate CarPlay HUD (responder + operator yes; companion yes for personal driving; guest no).

### Phase D — PWA / Unity parity
- PWA (`pwa/`, `xr.grizzlymedicine.icu/`): same layer stack, MapLibre-GL JS, same attribution discipline. Design the component boundaries (map shell, layer manager, briefing panel).
- Unity (`workshop/`, `vendor/` for bridges): volumetric variant — the same layers projected into a 3D table/plane. Spec the bridge contract (what JSON the Swift/engine side hands over, what Unity consumes). Do not duplicate engine logic in Unity.

### Phase E — Pre-search briefing card
- Consumes a `SceneBriefing` (GLM defines the type). Renders:
  - Destination summary (name, jurisdiction, nearest cross-streets)
  - Access notes (entrances, ADA if Companion; ingress/egress if Responder)
  - Surrounding hazards (current overlays within N meters)
  - "Last updated" per data source — non-negotiable honesty about staleness
- Card is audio-first — every element has a short spoken form prioritized for voice output.

### Phase F — Anti-goals (do NOT design)
- No routing math. No tile fetch logic. No OSINT adapter wiring. No credential handling. (GLM owns all of that.)
- No surfaces that read from unregistered sources. If you need a layer that isn't in `OSINTSourceRegistry`, file it under Open Questions — do not mock it in.
- No surfaces that present clinical decision support on Responder tier. Advocacy + situational awareness only. Do not draw "recommended dose" / "suggested intervention" widgets. Ever.
- No dark-mode-only or light-mode-only surfaces without both specified.

---

## 2. Interfaces you must NOT break

- `JarvisBrandPalette` tokens and tier mapping — extend, don't redefine.
- `Principal` tier identity — do not collapse `.responder(role:)` variants into a single surface without per-role capability notes.
- Existing Workshop/PWA aesthetic — your surfaces must look like they belong in the same product.

## 3. Output format (your response goes here)

Write your response to `Construction/Qwen/response/UX-001-response.md` with sections:

1. **Visual doctrine** (≤ 300 words). Anchor in ATAK + Stark + GMRIWorkshop. State what you will and won't borrow.
2. **Token manifest** — full list of `NavigationDesignTokens` roles with tier-by-tier palette resolution.
3. **Surface catalog** — for each surface (iOS Map, CarPlay HUD, PWA, Unity, Briefing Card): tier matrix, layer list, attribution plan, voice-fallback plan.
4. **Component tree sketches** — SwiftUI view hierarchy, PWA component boundaries, Unity scene graph. Names only; no full implementations.
5. **Iconography license ledger** — every glyph, its origin, its license, proof it's clean.
6. **Accessibility review** — contrast, motion, voice-first, colorblind safety. Per surface.
7. **Open questions** — anything in this spec wrong, ambiguous, or missing a data source. Do not mock unregistered sources; flag them.
8. **Risk log** — five+ risks (visual legibility in sunlight, AR degradation, tier leakage across surfaces, etc.) with mitigations.
9. **Sequencing** — PR plan, each ≤ ~400 net LOC of spec/design artifacts. Land the tokens first, the SwiftUI map surface second, CarPlay third.

## 4. Tone and standards

- Swift 5.9 for iOS bits. Web: stay inside the `pwa/` tech choices already made. Unity: C# only where the project already uses it.
- No new fonts without license text inline.
- No external icon sets without license.
- Every surface ships with dark + light themes derived from palette tokens, not hardcoded.

---

**Final reminder:** restraint. This is a HUD for someone whose mind is already firing a hundred parallel branches. Your job is to be *readable at a glance*, not to showcase density. Readable in the ambulance. Readable on the Vision Pro. Same doctrine, different substrate.
