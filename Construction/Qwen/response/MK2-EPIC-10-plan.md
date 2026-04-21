# MK2‑EPIC‑10 Plan  
**Add a visionOS thin‑client target guarded by `#if canImport(RealityKit) && os(visionOS)`**  

---

## 1. Goal  

Create a **visionOS‑only** thin‑client target that can be compiled **whether or not** the VisionOS SDK (RealityKit) is installed on the developer’s machine. The target must:

1. **Only compile** when the SDK is present (guarded by `#if canImport(RealityKit) && os(visionOS)`).
2. Provide an **entry‑point** (`@main` app) that launches an **immersive view** using RealityKit.
3. Include a **compile‑only test** that validates the guard and the basic view hierarchy.
4. Generate a **response markdown** (`Construction/Qwen/response/MK2‑EPIC‑10‑response.md`) summarising the guard strategy, build steps, and verification results.

All other platforms (iOS, macOS, tvOS, etc.) must **ignore** this target and continue to build successfully.

---

## 2. Guard Strategy  

| Guard | Meaning | Why it works |
|------|---------|--------------|
| `canImport(RealityKit)` | True only when the RealityKit framework is available on the host SDK. | If the VisionOS SDK is not installed, the compiler cannot locate RealityKit → guard evaluates to `false`. |
| `os(visionOS)` | True only when the target’s deployment OS is `visionOS`. | Prevents accidental compilation on other Apple platforms that might also have RealityKit (e.g., iOS 17+). |
| Combined guard: `#if canImport(RealityKit) && os(visionOS)` | Both conditions must be satisfied. | Guarantees **visionOS‑only** code is compiled **only** when the SDK exists. |

All source files that reference VisionOS‑specific APIs (e.g., `RealityKit`, `ImmersiveSpace`, `ARView`) must be wrapped in this guard. Files that are completely VisionOS‑specific can be placed in a dedicated folder and marked with the guard at the top of the file.

---

## 3. Conditional Target Addition  

### 3.1. Swift Package Manager (preferred)  

If the project uses **SwiftPM**, add a new target in `Package.swift`:

```swift
// Package.swift (excerpt)
let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        // VisionOS is optional – do NOT list it here.
    ],
    products: [
        .executable(name: "VisionThinClient", targets: ["VisionThinClient"]),
    ],
    targets: [
        // Existing targets …

        // ---- VisionOS thin‑client target ----
        .target(
            name: "VisionThinClient",
            dependencies: [],
            path: "Sources/VisionThinClient",
            swiftSettings: [
                // Enable the guard for the whole target.
                .define("VISION_THIN_CLIENT", .when(configuration: .debug)),
                .unsafeFlags([
                    "-Xfrontend", "-enable-actor-data-race-checks"
                ], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "VisionThinClientTests",
            dependencies: ["VisionThinClient"]
        )
    ]
)
```

*Important*: **Do not** list `.visionOS` in the `platforms` array. The guard inside the source files will prevent compilation when the SDK is missing, and Xcode/SwiftPM will simply skip the target.

### 3.2. Xcode Project (if not using SwiftPM)

1. **Add a new target** → *App* → name it `VisionThinClient`.  
2. In **General → Deployment Info**, set **Deployment Target** to the lowest VisionOS version you support (e.g., 1.0).  
3. In **Build Settings → Swift Compiler – Custom Flags**, add:  

   ```
   OTHER_SWIFT_FLAGS = $(inherited) -D VISION_THIN_CLIENT
   ```

4. In **File Inspector**, set the **Target Membership** of all VisionOS‑specific files to **VisionThinClient** only.  
5. Add the **guard** (see Section 4) at the top of each VisionOS file.

---

## 4. Entry‑Point Application  

Create `Sources/VisionThinClient/main.swift` (or `App.swift` for SwiftUI) wrapped in the guard:

```swift
#if canImport(RealityKit) && os(visionOS)
import SwiftUI
import RealityKit

@main
struct VisionThinClientApp: App {
    var body: some Scene {
        WindowGroup {
            ImmersiveView()
        }
    }
}
#else
// This file is compiled on non‑visionOS platforms but does nothing.
#endif
```

### 4.1. Immersive View (`ImmersiveView.swift`)

```swift
#if canImport(RealityKit) && os(visionOS)
import SwiftUI
import RealityKit

struct ImmersiveView: View {
    var body: some View {
        // The immersive space is provided by RealityKit.
        ImmersiveSpace {
            // Simple placeholder content – a rotating cube.
            ModelEntity(mesh: .generateBox(size: 0.2))
                .generateCollisionShapes(recursive: true)
                .scaleEffect(1.5)
                .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: UUID())
        }
        .ignoresSafeArea()
    }
}
#else
// Stub for non‑visionOS builds – provides a compile‑time placeholder.
struct ImmersiveView: View { var body: some View { EmptyView() } }
#endif
```

*Notes*:

* `ImmersiveSpace` is a RealityKit‑provided SwiftUI container that automatically creates an immersive session on visionOS.
* The view is deliberately **minimal** to keep compile‑time low and avoid runtime dependencies on unavailable hardware.

