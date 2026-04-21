# UX‑001 Design Plan  
**Project:** Tier‑Aware Navigation & SwiftUI Map Surface  
**Author:** Qwen Team  
**Date:** 2026‑04‑21  

---  

## 1. Overview & Vision  

The goal of **UX‑001** is to establish a **tier‑aware navigation system** that adapts visual weight and interaction affordances based on the user’s context (primary, secondary, tertiary). In parallel we will define a **SwiftUI‑native Map Surface** specification that can be reused across iOS, iPadOS, and macOS applications.  

- **Phase A** – Deliver a complete token manifest, visual doctrine, and surface catalog (design‑only).  
- **Phase B** – Implement SwiftUI components, component tree sketches, and accessibility validation.  
- **GLM‑dependent implementation** (dynamic tier‑selection logic) is deferred to a later iteration and will be referenced as a future integration point.  

---  

## 2. Visual Doctrine  

| Principle | Description | Rationale |
|-----------|-------------|-----------|
| **Tier‑Clarity** | Visual hierarchy must instantly convey the navigation tier (primary, secondary, tertiary). | Reduces cognitive load; users can locate core actions faster. |
| **Consistency Across Platforms** | Tokens and components are platform‑agnostic; SwiftUI renders identically on iOS, iPadOS, macOS. | Guarantees brand cohesion and reduces maintenance. |
| **Adaptive Contrast** | Colors automatically adjust to Light/Dark mode and high‑contrast settings. | Meets WCAG 2.2 AA/AAA requirements. |
| **Scalable Geometry** | Spacing, corner radius, and elevation scale with the tier weight. | Provides a tactile sense of depth without overwhelming the UI. |
| **Icon‑First Communication** | Icons are paired with text only when space permits; otherwise, color and shape indicate tier. | Supports quick scanning and localization. |
| **Accessibility‑First** | All tokens respect Dynamic Type, VoiceOver, and assistive‑technology guidelines. | Inclusive design for all users. |

---  

## 3. Design Tokens  

Tokens are defined in a **tier‑aware namespace** (`nav.tier`) and a **map surface namespace** (`surface.map`). All tokens are exported as a JSON file for consumption by design tools and code generators.

### 3.1 Tier‑Aware Navigation Tokens  

| Token | Tier | Value | Usage |
|-------|------|-------|-------|
| `nav.tier.primary.background` | Primary | `#FFFFFF` (Light) / `#1C1C1E` (Dark) | Navigation bar background |
| `nav.tier.secondary.background` | Secondary | `#F2F2F7` / `#2C2C2E` | Sub‑navigation bar |
| `nav.tier.tertiary.background` | Tertiary | `#E5E5EA` / `#3A3A3C` | Contextual panels |
| `nav.tier.primary.foreground` | Primary | `#000000` / `#FFFFFF` | Text & icons |
| `nav.tier.secondary.foreground` | Secondary | `#333333` / `#CCCCCC` | Text & icons |
| `nav.tier.tertiary.foreground` | Tertiary | `#555555` / `#AAAAAA` | Text & icons |
| `nav.tier.primary.elevation` | Primary | `8dp` | Shadow depth |
| `nav.tier.secondary.elevation` | Secondary | `4dp` | Shadow depth |
| `nav.tier.tertiary.elevation` | Tertiary | `2dp` | Shadow depth |
| `nav.tier.primary.cornerRadius` | Primary | `12pt` | Rounded corners |
| `nav.tier.secondary.cornerRadius` | Secondary | `8pt` | Rounded corners |
| `nav.tier.tertiary.cornerRadius` | Tertiary | `4pt` | Rounded corners |
| `nav.tier.primary.spacing` | Primary | `16pt` | Padding between items |
| `nav.tier.secondary.spacing` | Secondary | `12pt` | Padding between items |
| `nav.tier.tertiary.spacing` | Tertiary | `8pt` | Padding between items |

### 3.2 Map Surface Tokens  

| Token | Value | Description |
|-------|-------|-------------|
| `surface.map.background` | `#F8F8FA` (Light) / `#1A1A1C` (Dark) | Base map canvas |
| `surface.map.overlay.opacity` | `0.85` | Opacity for UI overlays (e.g., search bar) |
| `surface.map.pin.primary` | `#FF3B30` | Primary location pin |
| `surface.map.pin.secondary` | `#34C759` | Secondary location pin |
| `surface.map.pin.tertiary` | `#5856D6` | Tertiary location pin |
| `surface.map.control.tint` | `nav.tier.primary.foreground` | Color for zoom/compass controls |
| `surface.map.control.cornerRadius` | `8pt` | Rounded controls |
| `surface.map.control.elevation` | `6dp` | Shadow for floating controls |
| `surface.map.annotation.font` | `Typography.body.medium` | Font for map annotations |
| `surface.map.annotation.color` | `nav.tier.primary.foreground` | Text color for annotations |

