# SPECS_INDEX — SPEC-001..011 Ledger

**Source of truth:** `PRODUCTION_HARDENING_SPEC.md` at repo root.
**Status as of:** 2026-04-20T07:25.
**Test floor:** 138/138 (see [[canon/VERIFICATION_PROTOCOL|VERIFICATION_PROTOCOL §gate-2]]).

## Ledger

| SPEC | Title | Status | Landed commit | Surface | Tests |
|---|---|---|---|---|---|
| SPEC-001 | Canon-file SHA-256 hash manifest | DONE | pre-2026-04 | [[codebase/modules/Canon]] | CanonManifestTests |
| SPEC-002 | Alignment-tax pre-action writer | DONE | pre-2026-04 | [[codebase/modules/Canon]] AlignmentTaxWriter | AlignmentTaxTests |
| SPEC-003 | A&Ox4 short-circuit gate | DONE | pre-2026-04 | [[codebase/modules/RLM]] | AOx4Tests |
| SPEC-004 | VoiceCommandRouter ↔ IntentParser ↔ CapabilityRegistry ↔ DisplayCommandExecutor rewire | DONE | `7f35e8d` | [[codebase/modules/Interface]] `RealJarvisInterface.swift` | VoiceCommandRouterTests |
| SPEC-005 | Soul-Anchor Lockdown verifier | DONE | pre-2026-04 | [[codebase/modules/SoulAnchor]] | LockdownVerifierTests |
| SPEC-006 | Voice-Approval-Gate fail-closed path | DONE | pre-2026-04 | [[codebase/modules/Voice]] VoiceApprovalGate | VoiceGateTests |
| SPEC-007 | Voice-operator tunnel role gated on green voice-approval | DONE | `0200146` | [[codebase/modules/Host]] JarvisHostTunnelServer | JarvisHostTunnelServerTests (3 new) |
| SPEC-008 | Destructive-intent blocklist + command rate limit | DONE | `7a8ad00` | [[codebase/modules/Interface]] IntentParser.blockedPatterns + CommandRateLimiter | VoiceCommandRouterTests (2 new) + [[canon/ADVERSARIAL_TESTS]] |
| SPEC-009 | NLB summarizer in-the-loop | DONE | pre-2026-04 | [[codebase/modules/Core]] | NLBSummarizerTests |
| SPEC-010 | Telemetry decoupling (`VoiceGateTelemetryRecording` protocol) | DONE | pre-2026-04 | [[codebase/modules/Voice]] + [[codebase/modules/Telemetry]] | TelemetryDecouplingTests |
| SPEC-011 | Tunnel unauthenticated idle-timeout kick | DONE | `da8c3a6` | [[codebase/modules/Host]] | TunnelIdleKickTests |

## Evidence trail for the 2026-04-20 delta

Each SPEC below carries the same verification bundle per [[canon/VERIFICATION_PROTOCOL]]:

### SPEC-004 (commit `7f35e8d`)
- `VoiceCommandRouter.route()` stays synchronous; async executor bridged via `awaitSync` / `AwaitSyncBox: @unchecked Sendable`.
- `DisplayCommandExecutor` marked `@unchecked Sendable` for Swift 6 strict concurrency.
- `CapabilityRegistry.matchAction` collapses both "hud" and "dashboard" transcripts to `display-dashboard` — tests asserting `"display-hud"` will mis-fire.
- `action` key added to dispatch details so HomeKit-routed actions carry the parsed action label.
- 124/124 → 127 at landing (delta = +3 SPEC-004 tests, though most already existed).

### SPEC-007 (commit `0200146`)
- `JarvisHostTunnelServer.authorizedSources` extended: `obsidian-command-bar`, `terminal`, **`voice-operator`**, **`mobile-cockpit`**.
- `authorizeRegistrationRole(_:)` extracted as internal testable seam; returns `(role?, error?)`.
- `voice-operator` requires `runtime.voice.approval.snapshotForSpatialHUD().state == .green`. Gate-not-green → rejection + telemetry.
- Test count: 127 → **129**.

### SPEC-008 (commit `7a8ad00`)
- `IntentParser.blockedPatterns` (17 patterns) + `isBlockedIntent()` short-circuit. Blocklist runs *before* verb matching — destructive intent can't ride on legitimate verbs.
- `CommandRateLimiter` (5 commands / 60s token-bucket) wired into `RealJarvisInterface.dispatchThroughExecutor`.
- Over-cap → spoken refusal ([`CommandRateLimiter.limitExceededResponse`]) + telemetry with `status: command_refused`.
- `logExecutionTrace` signature is `(workflowID:stepID:inputContext:outputResult:status:)` — positional args will not compile.
- Test count: 129.

### Adversarial canon battery (commit `8396d57`, 2026-04-20)
See [[canon/ADVERSARIAL_TESTS]]. **+9 tests → 138/138.** This is the new floor.

## Related
- [[canon/VERIFICATION_PROTOCOL]] · [[canon/ADVERSARIAL_TESTS]] · [[canon/REPAIR_INDEX]]
- [[history/REMEDIATION_TIMELINE]]
