# MK2‑EPIC‑01 – VisionOS SDK Unavailable (RealJarvisVision Target Skipped)

## Purpose
This document records the expected behaviour of the **Jarvis** Xcode workspace when the **visionOS** SDK is not present on the build machine. In that situation the `RealJarvisVision` target is deliberately omitted from the build graph, allowing the rest of the project (iOS, macOS, tvOS, etc.) to compile and run without error.

## Background
The recent refactor introduced:

1. **Missing Xcode targets** – each surface now has its own target (`RealJarvisiOS`, `RealJarvisMac`, `RealJarvisVision`, …).  
2. **Conditional VisionOS target** – the `RealJarvisVision` target is only added to the workspace if the visionOS SDK can be located.  
3. **Composite “all” scheme** – a top‑level scheme named **all** builds every available surface in one command:  

   ```bash
   xcodebuild -workspace jarvis.xcworkspace -scheme all
   ```

4. **Smoke‑build script** – `scripts/smoke-build.sh` invokes the above command and fails fast on any error.

Because the visionOS SDK is still optional (it ships only with Xcode 15+ on Apple‑silicon Macs), the build must succeed even when that SDK cannot be found.

## How the Conditional Target Works
The `RealJarvisVision` target is defined in `jarvis.xcodeproj` with the following guard (pseudo‑Xcode‑project logic shown for clarity):

```xml
<Target
    name="RealJarvisVision"
    ...>
    <BuildSettings>
        <SDKROOT>$(VISIONOS_SDK_ROOT)</SDKROOT>
    </BuildSettings>
    <Condition>
        $(VISIONOS_SDK_ROOT) != ""
    </Condition>
</Target>
```

* `VISIONOS_SDK_ROOT` is resolved at **project generation time** by the `scripts/generate‑targets.rb` helper.  
* If the environment variable is empty (i.e., the SDK cannot be located), the target is **not added** to the workspace file.  
* Consequently, the **all** scheme simply does not contain a `RealJarvisVision` build action.

## Expected Behaviour When SDK Is Missing

| Step | Command | Expected Output |
|------|---------|-----------------|
| 1 | `scripts/smoke-build.sh` (or the raw `xcodebuild` call) | The build proceeds through all non‑visionOS targets. |
| 2 | `xcodebuild -workspace jarvis.xcworkspace -scheme all` | No “target ‘RealJarvisVision’ not found” error. |
| 3 | Build log | A line similar to: `Skipping RealJarvisVision – visionOS SDK not detected` (printed by the generation script). |
| 4 | Exit code | `0` if all other targets succeed; non‑zero only for failures unrelated to visionOS. |

## Verifying the Omission

You can confirm that the vision target is absent by inspecting the generated workspace:

```bash
# List all targets known to the workspace
xcodebuild -workspace jarvis.xcworkspace -list
```

The output will **not** contain `RealJarvisVision` when the SDK is missing.

Alternatively, open `jarvis.xcworkspace` in Xcode; the **RealJarvisVision** target will be hidden from the **Targets** list.

## Re‑enabling VisionOS Builds
When you later install an Xcode version that includes the visionOS SDK:

1. Ensure the SDK path is discoverable (e.g., `xcode-select -p` points to the new Xcode).  
2. Re‑run the target‑generation script (automatically invoked by the smoke‑build script or CI pipeline).  
3. The `RealJarvisVision` target will be added, and the **all** scheme will now include it.

You can also force regeneration manually:

```bash
ruby scripts/generate-targets.rb
```

After regeneration, a subsequent `xcodebuild -scheme all` will compile the vision target alongside the others.

## Impact on CI / Automation
CI runners that do not have the visionOS SDK installed will **still pass** the smoke‑build stage because the target is omitted automatically. No extra configuration is required.

If you wish to explicitly fail the build when the SDK is missing (e.g., for a vision‑only pipeline), you can add a guard in your CI script:

```bash
if ! xcodebuild -sdk visionos -showBuildSettings > /dev/null 2>&1; then
    echo "visionOS SDK not available – aborting vision‑specific pipeline"
    exit 1
fi
```

## Summary
- The `RealJarvisVision` target is **conditionally added** based on SDK availability.  
- When the SDK is absent, the **all** scheme and smoke‑build script automatically skip the vision target, resulting in a successful build of the remaining surfaces.  
- Documentation and scripts are now in place to make this behaviour transparent to developers and CI systems.