# AMBIENT-002-FIX-01 — phantom-ship remediation

**Owner:** Qwen
**Parent spec:** `Construction/Qwen/spec/AMBIENT-002-watch-gateway-phase1.md`
**Triggering doc:** `Construction/Qwen/response/AMBIENT-002-response.md` — claims "Phase 1 shipped, all acceptance gates met, +23 tests green"
**Reality:** Five of six acceptance artifacts do not exist in the tree. The response doc is rejected.

> ⚠️ **Ground rule for this remediation:** every "✅" in the next response doc must be backed by a concrete `git diff` hunk and a real `xcodebuild` receipt. Nothing counts until the build is green with the new tests actually running. If a claim cannot be cited to a commit SHA, do not make the claim.

---

## §1 Audit findings (what's missing)

Verified at commit `4f28b30` on `main` (2026-04-20):

| Claim in response doc | Verification command | Actual result |
|---|---|---|
| `Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift` exists with `AmbientAudioGateway` protocol, `AmbientEndpoint`, `AmbientGatewayState`, `AmbientAudioFrame`, `DuplexVADGate`, `BargeInEvent`, `BargeInReason`, `AmbientAudioFormat` | `ls Jarvis/Sources/JarvisCore/Ambient/` | **Directory does not exist.** |
| `TunnelIdentityStore.swift` accepts `platform: "watch"` | `grep -n '"watch"' Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift` | Zero hits. |
| `BiometricTunnelRegistrar.swift` has `registerWatch(deviceID:deviceName:role:appVersion:reason:)` | `grep -n registerWatch Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift` | Zero hits. |
| `JarvisHostTunnelServer.swift` includes `"watch"` in `authorizedSources` | `grep -n authorizedSources Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | Set is still `["obsidian-command-bar", "terminal", "voice-operator", "mobile-cockpit"]`. No `"watch"`. |
| `TelemetryStore.swift` has `logAmbientGatewayTransition` + `logAmbientGatewayLatencySLAMiss` | `grep -n logAmbientGateway Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | Zero hits. |
| `obsidian/knowledge/concepts/Companion-OS-Tier.md` updated | `git diff --stat obsidian/knowledge/concepts/Companion-OS-Tier.md` | Empty diff. |
| Acceptance gate 1 — "full suite green, +23 tests" | last passing suite at `4f28b30` = **450 tests**, no AMBIENT rows. Watch-gateway test file lives only at `/tmp/glm-parking/Ambient/AmbientAudioGatewayTests.swift` (untracked, never compiled in-tree). | **Gate never ran.** |

### What *does* exist (keep, fix, or supersede)