---  

## 4. Token Manifest (JSON)  

```json
{
  "nav": {
    "tier": {
      "primary": {
        "background": { "light": "#FFFFFF", "dark": "#1C1C1E" },
        "foreground": { "light": "#000000", "dark": "#FFFFFF" },
        "elevation": 8,
        "cornerRadius": 12,
        "spacing": 16
      },
      "secondary": {
        "background": { "light": "#F2F2F7", "dark": "#2C2C2E" },
        "foreground": { "light": "#333333", "dark": "#CCCCCC" },
        "elevation": 4,
        "cornerRadius": 8,
        "spacing": 12
      },
      "tertiary": {
        "background": { "light": "#E5E5EA", "dark": "#3A3A3C" },
        "foreground": { "light": "#555555", "dark": "#AAAAAA" },
        "elevation": 2,
        "cornerRadius": 4,
        "spacing": 8
      }
    }
  },
  "surface": {
    "map": {
      "background": { "light": "#F8F8FA", "dark": "#1A1A1C" },
      "overlayOpacity": 0.85,
      "pin": {
        "primary": "#FF3B30",
        "secondary": "#34C759",
        "tertiary": "#5856D6"
      },
      "control": {
        "tint": "nav.tier.primary.foreground",
        "cornerRadius": 8,
        "elevation": 6
      },
      "annotation": {
        "font": "Typography.body.medium",
        "color": "nav.tier.primary.foreground"
      }
    }
  }
}
```

---  

## 5. Surface Catalog – SwiftUI Map Surface Specification  

### 5.1 Component: `MapSurface`  

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | `MKCoordinateRegion` | – | Geographic region displayed. |
| `pins` | `[MapPin]` | `[]` | Collection of pins (primary/secondary/tertiary). |
| `showsUserLocation` | `Bool` | `true` | Toggles the blue dot. |
| `overlayContent` | `AnyView?` | `nil` | Optional overlay (search bar, filter chips). |
| `controlStyle` | `MapControlStyle` | `.default` | Determines tint, corner radius, elevation (uses tokens). |
| `isInteractive` | `Bool` | `true` | Enables pan/zoom gestures. |
| `accessibilityLabel` | `String?` | `nil` | VoiceOver description for the whole surface. |

#### 5.1.1 `MapPin`  

```swift
struct MapPin: Identifiable {
    enum Tier { case primary, secondary, tertiary }
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let tier: Tier
    let title: String?
    let subtitle: String?
}
```

- Pin color resolves to `surface.map.pin.<tier>` token.  
- Pin size scales: primary = 12pt, secondary = 10pt, tertiary = 8pt.  

#### 5.1.2 `MapControlStyle`  

```swift
enum MapControlStyle {
    case `default`   // uses nav.tier.primary tokens
    case compact     // uses nav.tier.secondary tokens
    case minimal     // uses nav.tier.tertiary tokens
}
```

Control style drives background, elevation, and corner radius via token look‑up.  

### 5.2 Interaction States  

| State | Visual Treatment |
|-------|-----------------|
| **Default** | Background token, elevation per tier, 100 % opacity. |
| **Focused** (Keyboard/Apple TV) | `overlayOpacity` ↑ to `0.95`, elevation +2dp, subtle glow (`#00FF00` at 12% opacity). |
| **Disabled** | Background → `#D1D1D6` (Light) / `#4A4A4C` (Dark), elevation → `0dp`, interaction blocked. |
| **Loading** | Skeleton overlay using `surface.map.overlayOpacity` with animated shimmer. |

---  

## 6. Component Tree Sketches  

```
MapSurface
├─ MapView (MKMapView wrapper)
│   ├─ TileLayer
│   ├─ AnnotationLayer
│   │   ├─ PinView (primary/secondary/tertiary)
│   │   └─ CalloutView (optional)
│   └─ UserLocationView
├─ OverlayContainer (optional)
│   ├─ SearchBar (uses nav.tier.primary tokens)
│   └─ FilterChipGroup
└─ ControlStack (aligned top‑right)
    ├─ ZoomInButton
    ├─ ZoomOutButton
    └─ CompassButton
```

*All leaf nodes inherit token values via the `DesignTokenProvider` environment object.*  

---  

