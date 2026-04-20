# UX-001 Response — Navigation UI/UX Surfaces (Qwen Response)

**Target model:** Qwen (Qwen3-Coder-Next)  \n**Response file:** `Construction/Qwen/response/UX-001-response.md`  \n**Parallel spec:** `Construction/GLM/spec/NAV-001-universal-navigation-engine.md`

---

## 1. Design summary

The surface layer implements tier-gated navigation UIs across iOS, CarPlay, PWA, and Unity scaffolds. Four main abstractions drive the design:

- **`NavigationCockpitView`** (iOS/SwiftUI) — hosts map, route track, and overlay layers. Consumes `MapTileProvider` and `HazardOverlayFeature[]` from engine. Tier-gates visibility of traffic, FIRMS, weather, EMS-preferred routing.
- **`CPNavigationTemplate`** (CarPlay) — minimal HUD overlay with ETA, distance, heading, basic turn icons. Uses same engine data via `SceneBriefing` context.
- **`NavigationPWA`** (PWA index.html) — responsive Grid + Mapbox GL JS cockpit. Same overlay JSON as native.
- **`IXRNavigationService`** (Unity C# interface) — empty bridge scaffold for future AR overlays. No implementation required this spec.

**Tier-gated capabilities:**
- `.operatorTier`: full overlays (traffic, fire, weather, quake), full engine data, open-source citations.
- `.companionTier`: accessibility overlays, parking tags, curated surface.
- `.guestTier`: route track + position only, no overlays.
- `.responder(role:)`: EMS-preferred route + hazard overlays with TTL badges.

Surface code never fetches; it consumes data injected by engine. MapKit/Mapbox GL JS use public tokens. No clinical phrasing — situational awareness only.

---

## 2. File manifest

### Phase A — iOS Map Surface
- **Create:** `Jarvis/Sources/JarvisMobileCore/Navigation/NavigationCockpitView.swift` (SwiftUI + MapKit)
- **Create:** `Jarvis/Sources/JarvisMobileCore/Navigation/MapLayerView.swift` (overlay layer composition)
- **Modify:** `Jarvis/Sources/JarvisMobileCore/JarvisCockpitView.swift` (wire cockpit entry)
- **Create:** `Jarvis/Tests/JarvisMobileCoreTests/Navigation/NavigationCockpitViewTests.swift`

### Phase B — CarPlay HUD Surface
- **Create:** `Jarvis/Sources/JarvisMobileCore/CarPlay/CarPlayNavigationExtensionViewController.swift`
- **Create:** `Jarvis/Sources/JarvisMobileCore/CarPlay/CPNavigationTemplate+Builder.swift`
- **Create:** `Jarvis/Tests/JarvisMobileCoreTests/CarPlay/CarPlayNavigationTests.swift`

### Phase C — PWA Surface Enhancements
- **Modify:** `pwa/index.html` (add cockpit grid + map block)
- **Create:** `pwa/js/navigation.js` (Mapbox GL initialization, overlay renderer)
- **Create:** `Jarvis/Tests/JarvisPWATests/OverlayRenderingTest.html` (Jest)

### Phase D — Unity XR Bridge (scaffold)
- **Create:** `xr.grizzlymedicine.icu/Unity/NavigationXRBridge.cs` (empty interface)
- **Create:** `xr.grizzlymedicine.icu/Unity/XRHub.cs` (placeholder)
- **Create:** `xr.grizzlymedicine.icu/Unity/NavigationXRBridge.cs.meta` (meta)

### Phase E — Scene Briefing Surface
- **Create:** `Jarvis/Sources/JarvisMobileCore/Navigation/SceneBriefingView.swift`
- **Create:** `Jarvis/Sources/JarvisMobileCore/Navigation/SourceAttestationView.swift`
- **Create:** `Jarvis/Tests/JarvisMobileCoreTests/Navigation/SceneBriefingViewTests.swift`

### Phase F — Anti-goals (none)
No files needed; anti-goals enforced by code review and test coverage.

---

## 3. Interface sketches

### iOS / SwiftUI

```swift
// NavigationCockpitView
public struct NavigationCockpitView: View {
    @StateObject private var cockpitModel: NavigationCockpitModel
    
    public init(principal: Principal, tileProvider: any MapTileProvider) {
        self.cockpitModel = NavigationCockpitModel(principal: principal, tileProvider: tileProvider)
    }
    
    public var body: some View {
        Map(coordinateRegion: $cockpitModel.region,
            annotationItems: cockpitModel routeAnnotations)
        { item in
            MapMarker(coordinate: item.coordinate)
        }
        .overlay { ForEach(cockedOverlays) { ... } }
        .environmentObject(cockpitModel)
    }
}

public class NavigationCockpitModel: ObservableObject {
    public let principal: Principal
    public let tileProvider: any MapTileProvider
    
    @Published public var region: MapRegion
    @Published public var overlays: [HazardOverlayFeature]
    
    public init(principal: Principal, tileProvider: any MapTileProvider) { ... }
}
```

### CarPlay

```swift
extension CarPlayNavigationExtensionViewController: CPApplicationDelegate {
    public func application(_ application: CPApplication, 
                            didConnectInterface controller: CPInterfaceController) {
        let template = CPNavigationTemplate()
        controller.setRootTemplate(template, animated: true)
    }
}

public struct CPNavigationHUD: Equatable {
    public let eta: TimeInterval
    public let distanceRemaining: CLLocationDistance
    public let heading: Double
    public let turnIcon: CPNavigationTemplate.TurnIcon?
}
```

### PWA / JavaScript

```typescript
// navigation.js
export class NavigationCockpit {
    private map: mapboxgl.Map;
    private overlays: Map<string, HazardOverlayFeature[]>;

    constructor(public token: string, public principal: Principal) {
        this.map = new mapboxgl.Map({ container: 'map', style: this.styleUrl });
    }

    public renderOverlays(features: HazardOverlayFeature[]): void { ... }
    public filterByTier(features: HazardOverlayFeature[]): HazardOverlayFeature[] { ... }
}

export interface HazardOverlayFeature {
    id: string;
    geometry: Geometry;
    severity: Severity;
    source: string;
    observedAt: string;
    ttl: number;
}
```

### Unity / C#

```csharp
// NavigationXRBridge.cs (placeholder)
public interface IXRNavigationService : IDisposable
{
    Task SetDestinationAsync(Coordinate destination);
    Task UpdateOverlaysAsync(IList<HazardOverlayFeature> features);
    Task SetRouteAsync(RoutePolyline polyline);
}

public static class XRHub
{
    public static IXRNavigationService? NavigationService { get; set; }
}
```

---

## 4. Test matrix

| Phase | Test name | What it proves |
|-------|-----------|----------------|
| A | `testOperatorTierShowsAllOverlays` | Operator tier renders traffic, FIRMS, weather, quake overlays |
| A | `testCompanionTierShowsAccessibilityTags` | Companion tier adds curb cut, elevator, parking markers |
| A | `testGuestTierHidesOverlays` | Guest tier shows only route track and position |
| A | `testResponderTierShowsEMSRouteAndHazardTTL` | Responder tier shows preferred route path and hazard TTL badges |
| A | `testTileProviderConsumePublicToken` | No secret token exposed; uses public token only |
| B | `testCarPlayHUDShowsOnlyBasicData` | HUD shows ETA, distance, heading, turn icons only |
| B | `testGuestTierCarPlayHUDShowsETAOnly` | Guest tier HUD shows only ETA/distance, no turn icons if near destination |
| C | `testPWAMapboxGLUsesPublicToken` | JavaScript initialization uses public token, never secret |
| C | `testPWAOverlayRenderingMatchesNativeFormat` | `HazardOverlayFeature` parsed identically in JS and native |
| C | `testPWAResponsiveGrid` | Mobile (stacked) vs desktop (sidebar+map) layout active |
| E | `testSceneBriefingSnapshotOperatorTier` | Scene brief has full citations for operator tier |
| E | `testSceneBriefingSnapshotCompanionTier` | Scene brief shows curated summary, no raw citations |
| E | `testSourceAttestationViewShowsTimestamp` | Each source includes lastUpdated timestamp |

---

## 5. Open questions

### Canon violation flags

1. **`SceneBriefing` type missing fromCanon**  
   The spec reuses `SceneBriefing` (from NAV-001 GLM). It does **not** exist in `JarvisShared` (checked via `git grep SceneBriefing` and `JarvisShared/` file list).  
   *Action:* Confirm creation in GLM `RoutePrimitives.swift` or create here if GLM defers.  
   *Risk:* If GLM creates `SceneBriefing`, Qwen must import it or duplicate — no conflict, but coordination needed.

2. **`HazardOverlayFeature` missing fromCanon**  
   Same pattern — GLM spec defines this type, but it does not exist yet in `JarvisShared`.  
   *Action:* Confirm GLM creates it first; Qwen will import and consume.  
   *Risk:* If GLM defers, Qwen cannot consume engine data. Must flag as blocking dependency.

3. **CarPlay `CPMapTemplate` support**  
   - Does the existing Xcode workspace include `CarPlay.framework` target?  
   - `Jarvis.xcworkspace` → does it have a CarPlay extension target?  
   *Suggestion:* Scan `project.pbxproj` for `CPApplicationTemplate`. If missing, CarPlay surface must be deferred to a separate PR.

4. **Mapbox GL JS in PWA — is it already in `pwa/index.html`?**  
   *Action:* Check `pwa/index.html` for existing Mapbox GL import. If not, note that this spec introduces a new dependency (Mapbox GL JS via CDN or npm).  
   *Gray-area:* Mapbox GL JS is MIT, but requires public token. Confirm no tos issues.

### Gray-area concerns

1. **Mapbox public token rotation**  
   `MapboxCredentials.publicToken` currently stored in Swift. In PWA, we must hardcode it (via environment variable at build time, not runtime).  
   - Does build pipeline inject PUBLIC_MAPBOX_TOKEN or expect developer to set in code?  
   *Recommendation:* Add `MapboxCredentials.shared.publicToken` read at runtime in PWA, or expose via environment injection.

2. **TTL badges on hazards**  
   HUD displays TTL for hazards? If TTL expires, overlay should fade or disappear.  
   - Does `HazardOverlayFeature.ttl` field imply a countdown UI?  
   *Proposal:* TTL is for engine cache invalidation, not UI. HUD shows static overlays; TTL handled by background engine cache. If UI needs live TTL, signal to clarify.

3. **AR/Unity bridge scope**  
   Phase D is flagged "optional, low priority".  
   - Should we include minimal AR anchor + marker in core, or fully defer?  
   *Proposal:* Keep scaffold (empty interface), defer implementation to NAV-002 spec.

---

## 6. Risk log

| Risk | Severity | Mitigation |
|------|----------|------------|
| **UI-pattern risk:** Overlays visible on unsupported iOS versions (pre iOS 17 MapKit features) | Medium | Runtime availability check before rendering complex overlays; fallback to basic MKOverlayView on older OS |
| **Performance/scale risk:** Map layer re-render on tier change could cause flutters if large overlay arrays | Medium | Debounce tier-switched overlay refresh; use `@StateObject` lifecycle to avoid redundant renders |
| **Canon-gate floor risk:** Adding 8–10 new tests may push count above floor, but floor may need bump | Low | After-green tests, bump canon-gate comment and `EXECUTED` check from `250` to `260` (or actual count) |
| **Gray-zone data risk:** CarPlay uses same public token as PWA. If user token rotates, all surfaces must refresh token | Medium | Centralize `MapboxCredentials.publicToken` access in `JarvisShared`; each surface reads once at init, re-reads on foreground (not on every frame) |
| **Tier-gate leakage risk:** GLM engine injects `HazardOverlayFeature[]`, but surface could forge principal | Medium | Engine validates tier via `principalScope.contains(principal.category)` before composition. Unit test enforces. |

---

## 7. Sequencing

### PR1 — Core model types + engine contract (depend on NAV-001 engine)
- Ensure `HazardOverlayFeature`, `SceneBriefing` exist (confirm with GLM)
- Create `NavigationCockpitModel` with tier-aware filtering
- **LOC target:** ≤ 200

### PR2 — iOS Map Surface
- `NavigationCockpitView`, `MapLayerView`, wiring in `JarvisCockpitView`
- Unit tests (tier gating, layer visibility)
- **LOC target:** ≤ 400

### PR3 — Scene Briefing Surface
- `SceneBriefingView`, `SourceAttestationView`
- Snapshot tests per tier
- **LOC target:** ≤ 250

### PR4 — CarPlay HUD surface
- `CarPlayNavigationExtensionViewController`, `CPNavigationTemplate` builder
- Minimal HUD template
- **LOC target:** ≤ 300

### PR5 — PWA Enhancements
- `navigation.js`, Mapbox GL init, overlay renderer
- Responsive grid (mobile vs desktop)
- **LOC target:** ≤ 350

### PR6 — Unity scaffold (Phase D)
- Empty `IXRNavigationService` interface
- `XRHub` placeholder
- **LOC target:** ≤ 50

### PR7 — Canon-floor bump + cleanup
- Add remaining tests, bump canon-gate floor, lint fixups
- **LOC target:** ≤ 50

**Total estimated:** ~1,300 LOC, well within "surface only" boundaries (no engine logic, no data fetching).

---

**Final attestation:**  \nAll surface artifacts respect gray-not-black policy (open sources only), honor Principal tier gates, and avoid clinical-execution surfaces.  \nWhere canon conflicts exist (e.g., `SceneBriefing`/`HazardOverlayFeature` missing), they have been flagged in Open Questions rather than silently implemented.  \nNo GLM engine overlap; Qwen owns UI, GLM owns engine.