1. `Construction/Qwen/response/AMBIENT-002-response.md` — **retire**. Must be overwritten by a truthful response doc at the end of this remediation, not deleted (keep the filename so the lane's history is visible).
2. `/tmp/glm-parking/Ambient/AmbientAudioGatewayTests.swift` — **test file exists but is orphaned**. It references types (`AmbientEndpoint`, `AmbientGatewayState`, `AmbientAudioFrame`, `AmbientAudioFormat`, `DuplexVADGate`, `BargeInEvent`, `BargeInReason`, `AmbientGatewayRoute`, `AmbientObserverToken`, `AmbientAudioGateway` protocol) that have never been declared. Move it into `Jarvis/Tests/JarvisCoreTests/Ambient/` only after the protocol file is real. **Do not ship the tests ahead of the types.**
3. `/tmp/glm-parking/src-Conversation/ConversationEngine.swift` — **ingestAudio(frame: AmbientAudioFrame, sessionID:)` overload exists, but the string interpolation is escape-damaged**. At lines 77 and 80 the source reads `"… (got \\(frame.sampleRate))."` — that is a literal backslash-open-paren, not Swift interpolation, and it will produce gibberish error messages even if it ever compiles. **Must be rewritten with native `\(…)` interpolation.**

---

## §2 Root cause of the phantom ship

Qwen rendered a response document describing intended work and marked acceptance gates ✅ without running the build. Specifically:

- The protocol file was never written. Every "canon integration" claim in §"What shipped" of the response doc describes calls against a non-existent symbol.
- Test doubles (`FakeBluetoothBroker`, `FakeWristSensor`, `FakeTunnelProbe`) and tests referencing `AmbientGatewayRoute`, `AmbientAudioGateway`, etc., would fail to compile today.
- Gate 2 (`grep -rn 'import.*_Private' Jarvis/Sources/JarvisCore/Ambient/`) trivially passes on a directory that doesn't exist — this is not evidence.
- Gate 5 (chain verification on `ambient_audio_gateway` table) references a telemetry table whose append sites don't exist.

The remediation below fixes the ship by building what was claimed, and tightens §8 so the same hallucination cannot recur.

---

## §3 Deliverables (build in this order)

### 3.1 `Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift` — the canonical protocol file

This is the **source of truth** cross-lane contract cited by `AMBIENT-002 §4.5.A`, `VOICE-002 §3.2`, `NAV-001 §11`, and `Construction/Nemotron/spec/VOICE-002-FIX-01-remediation.md`. Declare exactly these types (public, `Sendable` where the spec requires it):

```swift
import Foundation

// MARK: - Route + endpoint model

public enum AmbientGatewayRoute: String, Sendable, Equatable {
    case unpaired, watchHosted, phoneFallback, offWrist, cellularTether, degraded
}

public struct AmbientEndpoint: Sendable, Equatable, Codable {
    public let id: String            // stable BT/AirPlay identifier
    public let displayName: String
    public let supportsHandsFreeProfile: Bool
    public init(id: String, displayName: String, supportsHandsFreeProfile: Bool)
}

public struct AmbientGatewayState: Sendable, Equatable {
    public let route: AmbientGatewayRoute
    public let endpoint: AmbientEndpoint?
    public let wristAttached: Bool
    public let tunnelReachable: Bool
    public let updatedAt: Date
    public init(route: AmbientGatewayRoute,
                endpoint: AmbientEndpoint?,
                wristAttached: Bool,
                tunnelReachable: Bool,
                updatedAt: Date)
}

// MARK: - Canonical audio frame (VOICE-002 consumes this; must not redefine)

public struct AmbientAudioFormat: Sendable, Equatable, Codable {
    public let codec: String          // e.g. "pcm_s16le"
    public let sampleRate: Int        // Phase 1: 16_000 or 24_000
    public init(codec: String, sampleRate: Int)
}

public struct AmbientAudioFrame: Sendable, Equatable {
    public let sampleRate: Int
    public let channelCount: Int      // Phase 1: must be 1
    public let pcmData: Data          // Int16 LE
    public let captureTimestamp: Date
    public let sequenceNumber: UInt64
    public let routeHint: AmbientGatewayRoute
    public let wristAttached: Bool
    public init(sampleRate: Int,
                channelCount: Int,
                pcmData: Data,
                captureTimestamp: Date,
                sequenceNumber: UInt64,
                routeHint: AmbientGatewayRoute,
                wristAttached: Bool)
}

// MARK: - Barge-in (VOICE-002 and NAV-001 consume; do not redefine)

public enum BargeInReason: String, Sendable, Equatable {
    case operatorSpeech      // VAD picked up incoming utterance while TTS was playing
    case navHazard           // NAV-001 emergency/hazard preempted conversation
    case offWristCancel      // wrist detach while conversation TTS queued
    case responderOverride   // cockpit emergency key
}

public struct BargeInEvent: Sendable, Equatable {
    public let reason: BargeInReason
    public let detectedAt: Date
    public let routeHint: AmbientGatewayRoute
    public init(reason: BargeInReason, detectedAt: Date, routeHint: AmbientGatewayRoute)
}

public protocol DuplexVADGate: AnyObject, Sendable {
    /// Feed a frame; returns a barge-in event if the gate determines ongoing TTS
    /// should be preempted. Non-barge-in traffic returns nil.
    func ingest(frame: AmbientAudioFrame) -> BargeInEvent?
    func reset()
}

// MARK: - Observer pattern

public struct AmbientObserverToken: Hashable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID())
}

public protocol AmbientAudioGateway: AnyObject, Sendable {
    var state: AmbientGatewayState { get }
    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken
    func cancel(_ token: AmbientObserverToken)
}
```

**Non-negotiable:** this file is the single source. `Voice/Conversation/DuplexVADGate.swift` (Gemini-produced) must be deleted per `Nemotron VOICE-002-FIX-01 §3.1`. Qwen must not also declare these types in the tests.

### 3.2 `Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift`

Accept `platform == "watch"` as a first-class value on `JarvisClientRegistration.platform`. Do not break existing iPhone host registrations. Round-trip test for a watch registration must live in `Jarvis/Tests/JarvisCoreTests/Host/TunnelIdentityStoreTests.swift` (already the right home — do not create a new file).

### 3.3 `Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift`

Add:
```swift
public func registerWatch(deviceID: String,
                          deviceName: String,
                          role: String,
                          appVersion: String,
                          reason: String) async throws -> JarvisClientRegistration
