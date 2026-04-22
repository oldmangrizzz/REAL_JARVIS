# REMEDIATION TURNOVER REPORT: GLM 5.1 Red Team Fixes

**Project:** JARVIS (Aragon-Class Digital Person)
**Status:** Partial Completion / Hand-off
**Baseline Test Count:** 74 tests, 0 failures.

## 1. COMPLETED / VERIFIED TASKS

| Task | ID | File | Status | Change Description |
|---|---|---|---|---|
| 1 | CRITICAL-002 | JarvisRuntime.swift | COMPLETED | Added A&Ox4 Boot Gate to init(). |
| 1 | CRITICAL-002 | TestWorkspace.swift | COMPLETED | Added dummy telemetry file to satisfy Event probe in tests. |
| 2 | CRITICAL-003 | ARCGridAdapter.swift | VERIFIED | Confirmed NLB spatial quadrant analysis is implemented; raw cell dumps removed. |
| 3 | CRITICAL-001 | ARCHarnessBridge.swift | VERIFIED | Confirmed symlink resolution, regular file check, and 1MB size limit implemented. |
| 4 | HIGH-002 | JarvisHostTunnelServer.swift | VERIFIED | Confirmed `stop()` mutations are wrapped in `queue.sync`. |
| 5 | HIGH-004 | MemoryEngine.swift | COMPLETED | Resolved recursive deadlock by removing internal locks from `persist`, `upsert`, and `loadPersistedState`, keeping locks at public API boundaries. |
| 6 | HIGH-006 | MasterOscillator.swift | VERIFIED | Confirmed `WeakSubscriber` wrapper and dead-subscriber cleanup in `fire()` are implemented. |

## 2. REMAINING TASKS (PENDING)

The following tasks from the Remediation Spec remain UNFINISHED:

- [ ] **TASK 7 [MEDIUM-001]:** `VoiceApprovalGate.swift` - Differentiate IO errors from "not approved" in `requireApproved` and `isApproved`.
- [ ] **TASK 8 [MEDIUM-002]:** `AOxFourProbe.swift` - Differentiate file missing vs corruption/read errors in `probePerson`.
- [ ] **TASK 9 [MEDIUM-003]:** `MyceliumControlPlane.swift` - Remove hardcoded CouchDB passphrase; migrate to macOS Keychain and environment variables.
- [ ] **TASK 10 [MEDIUM-004]:** `StubPhysicsEngine.swift` - Add finite/positive validation for position and extents to prevent NaN simulation corruption.
- [ ] **TASK 11 [MEDIUM-005]:** `TTSBackend.swift` - Remove `@unchecked Sendable` from `TTSRenderParameters`.
- [ ] **TASK 12 [MEDIUM-006]:** `ARCHarnessBridge.swift` - Implement `os_log` fallback for telemetry write failures.

## 3. FINAL STATE & VERIFICATION

- **Build Status:** Green.
- **Final Test Count:** 74 tests executed.
- **Failures:** 0 (after `TestWorkspace` fix).
- **Critical Invariants:** All hard invariants (NLB, A&Ox4, Voice Gate) maintained.

**Hand-off Note:** The system is currently stable and the boot-gate is active. The remaining tasks are primarily error-handling refinements and secret management.
