<!--
  AMBIENT-002 response doc (replacement)
  Governing spec:  Construction/Qwen/spec/AMBIENT-002-FIX-01-phantom-ship.md
  Governing standard: MEMO_CLINICAL_STANDARD.md (verify, don't assume)
-->

<acceptance-evidence>
head_commit: d1cab26c984a7e8e314a45a320742bdefe1c9796
suite_count_before: 634
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
build_receipt_sha256: 3dfa6466ca9ac63256fb66a4b1d0c19f1526409bf5ce08f65a1eade38c0b7163
</acceptance-evidence>

# AMBIENT-002 — Watch-tier phantom-ship remediation (response)

## §1 Header

- **Lane owner:** Qwen
- **Parent spec:** `Construction/Qwen/spec/AMBIENT-002-ambient-audio-gateway.md`
- **Fix spec:** `Construction/Qwen/spec/AMBIENT-002-FIX-01-phantom-ship.md`
- **Commit SHA:** `d1cab26c984a7e8e314a45a320742bdefe1c9796`
- **Build status:** macOS `** TEST SUCCEEDED **` (659 / 1 skip / 0 fail) ·
  watchOS strict-concurrency `** BUILD SUCCEEDED **`

## §2 Evidence of correction — audit row by row

Every row in the fix-spec §1 audit table is backed by a commit (all rolled
into `d1cab26`) and a grep that returns the spec-expected output.

| Audit row (fix-spec §1) | Fixing commit | Verification command | Expected | Observed |
|---|---|---|---|---|
| 1.1  Ambient file in wrong target (`JarvisShared/Ambient/…`) | `d1cab26` | `test -f Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift && echo ok` | `ok` | `ok` |
| 1.2  Tests entirely `#if false` quarantined | `d1cab26` | `grep -c "^    func test" Jarvis/Tests/JarvisCoreTests/Ambient/AmbientAudioGatewayTests.swift` | `>= 15` | `17` |
| 1.3  `watch` missing from `authorizedSources` | `d1cab26` | `grep -n '"watch"' Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | non-empty | `10:…"watch"…` |
| 1.4  `watch` missing from `privilegedRoles` | `d1cab26` | `grep -n '"watch"' Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift` | non-empty | `65:…"watch"…` |
| 1.5  No `registerWatch(...)` entry point | `d1cab26` | `grep -n 'func registerWatch' Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift` | non-empty | present |
| 1.6  Ambient telemetry helpers absent | `d1cab26` | `grep -n 'logAmbientGateway' Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | two hits | `logAmbientGatewayTransition`, `logAmbientGatewayLatencySLAMiss` |
| 1.7  Watch row absent from Companion-OS-Tier | `d1cab26` | `grep -n '^## Watch' obsidian/knowledge/concepts/Companion-OS-Tier.md` | non-empty | present |
| 1.8  `ConversationEngine` sync-VAD backslash-escaped interpolation | `d1cab26` | `grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift` | empty | empty |

## §3 Files changed

```
 .gitignore                                                            |   3 +
 Jarvis.xcodeproj/project.pbxproj                                      |  28 +-
 Jarvis/Shared/Sources/JarvisShared/Ambient/AmbientAudioGateway.swift  | 112 -----
 Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift           | 135 ++++++
 Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift         |  45 ++
 Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift           |   2 +-
 Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift              |   2 +-
 Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift              |  44 ++
 Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift |  28 +-
 Jarvis/Tests/JarvisCoreTests/Ambient/AmbientAudioGatewayTests.swift   | 961 ++++++++++++++++++++++--------------------
 Jarvis/Tests/JarvisCoreTests/BiometricTunnelRegistrarTests.swift      | 106 +++++
 Jarvis/Tests/JarvisCoreTests/JarvisHostTunnelServerTests.swift        |  18 +
 Jarvis/Tests/JarvisCoreTests/TunnelIdentityStoreTests.swift           |  80 ++++
 obsidian/knowledge/concepts/Companion-OS-Tier.md                      |  60 +++
 14 files changed, 1022 insertions(+), 602 deletions(-)
```

## §4 Full-suite test output

```
Test Suite 'All tests' passed at 2026-04-22 …
    Executed 659 tests, with 1 test skipped and 0 failures (0 unexpected) in …

** TEST SUCCEEDED **
```

Baseline on `4891e1e` (pre-remediation): 634 tests / 1 skip / 0 fail.
Post-remediation: 634 + 25 new = 659 / 1 skip / 0 fail. Delta exactly
matches the new test count across §3.2, §3.3, §3.4c, §3.6, §3.7.

Receipt: `/tmp/test-post-change-qwen-ambient.log` · sha256
`3dfa6466ca9ac63256fb66a4b1d0c19f1526409bf5ce08f65a1eade38c0b7163`.

## §5 String-interpolation audit

```
$ grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Ambient/ \
                    Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift
(no output)
```

Empty, as required. `ConversationEngine.ingestAudio(frame:sessionID:)` now
uses correct Swift interpolation (`\(frame.sampleRate)` etc.).

## §6 Chain verification

Active test in `AmbientAudioGatewayTests` simulates ≥10 route transitions
via `TelemetryStore.logAmbientGatewayTransition(...)`, then asserts:

```swift
let report = try store.verifyChain(table: "ambient_audio_gateway")
XCTAssertTrue(report.isIntact)
XCTAssertEqual(report.totalRows, simulatedTransitionCount)
XCTAssertNil(report.brokenAt)
```

All assertions pass in the final green run (§4).

> **Spec deviation (call-out, see §8):** fix-spec §6.6 refers to this
> field as `.rowCount`. The real `TelemetryChainReport` type exposes
> `.totalRows`, `.hashedRows`, `.legacyRows`, `.brokenAt`. The tests
> assert `.totalRows`; the fix-spec is the thing that's wrong here, not
> the implementation.

## §7 Sendable / strict-concurrency audit

```
$ xcodebuild -scheme JarvisWatchCore \
             -destination 'generic/platform=watchOS' \
             SWIFT_STRICT_CONCURRENCY=complete build
…
** BUILD SUCCEEDED **
```

Zero strict-concurrency errors, zero warnings. `FakeAmbientAudioGateway`
and the test doubles in `AmbientAudioGatewayTests` are `Sendable`-clean.

## §8 Known gaps

1. **Fix-spec §6.6 field-name drift (`rowCount` vs `totalRows`).** Spec
   text says `.rowCount`; real type is `TelemetryChainReport.totalRows`.
   Tests assert `.totalRows`. A one-line spec correction is owed by the
   spec author; no code change needed.
2. **Watch-tier end-to-end path not exercised on a physical Apple Watch.**
   This commit lands the host + telemetry + ambient scaffolding and unit
   coverage. The on-wrist integration test (real `WKInterfaceDevice`
   wrist-detect events against the live host) is parked for a dedicated
   hardware-in-loop session and is not claimed as ✅ here.
3. **Journey kit fleet not yet installed.** The 15 kits the operator
   queued at session start (journey, morning-brief, personal-knowledge-
   wiki, humanizer, supabuilder, memory-stack-integration, multi-agent-
   game-dev, determinism-guard, self-improve-harness, skill-drift-
   detector, rsi-starter-loop, context-guard, personal-ops-loop,
   proposal-to-pdf, data-analysis-suite, itp-parallel-agent-cost-saver)
   were deferred in favour of the Qwen burndown. Scope re-confirm
   pending with operator before any further installs.

## §9 Debut video

Not claimed. No playlist entry exists.

---

> I, the Qwen lane, confirm that every "✅" in this remediation's response
> doc is backed by the commit on `main` at SHA
> `d1cab26c984a7e8e314a45a320742bdefe1c9796`, and that the
> acceptance-evidence block above is reproducible by any operator with a
> clean checkout. — Qwen, 2026-04-22, `HEAD = d1cab26`
