# MK2-EPIC-10 — visionOS Thin Client — SKIPPED (external-owed)

**Lane:** Qwen (UX)
**Spec:** `Construction/Qwen/spec/MK2-EPIC-10-visionos-thin-client.md`
**Status:** SKIPPED — visionOS platform components not installed
**HEAD at time of skip:** `19b70d2`

---

## §1 SDK Gate Result

```
$ xcodebuild -showsdks 2>&1 | grep -i xros
visionOS 26.4                 	-sdk xros26.4
	Simulator - visionOS 26.4     	-sdk xrsimulator26.4
```

**SDK-present:** YES — `xros26.4` and `xrsimulator26.4` both appear in `-showsdks`.

**Platform-installed:** NO — The SDK lines indicate the toolchain header references are present, but the full platform components (device support files, simulator runtime) are not installed. Any `xcodebuild build -destination 'generic/platform=visionOS'` invocation will fail with:

> `error: visionOS 26.4 is not installed. Please download and install the platform from Xcode > Settings > Components.`

This failure mode was confirmed in EPIC-01 evidence (see §3 below).

---

## §2 Path taken

Per spec `MK2-EPIC-10` §"Acceptance Criteria":

> If visionOS SDK absent: epic emits `Construction/Qwen/response/MK2-EPIC-10-skipped.md` with clear rationale; shipping Mark II is NOT blocked (P2 allows skip).

**Path taken: SKIP.** No code changes made. No `Jarvis/Vision/` tree created. No build attempted. Smoke script continues to mark `RealJarvisVision` as `⚠️ SKIP` and exits 0.

---

## §3 Evidence from prior runs

### EPIC-01 response doc (`Construction/GLM/response/MK2-EPIC-01.md`) — §3 Honest Flags, flag 2:

> **visionOS platform not fully installed:** `xcodebuild -showsdks` lists `xros26.4` and `xrsimulator26.4`, but building for any visionOS destination fails with "visionOS 26.4 is not installed. Please download and install the platform from Xcode > Settings > Components." The `RealJarvisVision` scheme IS committed and present in `-list`; smoke marks it `⚠️ SKIP` (not FAIL) and exits 0.

### EPIC-01 response doc — §2 Spec Acceptance-Criteria Map, row "RealJarvisVision":

> ✅ Scheme present, ⚠️ platform not installed | SDK present (`xros26.4`) but `visionOS 26.4` platform not installed in Xcode; scheme added, smoke skips gracefully

### `scripts/smoke/build-all.sh` — vision entry:

```bash
run_build "RealJarvisVision" "generic/platform=visionOS Simulator" "RealJarvisVision" "optional"
```

The `"optional"` flag causes the smoke script to record `⚠️ SKIP` rather than `❌ FAIL` on build failure and continue. This is the current runtime behaviour at HEAD `19b70d2`.

---

## §4 No code changes

The following actions were deliberately **not** taken:

- `Jarvis/Vision/` tree was **not** created.
- `RealJarvisVisionApp.swift` and `JarvisVisionImmersiveView.swift` were **not** created.
- `Tests/VisionBuildGuardTests.swift` was **not** created.
- No `project.yml` edits, no `xcodegen generate` run.
- No build was attempted against `generic/platform=visionOS` or `generic/platform=visionOS Simulator` (would fail in this environment).

Attempting to land stub files that reference `RealityKit`/`ARKit`/visionOS APIs when the platform is not installed would introduce phantom compile paths — exactly the failure mode VOICE-002-FIX-02 documents as unacceptable.

---

## §5 External-owed

**Required action (operator):**

> Install the **visionOS 26.4** platform from **Xcode → Settings → Platforms** (or **Settings → Components** depending on Xcode version). Once the platform runtime is installed, re-run `scripts/smoke/build-all.sh` to confirm `RealJarvisVision` upgrades from `⚠️ SKIP` to `✅ PASS`. Then re-open this EPIC-10 work item and implement `RealJarvisVisionApp` + `ImmersiveView` per spec §Scope.

This is an **operator-owed infrastructure action**; it cannot be completed by a code-change sub-agent operating in this environment.

---

## §6 Honest flags

1. **SDK vs platform distinction:** `-showsdks` returns `xros26.4` which means Xcode has the SDK headers. This is not the same as having the platform simulator runtime. The build failure happens at simulator/device target resolution, after the SDK is found.
2. **Suite count unchanged:** No test files added or removed. Suite remains at `659 / 1 skipped / 0 failures` (baseline from EPIC-01 acceptance-evidence).
3. **`RealJarvisVision` scheme present:** The scheme exists in `jarvis.xcworkspace/xcshareddata/xcschemes/` from EPIC-01. This skip doc does not remove or modify it.
4. **Mark II not blocked:** EPIC-10 is P2. Per spec, Mark II ships without it.

---

## §7 Re-open conditions

This epic transitions from SKIP → IN PROGRESS when **all** of the following are true:

- [ ] Operator confirms `xcodebuild -destination 'generic/platform=visionOS Simulator' -sdk xrsimulator26.4 -scheme RealJarvisVision build` exits 0 (or non-error) on their machine after platform install.
- [ ] EPIC-01 `build-all.sh` row for `RealJarvisVision` shows `✅ PASS` not `⚠️ SKIP`.

Until then, this doc stands as the closed-out record for EPIC-10.

---

**Closing note:**

> This is not a failure — it is a correct gate. Emitting an honest `skipped.md` when the platform is absent is the right action under MEMO_CLINICAL_STANDARD.md: "verified correct" is only achievable if the target environment is present. We do not claim a passing build we cannot reproduce.
