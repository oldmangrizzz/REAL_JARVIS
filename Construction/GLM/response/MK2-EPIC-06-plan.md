# MK2‑EPIC‑06 Plan  
**Design Document – NavigationStore, Platform‑Guard Compliance, CarPlay Integration & Test Suite**

---

## 1. Overview  

The MK2‑EPIC‑06 effort closes the navigation‑CarPlay feedback loop for the **MapKit**‑based navigation stack.  The work introduces:

1. **Platform‑Guard compliance** – a systematic sweep that guarantees every public API is wrapped with the appropriate `#if os(iOS) / #if targetEnvironment(carPlay)` guards.  
2. **Shared `NavigationStore`** – a thread‑safe, singleton‑style store that holds the current route, navigation state, and UI‑driven preferences.  It is consumed by both the iOS navigation UI and the CarPlay extension.  
3. **CarPlay entitlement & UI** – addition of the `com.apple.developer.carplay-multimedia` entitlement, CarPlay scene configuration, and a minimal “happy‑path” navigation UI that can be launched from the CarPlay dashboard.  
4. **Smoke‑test harness** – a script‑driven UI test that drives a full navigation session from route request to arrival on both iOS and CarPlay simulators.  
5. **Comprehensive XCTest suite** – unit, integration, and UI tests that validate the `NavigationStore`, platform‑guard behavior, CarPlay entitlement loading, and the happy‑path navigation flow.

The result is a **single source of truth** for navigation state, guaranteed compile‑time platform safety, and automated verification that the CarPlay experience works end‑to‑end.

---

## 2. Goals & Success Criteria  

| Goal | Success Metric |
|------|----------------|
| **Platform‑Guard Sweep** | 0 compile warnings on both iOS and CarPlay targets; `swiftlint` rule `platform_guard` passes 100 % |
| **Shared NavigationStore** | All navigation‑related view models reference `NavigationStore.shared`; no duplicate state observed in runtime logs |
| **CarPlay Entitlement** | CarPlay scene launches on the simulator without entitlement errors; `Info.plist` contains `UIBackgroundModes` and `com.apple.developer.carplay-multimedia` |
| **Happy‑Path Smoke Test** | CI pipeline runs the script, completes a full navigation session in < 2 min, and exits with status 0 |
| **XCTest Suite** | ≥ 90 % code coverage for navigation stack; all tests pass on macOS, iOS, and CarPlay simulators |

---

## 3. Architecture  

### 3.1 High‑Level Diagram  

```
+-------------------+          +-------------------+          +-------------------+
|   iOS App UI      | <------> |  NavigationStore  | <------> |   CarPlay UI      |
| (SwiftUI/UIView)  |          | (Singleton)      |          | (CarPlay Scene)   |
+-------------------+          +-------------------+          +-------------------+
          ^                               ^                               ^
          |                               |                               |
   RouteRequest                     State Updates                UI Rendering
```

### 3.2 NavigationStore  

```swift
final class NavigationStore {
    // MARK: - Public API
    static let shared = NavigationStore()
    
    // MARK: - State
    @Published private(set) var currentRoute: Route?
    @Published private(set) var navigationState: NavigationState = .idle
    @Published private(set) var userPreferences: NavigationPreferences = .default
    
    // MARK: - Thread‑Safety
    private let queue = DispatchQueue(label: "com.myapp.navigationStore", attributes: .concurrent)
    
    // MARK: - Mutating Methods (internal)
    func setRoute(_ route: Route) {
        queue.async(flags: .barrier) { self.currentRoute = route }
    }
    
    func updateState(_ state: NavigationState) {
        queue.async(flags: .barrier) { self.navigationState = state }
    }
    
    func updatePreferences(_ prefs: NavigationPreferences) {
        queue.async(flags: .barrier) { self.userPreferences = prefs }
    }
    
    // MARK: - Query Helpers
    func isNavigating() -> Bool {
        var result = false
        queue.sync { result = navigationState == .active }
        return result
    }
    
    private init() { /* Prevent external instantiation */ }
}
```

*All UI components (iOS and CarPlay) subscribe to the `@Published` properties via Combine or SwiftUI `@ObservedObject`.*  

### 3.3 Platform‑Guard Strategy  

