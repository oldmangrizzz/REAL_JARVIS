# Adversarial Canon Tests

**File:** `Jarvis/Tests/JarvisCoreTests/CanonAdversarialTests.swift`.
**Added:** 2026-04-20 (commit `8396d57`).
**Canon-floor contribution:** +9 tests → **138/138**.

## Doctrine

The adversarial canon battery exists to guarantee that the combat-hardened invariants in [[canon/PRINCIPLES|PRINCIPLES.md]] and [[canon/SOUL_ANCHOR|SOUL_ANCHOR.md]] cannot be silently regressed by future commits. Any failure here is a canon-gate violation — [[canon/CANON_GATE_CI|CI]] must reject the PR.

Berserker assumption: assume the frontier-LLM red team has full source access and is actively probing every seam. Write tests as if they already know the happy path.

## Coverage matrix

| Test | Invariant | Enforces |
|---|---|---|
| `testBlockedPatternsRejectObviousDestructiveCommands` | SPEC-008.1 blocklist | 15 explicit destructive phrases (burn/destroy/delete/erase/wipe/kill/format/factory-reset/self-destruct/shutdown/disable-safety/override/hack/exploit/jailbreak) → `.unknown` intent, confidence 0.0. |
| `testBlockedPatternsStillCaughtWithCasingAndPunctuation` | SPEC-008.1 robustness | UPPERCASE, ellipses, Title Case, "Hey Jarvis, please ..." prefixes still trip the blocklist. |
| `testBenignCommandsStillParse` | SPEC-008 false-positive floor | "put the dashboard on the left monitor" still parses as `.displayAction` with non-zero confidence. |
| `testRateLimiterHardCapsBurstVolume` | SPEC-008.2 hard cap | 100 rapid-fire calls against a 5-token bucket yield exactly 5 allowances. |
| `testRateLimiterReleasesAfterWindow` | SPEC-008.2 window behavior | Tokens regenerate after the window via `allow(now:)` injection. |
| `testCapabilityRegistryAssignsCorrectAuthorityPerNATONode` | Capability registry decode | Display IDs non-empty; authority decodes with safe default. |
| `testProductionCapabilitiesFileIncludesAllMeshNodes` | Mesh topology canon | `.jarvis/capabilities.json` includes echo + alpha + beta + foxtrot + charlie + delta. `XCTSkip` outside dev environment so CI doesn't fail on absence. |
| `testVoiceOperatorRoleBlockedWithoutGreenGate` | SPEC-007 | `authorizeRegistrationRole("voice-operator")` returns `(nil, error)` when voice-approval gate is not green. |
| `testUnknownRoleDoesNotLeakAuthorization` | SPEC-007 hardening | `""`, `admin`, `root`, `sudo`, `debug`, `operator`, `superuser` all rejected. No privilege escalation via creative role strings. |

## Why `@testable import JarvisCore`

The tests hit `IntentParser.parse` and `CommandRateLimiter.allow` directly — they're internal seams deliberately exposed for this battery. `JarvisHostTunnelServer.authorizeRegistrationRole` is also internal (SPEC-007 extracted it as a testable seam).

## Adding new adversarial tests

When a new SPEC lands, add its adversarial counterpart here. The rule: a test floor can **never decrease**. [[canon/CANON_GATE_CI|canon-gate CI]] enforces this via `Enforce canon floor` step.

## Related
- [[canon/SPECS_INDEX]] · [[canon/CANON_GATE_CI]] · [[canon/VERIFICATION_PROTOCOL]]
- [[codebase/modules/Interface]] (home of `IntentParser`, `CommandRateLimiter`)
- [[codebase/modules/Host]] (home of `authorizeRegistrationRole`)
- [[codebase/testing/TestSuite]]