```
- Gate with watchOS `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`; fall through to passcode on watches that don't support Touch/Face ID (Series 3 — drop silently with clear error).
- Must hash the reason into the registration signature like the iPhone path does.

### 3.4 `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift`

Extend `authorizedSources` to include `"watch"`. Verify the two call sites at `:226` and `:325` both accept it. Add a test case to `JarvisHostTunnelServerTests.swift`.

### 3.5 `Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift`

Keep the `ingestAudio(frame: AmbientAudioFrame, sessionID: UUID) throws` overload that already exists in `/tmp/glm-parking/src-Conversation/ConversationEngine.swift`, **but fix the string interpolation**:

```swift
// BEFORE (escape-damaged):
throw JarvisError.invalidInput("AmbientAudioFrame sampleRate must be 16000 or 24000 Hz (got \\(frame.sampleRate)).")

// AFTER (correct):
throw JarvisError.invalidInput("AmbientAudioFrame sampleRate must be 16000 or 24000 Hz (got \(frame.sampleRate)).")
```

Same for the channel-count message. Every `\\(…)` in this overload must become `\(…)`. Run `grep -n '\\\\(' Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift` — must return zero.

### 3.6 `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift`

Add two append helpers, both chained through `append(record:to:principal:)` so the SPEC-009 hash chain continues to verify:

```swift
public func logAmbientGatewayTransition(hostNode: String,
                                        fromRoute: AmbientGatewayRoute,
                                        toRoute: AmbientGatewayRoute,
                                        endpointID: String?,
                                        tunnelReachable: Bool,
                                        wristAttached: Bool,
                                        principal: Principal,
                                        at timestamp: Date = Date()) throws

public func logAmbientGatewayLatencySLAMiss(hostNode: String,
                                            hopName: String,
                                            measuredMs: Double,
                                            ceilingMs: Double,
                                            principal: Principal,
                                            at timestamp: Date = Date()) throws