| Platform | Guard Macro | Usage Example |
|----------|--------------|---------------|
| iOS      | `#if os(iOS)` | `import UIKit` |
| CarPlay  | `#if targetEnvironment(carPlay)` | `import CarPlay` |
| Shared   | `#if canImport(CarPlay)` | Conditional extensions |

A **SwiftLint rule** (`platform_guard`) is added to the repo to enforce that any import or API that is not universally available is wrapped in the appropriate guard. The rule is configured in `.swiftlint.yml`:

```yaml
custom_rules:
  platform_guard:
    name: "Platform Guard"
    regex: '(import\s+(UIKit|AppKit|WatchKit|TVMLKit|CarPlay))|(targetEnvironment\(carPlay\))'
    message: "All platform‑specific imports must be wrapped in #if ... #endif"
    severity: error
```

A **script** (`Scripts/platform_guard_sweep.sh`) runs `swiftlint` and fails the build if any violation is found.

---

## 4. CarPlay Entitlement & Scene  

### 4.1 Entitlement  

*File:* `MyApp/Entitlements/MyApp.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.carplay-multimedia</key>
    <true/>
</dict>
</plist>
```

### 4.2 Info.plist Additions  

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.apple.carplay</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Needed for navigation.</string>
```

### 4.3 CarPlay Scene Configuration  

*File:* `MyApp/CarPlayScene.storyboard` (minimal UI)  

*File:* `MyApp/Info.plist` – add:

```xml
<key>UISceneConfigurations</key>
<dict>
    <key>CPTemplateApplicationSceneSessionRoleApplication</key>
    <array>
        <dict>
            <key>UISceneConfigurationName</key>
            <string>CarPlay</string>
            <key>UISceneDelegateClassName</key>
            <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            <key>UISceneStoryboardFile</key>
            <string>CarPlayScene</string>
        </dict>
    </array>
</dict>
```

### 4.4 CarPlaySceneDelegate (Guarded)

```swift
#if targetEnvironment(carPlay)
import CarPlay
import Combine

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var cancellables = Set<AnyCancellable>()
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        // Subscribe to NavigationStore
        NavigationStore.shared.$currentRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.updateMapTemplate(with: route, interfaceController: interfaceController)
            }
            .store(in: &cancellables)
    }
    
    private func updateMapTemplate(with route: Route?, interfaceController: CPInterfaceController) {
        guard let route = route else {
            interfaceController.setRootTemplate(CPMapTemplate(), animated: true)
            return
        }
        let mapTemplate = CPMapTemplate()
        mapTemplate.mapDelegate = self
        mapTemplate.showTripPreview(for: route.trip, using: .default)
        interfaceController.setRootTemplate(mapTemplate, animated: true)
    }
}
extension CarPlaySceneDelegate: CPMapTemplateDelegate { /* optional delegate methods */ }
#endif
```

---

## 5. Smoke‑Test Harness  

### 5.1 Script – `Scripts/run_navigation_smoke_test.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1️⃣ Build both targets
xcodebuild -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' clean build
xcodebuild -scheme MyApp -destination 'platform=carOS Simulator,name=Apple CarPlay,OS=latest' clean build

# 2️⃣ Launch iOS simulator & CarPlay simulator (headless)
SIMULATOR_UDID=$(xcrun simctl list devices | grep "iPhone 15 (" | awk -F'[()]' '{print $2}')
CARPLAY_UDID=$(xcrun simctl list devices | grep "Apple CarPlay (" | awk -F'[()]' '{print $2}')

xcrun simctl boot "$SIMULATOR_UDID"
xcrun simctl boot "$CARPLAY_UDID"

# 3️⃣ Install the app on both simulators
xcrun simctl install "$SIMULATOR_UDID" ./build/Debug-iphonesimulator/MyApp.app
xcrun simctl install "$CARPLAY_UDID" ./build/Debug-carOS-simulator/MyApp.app

# 4️⃣ Launch the app (iOS) – it will automatically request a route
xcrun simctl launch "$SIMULATOR_UDID" com.mycompany.MyApp

# 5️⃣ Wait for route to be generated (poll NavigationStore via a small helper binary)
TIMEOUT=120
ELAPSED=0
while true; do
    if ./Scripts/check_route_ready "$SIMULATOR_UDID"; then
        echo "✅ Route ready – navigation started."
        break
    fi
    sleep 2
    ((ELAPSED+=2))
    if (( ELAPSED > TIMEOUT )); then
        echo "⏰ Timeout waiting for route."
        exit 1
    fi