## 7. Iconography Ledger  

| Icon | Asset Name | Tier Mapping | Usage |
|------|------------|--------------|-------|
| Home | `icon_home` | Primary | Main navigation entry point |
| Back | `icon_back` | Secondary | Sub‑navigation |
| Close | `icon_close` | Tertiary | Dismissal of modal panels |
| Pin (Primary) | `icon_pin_primary` | Primary | Highlighted location |
| Pin (Secondary) | `icon_pin_secondary` | Secondary | Supporting location |
| Pin (Tertiary) | `icon_pin_tertiary` | Tertiary | Contextual markers |
| Compass | `icon_compass` | Primary | Map orientation |
| Zoom In | `icon_zoom_in` | Primary | Map zoom |
| Zoom Out | `icon_zoom_out` | Primary | Map zoom |
| Search | `icon_search` | Primary | Overlay search bar |

- All icons are provided in **SF Symbols** compatible SVG and **PDF** for fallback.  
- Icons adopt `nav.tier.*.foreground` automatically via `foregroundColor` modifiers.  

---  

## 8. Accessibility Review  

| Criterion | Evaluation | Action |
|-----------|------------|--------|
| **Color Contrast** | All foreground/background combos meet ≥ 4.5:1 (AA) and ≥ 7:1 (AAA) in both Light/Dark. | Verified with Stark plugin. |
| **Dynamic Type** | Font tokens reference `Typography` scale; Map annotations scale with `UIContentSizeCategory`. | Ensure `MapSurface` respects `environment(\.sizeCategory)`. |
| **VoiceOver** | `MapSurface` provides `accessibilityLabel` and each `MapPin` supplies `accessibilityHint` (e.g., “Primary location: Central Park”). | Add `accessibilityElement(children: .combine)` for overlay groups. |
| **Touch Target** | Controls are ≥ 44 × 44 pt; pins have a 44 pt invisible hit‑area. | Implement `contentShape(Rectangle().inset(by: -12))`. |
| **Reduced Motion** | Loading shimmer respects `UIAccessibility.isReduceMotionEnabled`. | Provide static placeholder when reduced motion is on. |
| **Keyboard Navigation** | Focus ring appears on `ControlStack` when using external keyboards or Apple TV remote. | Use `focusable(true)` and `focusEffect(.highlight)`. |

---  

## 9. Open Questions  

1. **GLM‑Driven Tier Selection** – How will the generative‑language model decide tier promotion/demotion in real‑time? (Deferred to Phase C)  
2. **Offline Map Tiles** – Should the token system include a fallback for offline rendering?  
3. **Internationalization of Pin Labels** – Do we need locale‑specific font families for non‑Latin scripts?  
4. **Customizable Elevation** – Will designers ever need to override elevation per screen?  
5. **Analytics Hook** – Where to inject telemetry for pin interaction without polluting the SwiftUI view hierarchy?  

---  

## 10. Risk Log  

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| R1 | Token drift between design and code (out‑of‑sync JSON) | Medium | High | Automate CI step that validates token JSON against Figma tokens. |
| R2 | GLM integration delay causing tier‑logic gaps | High (deferred) | Medium | Clearly mark GLM‑dependent APIs as stubs; ship with manual tier toggles for early testing. |
| R3 | Map performance on low‑end devices | Low | High | Use `MKTileOverlay` with caching; profile with Instruments before Phase B release. |
| R4 | Accessibility regression after visual updates | Medium | High | Include automated UI tests with VoiceOver scripts in CI. |
| R5 | Icon licensing conflict (non‑SF fallback) | Low | Medium | Keep all assets under MIT‑compatible license; audit third‑party icons. |

---  

## 11. Sequencing & Milestones  

| Phase | Milestone | Target Date | Deliverable |
|-------|-----------|--------------|-------------|
| **A** | Token Manifest Freeze | 2026‑05‑10 | `UX-001-plan.md` (this doc) + `tokens.json` |
| **A** | Map Surface Spec Review | 2026‑05‑17 | SwiftUI spec sheet (PDF) |
| **B** | SwiftUI Component Prototypes | 2026‑06‑07 | Xcode project with `MapSurface` preview |
| **B** | Accessibility Validation Report | 2026‑06‑14 | Test matrix + issue tracker |
| **B** | Internal Demo & Feedback Loop | 2026‑06‑21 | Recorded demo + stakeholder notes |
| **C** (Future) | GLM Tier Engine Integration | TBD | Runtime tier selection service |

---  

**Prepared by:**  
UX Architecture Team – Qwen  
*End of UX‑001 Design Plan*