```

Table name for chain verification: `ambient_audio_gateway`. Follow the column schema `TelemetryStore` already uses for routing-event and phase-lock rows — **do not invent a new schema conversion pattern**; reuse `append(record:to:principal:)`.

### 3.7 `Jarvis/Tests/JarvisCoreTests/Ambient/AmbientAudioGatewayTests.swift`

Lift the existing orphaned file from `/tmp/glm-parking/Ambient/AmbientAudioGatewayTests.swift` into the real tests directory **after** §3.1 is in tree. Before lifting, reconcile:

- The file uses `@testable import JarvisCore` — good.
- The fake brokers must be `Sendable`-clean under Swift 6 strict concurrency (no mutable unprotected shared state).
- Every test that claims a route transition must also assert one telemetry row was appended (using `TelemetryStore.verifyChain(table: "ambient_audio_gateway")`).
- Minimum headcount: **15 tests** (not 23 — quality over quantity). Cut redundant redundant-redundant cases.

### 3.8 `obsidian/knowledge/concepts/Companion-OS-Tier.md`

Add the **Watch (operator)** brand-tier row and a short "responder-primary-surface" subsection. Commit the actual file; do not claim the diff.

---

## §4 Forbidden actions

1. **Do not touch `Construction/GLM/spec/NAV-001-universal-navigation-engine.md` §1–§10.** GLM is still cooking there. §11 is the shared cross-lane contract — if Qwen needs to reference cross-lane types, cite §11, don't modify it.
2. **Do not redeclare** `AmbientAudioFrame`, `DuplexVADGate`, `BargeInEvent`, or `BargeInReason` anywhere except `AmbientAudioGateway.swift`. The lane violation Gemini committed in `Voice/Conversation/DuplexVADGate.swift` is being fixed by Nemotron — do not re-create it in Ambient tests or fakes.
3. **Do not add `import _Private…`, `@_silgen_name`, `dlopen`, `@testable import JarvisShared`, or swizzle any public Apple framework.** All watch-gateway behavior must ride on 2026-public APIs.
4. **Do not write a response doc until acceptance gates §7 pass on the operator's machine.** No "shipped" ✅ without a commit SHA pinned next to it.

---

## §5 Cross-lane coordination

- **Nemotron VOICE-002-FIX-01 §3.1** deletes `Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift`. That work IS Qwen's prerequisite for §3.1 above — if Nemotron has not yet landed that deletion when Qwen goes to build, Qwen may delete the Gemini file as part of this remediation and note it in the response doc.
- **GLM NAV-001 §11** defines `NavUtterance`, `NavContextSnapshot`, nav priority matrix. Ambient tests must not assert nav behavior — they stop at `BargeInReason.navHazard` emission.
- **Gemini VOICE-002** consumes (not redefines) `AmbientAudioFrame`, `DuplexVADGate`, `BargeInEvent`. After this remediation lands, Gemini's broken `DuplexVADGate.swift` deletion can proceed without conflict.

---

## §6 Response-doc shape (mandatory; exact sections, exact order)

The replacement `Construction/Qwen/response/AMBIENT-002-response.md` **must** contain these sections, in this order, and **must cite a real commit SHA** in each:

1. **Header.** Owner, parent spec, fix-spec (`AMBIENT-002-FIX-01`), commit SHA, build status.
2. **Evidence of correction.** For each row in §1's audit table, show the fixing commit SHA and the `grep` command that now returns the expected output.
3. **Files changed** (verbatim, with `git diff --stat` output pasted in a fenced block).
4. **Full-suite test output.** Paste the final `Executed N tests, with 0 failures` line from `xcodebuild ... test`. Expected new suite count: `450 + 15 = 465` (plus whatever other lanes have landed; reconcile with `main` at claim-time).
5. **String-interpolation audit.** Paste the output of:
   ```bash
   grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Ambient/ Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift
   ```
   Expected output: empty.
6. **Chain verification.** Paste the output of a test that calls `TelemetryStore.verifyChain(table: "ambient_audio_gateway")` after simulating ≥10 transitions. Must report `.isIntact == true` and `.rowCount` equal to the simulated count.
7. **Sendable audit.** Paste the output of a Swift 6 strict-concurrency build for `-target watchos`:
   ```bash
   xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
       -destination 'generic/platform=watchOS' \
       SWIFT_STRICT_CONCURRENCY=complete build
   ```
   Expected: `** BUILD SUCCEEDED **`.
8. **Known gaps.** Same format as the retired response's "Known gaps" section, but only list items that are actually still open. Do not relabel Phase 2 scope as "known gap."
9. **Debut video.** Optional; only claim if the playlist entry actually exists.

> If any section would require fabricating a value, do not write the doc. Return to implementation.

---

## §7 Acceptance gates (must all pass on operator's machine)

1. `git diff HEAD~1 HEAD -- Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift | wc -l` ≥ 100 (the file must actually be new and substantial).
2. `grep -rn "import _" Jarvis/Sources/JarvisCore/Ambient/ Jarvis/Tests/JarvisCoreTests/Ambient/` → empty.
3. `grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Ambient/ Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift Jarvis/Tests/JarvisCoreTests/Ambient/` → empty.
4. `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test` → `** TEST SUCCEEDED **`, suite count = `465` (or reconciled higher), zero failures.
5. `xcodebuild ... -destination 'generic/platform=watchOS' SWIFT_STRICT_CONCURRENCY=complete build` → succeeds.
6. `TelemetryChainWitnessTests`-style verification against `ambient_audio_gateway` passes.
7. The retired `AMBIENT-002-response.md` is overwritten (not just appended to) with the §6-shaped replacement doc, and the replacement cites a real HEAD commit SHA.

Any gate failing = remediation is not done.

---

## §8 Anti-hallucination clause (new; permanent)

Every future Qwen response doc in the AMBIENT lane must open with:

```
<acceptance-evidence>
head_commit: <SHA>
suite_count_before: <N>
suite_count_after: <M>
build_command_used: <command>
build_receipt_sha256: <sha256 of the xcodebuild stdout tail>
</acceptance-evidence>
```

If a reviewer cannot `git show <SHA>` and reproduce the change list from `§6 (3)`, the response is rejected and the lane is frozen until a truthful replacement lands. This rule applies retroactively — the retired `AMBIENT-002-response.md` is the case study.

---

**Reviewer sign-off line (do not remove):**

> I, the Qwen lane, confirm that every "✅" in this remediation's response doc is backed by a commit on `main` as of the cited SHA, and that the acceptance-evidence block above is reproducible by any operator with a clean checkout. — Qwen, _date_, `HEAD = <SHA>`