done

# 6️⃣ Simulate arrival (fast‑forward location)
./Scripts/simulate_arrival "$SIMULATOR_UDID"

# 7️⃣ Verify CarPlay UI shows completed navigation
if ./Scripts/verify_carplay_completion "$CARPLAY_UDID"; then
    echo "🎉 CarPlay navigation happy‑path succeeded."
    exit 0
else
    echo "❌ CarPlay verification failed."
    exit 1
fi
```

*Helper binaries (`check_route_ready`, `simulate_arrival`, `verify_carplay_completion`) are tiny Swift command‑line tools that attach to the simulator via `XCUIApplication` and query the `NavigationStore` through a shared `UserDefaults` flag.*

### 5.2 CI Integration  

Add a new **GitHub Actions** job:

```yaml
jobs:
  navigation-smoke-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Set up Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: "15.4"
      - name: Run Smoke Test
        run: |
          chmod +x Scripts/*.sh
          Scripts/run_navigation_smoke_test.sh
```

The job fails fast on any non‑zero exit, guaranteeing that a broken CarPlay flow blocks merges.

---

## 6. XCTest Suite  

### 6.1 Unit Tests – `NavigationStoreTests.swift`

```swift
import XCTest
@testable import MyApp

final class NavigationStoreTests: XCTestCase {
    var store: NavigationStore!

    override func setUp() {
        super.setUp()
        store = NavigationStore.shared
        // Reset state
        store.updateState(.idle)
        store.setRoute(nil)
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(store.navigationState, .idle)
        XCTAssertNil(store.currentRoute)
    }

    func testRouteAssignmentIsThreadSafe() {
        let expectation = expectation(description: "Concurrent writes")
        let route = Route.mock()
        DispatchQueue.global(qos: .userInitiated).async {
            self.store.setRoute(route)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(store.currentRoute?.id, route.id)
    }

    func testStateTransitions() {
        store.updateState(.active)
        XCTAssertTrue(store.isNavigating())
        store.updateState(.paused)
        XCTAssertFalse(store.isNavigating())
    }

    func testPreferencesUpdate() {
        let newPrefs = NavigationPreferences(voiceGuidance: .muted, mapStyle: .night)
        store.updatePreferences(newPrefs)
        XCTAssertEqual(store.userPreferences.voiceGuidance, .muted)
    }
}
```

### 6.2 Platform‑Guard Tests – `PlatformGuardTests.swift`

```swift
import XCTest

final class PlatformGuardTests: XCTestCase {
    func testCarPlayOnlyCodeIsExcludedFromiOSTarget() {
        #if os(iOS)
        // The symbol `CPMapTemplate` should not be available on iOS builds.
        XCTAssertFalse(_typeByName("CPMapTemplate") != nil)
        #endif
    }

    func testiOSOnlyCodeIsExcludedFromCarPlayTarget() {
        #if targetEnvironment(carPlay)
        // UIKit classes should not be linked in CarPlay target.
        XCTAssertFalse(_typeByName("UIViewController") != nil)
        #endif
    }
}
```

### 6.3 Integration Tests – `NavigationIntegrationTests.swift`

```swift
import XCTest
import Combine
@testable import MyApp

final class NavigationIntegrationTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    var store: NavigationStore!

    override func setUp() {
        super.setUp()
        store = NavigationStore.shared
        store.updateState(.idle)
        store.setRoute(nil)
    }

    func testFullNavigationFlow() {
        // 1️⃣ Request a route (simulated service)
        let expectationRoute = expectation(description: "Route received")
        MockRoutingService.shared.requestRoute(from: .mockStart, to: .mockEnd)
            .sink { completion in
                if case .failure(let err) = completion { XCTFail(err.localizedDescription) }
            } receiveValue: { route in
                self.store.setRoute(route)
                expectationRoute.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectationRoute], timeout: 5.0)

        // 2️⃣ Start navigation
        store.updateState(.active)
        XCTAssertTrue(store.isNavigating())

        // 3️⃣ Simulate arrival
        store.updateState(.arrived)
        XCTAssertEqual(store.navigationState, .arrived)
    }
}
```

### 6.4 UI Tests – `CarPlayNavigationUITests.swift`

```swift
import XCTest

@available(iOS 15.0, *)
final class CarPlayNavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testCarPlayMapTemplateAppearsAfterRoute() {
        // Trigger route request via UI (button with identifier "StartNavigation")
        let startButton = app.buttons["StartNavigation"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // Wait for CarPlay scene to appear (simulated via mock CarPlay UI)
        let mapTemplate = app.otherElements["CarPlayMapTemplate"]
        XCTAssertTrue(mapTemplate.waitForExistence(timeout: 10))

        // Verify that a turn instruction label updates
        let instruction = app.staticTexts["NextTurnInstruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        XCTAssertFalse(instruction.label.isEmpty)
    }
}
```

### 6.5 Code Coverage  

The Xcode scheme `MyApp` is configured with:

- **Gather coverage data** enabled.
- **Exclude** generated files (`*.generated.swift`) and test files from coverage.
- **Run** `xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -enableCodeCoverage YES`.

Coverage reports are uploaded to **Codecov** via a GitHub Action step.

---

## 7. Integration Steps  

1. **Merge Platform‑Guard Sweep**  
   - Run `Scripts/platform_guard_sweep.sh` locally.  
   - Fix any violations; commit the changes.  

2. **Add NavigationStore**  
   - Add `NavigationStore.swift` to `MyApp/Navigation/`.  
   - Replace all existing route/state singletons with `NavigationStore.shared`.  

3. **Configure CarPlay Entitlement & Scene**  
   - Add `MyApp.entitlements` to the CarPlay target.  
   - Update `Info.plist` with CarPlay scene configuration.  
   - Add `CarPlayScene.storyboard` and `CarPlaySceneDelegate.swift`.  

4. **Implement Smoke Test**  
   - Add the three helper binaries under `Scripts/`.  
   - Add `run_navigation_smoke_test.sh` and make it executable.  

5. **Add XCTest Suite**  
   - Create `NavigationStoreTests.swift`, `PlatformGuardTests.swift`, `NavigationIntegrationTests.swift`, `CarPlayNavigationUITests.swift`.  
   - Add test target `MyAppTests` (unit) and `MyAppUITests` (UI).  

6. **CI Pipeline**  
   - Extend `.github/workflows/ci.yml` with the `navigation-smoke-test` job.  
   - Add a `codecov.yml` entry for coverage upload.  

7. **Documentation**  
   - Update the project README with a “Running CarPlay navigation tests” section.  
   - Add a `CONTRIBUTING.md` note about the platform‑guard rule.  

8. **Verification**  
   - Run `xcodebuild test` locally for all targets.  
   - Verify code coverage ≥ 90 % for navigation modules.  
   - Ensure the smoke test passes on a clean macOS runner.  

---

## 8. Timeline  

| Week | Milestone |
|------|-----------|
| 1 | Platform‑guard sweep implementation, SwiftLint rule, and initial script. |
| 2 | `NavigationStore` implementation and migration of existing navigation code. |
| 3 | CarPlay entitlement, scene, and delegate implementation (guarded). |
| 4 | Smoke‑test script and helper binaries; local verification. |
| 5 | Full XCTest suite creation and coverage configuration. |
| 6 | CI integration, code‑coverage upload, and final documentation. |
| 7 | Bug‑fixes, performance tuning, and release candidate validation. |

---

## 9. Risks & Mitigations  

| Risk | Impact | Mitigation |
|------|--------|------------|
| Platform‑guard rule too strict → false positives | Build failures for legitimate code | Provide an `allowlist` in `.swiftlint.yml` for known edge cases; run rule in CI only after a dry‑run. |
| CarPlay entitlement rejected by App Store | Release delay | Verify entitlement via Xcode’s “Signing & Capabilities” before submission; keep a separate “CarPlay‑only” build configuration for internal testing. |
| Simulator CarPlay API instability | Flaky smoke test | Pin Xcode version in CI; add retry logic in the script. |
| Shared `NavigationStore` becomes a bottleneck | UI lag | Use concurrent queue with barrier writes; profile on device; consider moving heavy calculations off‑main thread. |

---

## 10. Conclusion  

The MK2‑EPIC‑06 plan delivers a **robust, platform‑safe navigation architecture** that unifies iOS and CarPlay state, guarantees compile‑time compliance, and provides **full automated verification** from unit tests to end‑to‑end smoke tests.  By completing the steps outlined above, the navigation stack will be production‑ready for CarPlay deployment, and future feature work can rely on a single source of truth for navigation state.