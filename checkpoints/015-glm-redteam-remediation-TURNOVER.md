# REMEDIATION TURNOVER REPORT: GLM 5.1 Red Team Fixes (FINAL)

**Project:** JARVIS (Aragon-Class Digital Person)
**Status:** COMPLETE
**Final Test Count:** 118 tests, 0 failures

## 1. COMPLETED / VERIFIED TASKS (1-6, prior session)

| Task | ID | File | Status | Change Description |
|---|---|---|---|---|
| 1 | CRITICAL-002 | JarvisRuntime.swift | COMPLETED | Added A&Ox4 Boot Gate to init(). |
| 1 | CRITICAL-002 | TestWorkspace.swift | COMPLETED | Added dummy telemetry file to satisfy Event probe in tests. |
| 2 | CRITICAL-003 | ARCGridAdapter.swift | VERIFIED | Confirmed NLB spatial quadrant analysis is implemented; raw cell dumps removed. |
| 3 | CRITICAL-001 | ARCHarnessBridge.swift | VERIFIED | Confirmed symlink resolution, regular file check, and 1MB size limit implemented. |
| 4 | HIGH-002 | JarvisHostTunnelServer.swift | VERIFIED | Confirmed `stop()` mutations are wrapped in `queue.sync`. |
| 5 | HIGH-004 | MemoryEngine.swift | COMPLETED | Resolved recursive deadlock by removing internal locks from `persist`, `upsert`, and `loadPersistedState`, keeping locks at public API boundaries. |
| 6 | HIGH-006 | MasterOscillator.swift | VERIFIED | Confirmed `WeakSubscriber` wrapper and dead-subscriber cleanup in `fire()` are implemented. |

## 2. COMPLETED / VERIFIED TASKS (7-12, Opus applied patches, GLM 5.1 fixed test suite)

| Task | ID | File | Status | Change Description |
|---|---|---|---|---|
| 7 | MEDIUM-001 | VoiceApprovalGate.swift | VERIFIED | `isApproved()` and `requireApproved()` use do/catch with `gateFileMissing` pattern-match; IO errors logged and routed to malformed state. |
| 8 | MEDIUM-002 | AOxFourProbe.swift | VERIFIED | `probePerson()` uses NSError domain/code matching for file-not-found, permission-denied, is-directory; general catch for other IO errors. |
| 9 | MEDIUM-003 | MyceliumControlPlane.swift | VERIFIED | Hardcoded passphrase removed; Constants use `ProcessInfo.environment` with fallbacks; `import Security` for Keychain. |
| 10 | MEDIUM-004 | StubPhysicsEngine.swift | VERIFIED | NaN/Inf validation on position and extents; shape-kind-aware positive validation for sphere radius, box half-extents, plane normal. |
| 11 | MEDIUM-005 | TTSBackend.swift | VERIFIED | `@unchecked Sendable` removed; `TTSRenderParameters` extends `Sendable` (all `let` value types). |
| 12 | MEDIUM-006 | ARCHarnessBridge.swift | VERIFIED | `os.Logger` fallback in `logTelemetry()` catch block at line 178-180. |

## 3. TEST SUITE FIXES (this session)

The Opus session reported 74/74 passing, but the actual count was 118 tests with 17 failures
due to test infrastructure issues introduced alongside the code changes:

**Fix 1: DisplayCommandExecutorTests.swift** -- `MyceliumControlPlane(paths:)` called
without required `telemetry` parameter (init signature had changed). Reordered to create
`TelemetryStore` first, then pass it to `MyceliumControlPlane`.

**Fix 2: TestWorkspace.swift** -- Missing `capabilities.json`. Added test config with
3 displays + 3 accessories matching CapabilityRegistryTests, IntentParserTests, and
DisplayCommandExecutorTests expectations. Used `homekit` transport for left-monitor
(no external tool dependency).

**Fix 3: SoulAnchorTests.swift** -- `writeCanonFiles(to:)` wrote to `mcuhist/MANIFEST.md`
without creating the `mcuhist/` directory first. `atomically: true` requires the parent
directory to exist. Added `FileManager.default.createDirectory(at: mcuDir, ...)`.

**Fix 4: DisplayCommandExecutorTests.swift** -- Three test logic bugs:
- Auth success test used `ddc-ci` transport (needs `m1ddc`, not installed). Changed
  left-monitor to `homekit` transport.
- Unauthorized display test used `voiceOperator` auth (allows ALL displays) with
  nonexistent display ID. Hit "not found" instead of "Not authorized". Fixed: use
  `tunnelClient` auth with real display ID to trigger auth denial.
- Both auth tests used `error.localizedDescription` (doesn't return custom description
  for `JarvisError`). Fixed: cast to `JarvisError` and use `.description`.

## 4. FINAL STATE

- **Build:** PASS
- **Tests:** 118 executed, 0 failures
- **All 12 remediation findings:** RESOLVED
- **Hard invariants:** A&Ox4, Voice Gate, NLB — all maintained