---

## 5. Compile‑Only Test  

Create `Tests/VisionThinClientTests/VisionThinClientTests.swift`:

```swift
#if canImport(RealityKit) && os(visionOS)
import XCTest
import SwiftUI
@testable import VisionThinClient

final class VisionThinClientCompileTests: XCTestCase {
    func testImmersiveViewCompiles() {
        // The test does not run on non‑visionOS platforms.
        // It merely forces the compiler to instantiate the view.
        _ = ImmersiveView()
    }
}
#else
// No tests compiled for other platforms.
#endif
```

*Purpose*: Guarantees that the guard is correctly applied and that the view can be type‑checked when the SDK is present. The test **does not execute** any runtime code; it only ensures successful compilation.

---

## 6. Response Documentation Generation  

After a successful build (or after a failed guard compilation), generate a markdown response summarising the outcome.

### 6.1. Script (`Scripts/generate‑vision‑response.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

OUTPUT="Construction/Qwen/response/MK2-EPIC-10-response.md"

cat > "$OUTPUT" <<'EOF'
# MK2‑EPIC‑10 Response

## Guard Evaluation
EOF

if swiftc -typecheck - <<'SWIFT' 2>/dev/null; then
cat >> "$OUTPUT" <<'EOF'
✅ `canImport(RealityKit) && os(visionOS)` evaluated to **true** – VisionOS SDK is available.
EOF
else
cat >> "$OUTPUT" <<'EOF'
⚠️ Guard evaluated to **false** – VisionOS SDK not present. The target was skipped.
EOF
fi

cat >> "$OUTPUT" <<'EOF'

## Build Summary
- **Target**: VisionThinClient
- **Platform**: visionOS (conditional)
- **Status**: $(if [ -d .build ]; then echo "✅ Build succeeded"; else echo "❌ Build failed"; fi)

## Test Results
$(xcrun xcodebuild test -scheme VisionThinClientTests -destination 'platform=visionOS Simulator,name=Apple Vision Pro' | grep -E "Test Succeeded|Test Failed" || echo "⚠️ Tests not executed (SDK missing)")

## Next Steps
- If the SDK is missing, install Xcode 15+ with the VisionOS SDK.
- Verify that the `ImmersiveView` renders correctly on a Vision Pro simulator or device.
- Extend the view with actual content once the thin‑client architecture is approved.

EOF
```

Running the script after a CI build will produce a **self‑contained** markdown file that can be posted back to the issue tracker or documentation site.

---

## 7. Acceptance Criteria  

| # | Criterion | Pass Condition |
|---|-----------|-----------------|
| 1 | The `VisionThinClient` target **builds** on a machine **without** the VisionOS SDK (i.e., the guard skips compilation). | `xcodebuild` succeeds, target is ignored. |
| 2 | The target **builds** on a machine **with** the VisionOS SDK. | `xcodebuild` succeeds, app launches in the VisionOS simulator. |
| 3 | The entry‑point app launches an `ImmersiveView` containing a simple placeholder (e.g., rotating cube). | Running the app on the simulator shows the placeholder. |
| 4 | The compile‑only test passes when the SDK is present and is **not compiled** otherwise. | Test file appears in the test report only on VisionOS builds. |
| 5 | The response markdown (`MK2‑EPIC‑10‑response.md`) is generated automatically after a CI run and accurately reflects guard evaluation, build status, and test results. | Script runs without error and file contains the expected sections. |

---

## 8. Risks & Mitigations  

| Risk | Impact | Mitigation |
|------|--------|------------|
| VisionOS SDK not installed on CI agents. | Build fails or target is silently skipped, causing false‑positive success. | Guard ensures safe skip; CI must report guard outcome via the response script. |
| Accidentally adding `visionOS` to the `platforms` array in `Package.swift`. | SwiftPM will try to compile the target even when SDK missing, leading to errors. | Keep `visionOS` out of the global `platforms` list; rely solely on the guard. |
| Future RealityKit API changes break the placeholder view. | Compile errors after SDK update. | Keep the placeholder minimal; encapsulate RealityKit usage inside the guard and update only when needed. |
| Xcode project may still attempt to link RealityKit on non‑visionOS builds. | Linker errors. | Ensure **Link Binary With Libraries** for RealityKit is set to **Optional** and limited to the VisionThinClient target. |

---

## 9. Implementation Checklist  

- [ ] Add `VisionThinClient` target (SwiftPM or Xcode).  
- [ ] Create `main.swift` / `App.swift` with guard.  
- [ ] Implement `ImmersiveView.swift` under the same guard.  
- [ ] Add compile‑only test under `VisionThinClientTests`.  
- [ ] Write `generate‑vision‑response.sh` script and add it to CI pipeline.  
- [ ] Verify builds on a machine **without** VisionOS SDK (guard skips).  
- [ ] Verify builds and runtime on a machine **with** VisionOS SDK (simulator).  
- [ ] Confirm response markdown is generated and contains correct sections.  

--- 

*Prepared by the Forge Executor – 2026‑04‑21*