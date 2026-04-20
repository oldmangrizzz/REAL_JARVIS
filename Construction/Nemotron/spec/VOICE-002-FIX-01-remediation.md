# VOICE-002-FIX-01 — Post-ship Swift compile remediation

**Target model:** NVIDIA Nemotron (Llama-3.3-Nemotron-Super-49B-v1 or
Nemotron-Ultra-253B, one fresh session)
**Parent spec:** `Construction/Gemini/spec/VOICE-002-realtime-speech-to-speech.md`
**Parent response (accepted as design, implementation broken):**
`Construction/Gemini/response/VOICE-002-response.md`
**Response path:** `Construction/Nemotron/response/VOICE-002-FIX-01-response.md`
— **one file, full source inline for every file you touch, no abbreviations, no
placeholders.**

---

detailed thinking on

---

## 0. Context you need before writing a single line

Gemini shipped VOICE-002 (realtime speech-to-speech) design + implementation
in one drop. The **design is accepted verbatim**. The Swift implementation
does not compile — four discrete bugs, three of them cross-lane contract
violations, one a Swift 6 strict-concurrency slip. Your job is the smallest
possible patch that makes the tree compile and the VOICE-002 test suite pass,
**without** redesigning any public surface the parent spec established.

You are not reviewing. You are not redesigning. You are patching.

Hard rules (inviolable, same as NAV-001 §2):
1. Swift 6, strict concurrency. `Sendable` where data crosses actor boundaries.
   `actor` for mutable orchestrator state. Zero warnings.
2. No new public APIs beyond what §1 of this spec names.
3. No edits to `Construction/GLM/**`, `Construction/Qwen/**`, or the
   Ambient source tree (`Jarvis/Sources/JarvisCore/Ambient/**`).
4. No edits to `services/f5-tts/**`. Those are clean, unrelated to the breaks.
5. `project.yml` is authoritative for Xcode. Run `xcodegen generate` after
   file moves.
6. Test runner: `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis
   -destination 'platform=macOS,arch=arm64' test`.

---

## 1. Exact file manifest for the patch

| # | Path | Action | Purpose |
|---|---|---|---|
| 1 | `Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift` | **delete** | Collides with Ambient-owned protocol + struct |
| 2 | `Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift` | edit | Consume Ambient `DuplexVADGate` protocol + `BargeInEvent` struct instead of the deleted local types |
| 3 | `Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` | edit | Resolve Sendable break on `activeTask` |
| 4 | `Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` | edit | Add `.speakRealtime` case to exhaustive switch |
| 5 | `project.yml` | edit (maybe) | Ensure `Conversation/` test subfolder is picked up by the test target |

No other files. If you find yourself editing anything else, stop and
re-read §0 rule 2.

---

## 2. Bug #1 — `DuplexVADGate` + `BargeInEvent` redeclaration

### 2.1 · What already exists (canon — do NOT redefine)

`Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift` lines 88–104:

```swift
/// VOICE-002 contract: local VAD that fires bargeInSignal.
public protocol DuplexVADGate: Sendable {
    var bargeInSignal: AsyncStream<BargeInEvent> { get }
    func configure(stopWords: [String])
}

public struct BargeInEvent: Sendable, Equatable {
    public let at: Date
    public let reason: BargeInReason
    public let confidence: Double           // 0.0–1.0
}

public enum BargeInReason: String, Codable, Sendable, Equatable {
    case vadTrigger
    case stopWord
    case explicit
}
```

### 2.2 · What Gemini wrote (wrong — delete)

`Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift`:

```swift
public enum BargeInEvent: Sendable { case speechStarted, speechEnded, stopWordDetected }
public final class DuplexVADGate: @unchecked Sendable {
    public init() {}
    public func subscribe() -> AsyncStream<BargeInEvent> { /* stub */ }
}
```

This enum collides with the Ambient **struct** of the same name. The class
collides with the Ambient **protocol** of the same name.

### 2.3 · Required action

1. Delete the file at path #1. The entire file.
2. In `ConversationEngine.swift` (path #2), adapt any consumer to:
   - Hold a stored property of type `any DuplexVADGate` (the Ambient
     protocol), injected at init.
   - Subscribe to `gate.bargeInSignal` (the protocol requires an
     `AsyncStream<BargeInEvent>` getter).
   - Switch on `event.reason` (of type `BargeInReason`). Map as:
     - `.vadTrigger`  → user started speaking; yield the LLM turn
     - `.stopWord`    → hard-cancel with <120ms p95 per parent §4
     - `.explicit`    → operator pressed cancel in UI
3. Do not create a concrete VAD implementation in
   `Conversation/`. Edge-side audio is Qwen's lane. If `ConversationEngine`
   needs a default gate for tests, inject a test double via its init;
   do not ship a production VAD here.

### 2.4 · Compile-time verification

After your edits:

```bash
rg -n 'class DuplexVADGate|enum BargeInEvent' Jarvis/Sources/
# Expected output: zero matches. Only the Ambient protocol + struct remain.
```

---

## 3. Bug #2 — `HTTPTTSBackend` Sendable break

### 3.1 · Diagnostic

```
Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift:30:17:
  error: stored property 'activeTask' of 'Sendable'-conforming
         class 'HTTPTTSBackend' is mutable
```

### 3.2 · Required action

Convert `HTTPTTSBackend` from a `public final class` to a `public actor`.

- Move every `var` inside the actor's isolated state.
- Existing `public func synthesize(...)` + `synthesizeStream(...)` signatures
  become `async` on the actor (they already perform `async` work internally;
  hoist the `async` to the declaration).
- Callers (grep: `rg 'HTTPTTSBackend\(' Jarvis/Sources`) must `await` the
  new signatures. Update callsites in the same PR.
- The actor can still conform to `TTSBackend` and `StreamingTTSBackend`; you
  may need to mark those protocol requirements with `async` in their
  definitions if they aren't already. Check
  `Jarvis/Sources/JarvisCore/Voice/TTSBackend.swift` and
  `Jarvis/Sources/JarvisCore/Voice/Conversation/StreamingProtocols.swift`.

If the actor refactor cascades into more than 6 call sites, stop and use
the fallback:

**Fallback (acceptable if actor refactor is too invasive):** keep the class,
mark `activeTask` as `nonisolated(unsafe)` **and** guard every read/write
with a `private let lock = NSLock()`. Do not use `nonisolated(unsafe)`
without a lock.

### 3.3 · Compile-time verification

```bash
xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
  -destination 'platform=macOS,arch=arm64' build 2>&1 \
  | grep -E "HTTPTTSBackend.*Sendable|HTTPTTSBackend.*mutable"
# Expected output: empty.
```

---

## 4. Bug #3 — `CompanionCapabilityPolicy` non-exhaustive switch

### 4.1 · Diagnostic

```
Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift:145:9:
  error: switch must be exhaustive
```

Gemini added `case speakRealtime = "speak_realtime"` to `JarvisRemoteAction`
at `Jarvis/Shared/Sources/JarvisShared/TunnelModels.swift:13` without
extending the tier-decision switch.

### 4.2 · Required action

In `CompanionCapabilityPolicy.companionAllowsTunnelAction(_:)`, add:

```swift
case .speakRealtime:
    // Streaming speech is user-observable and reversible at any turn.
    // Companion tier may invoke it.
    return .allow
```

Then grep for every other switch on `JarvisRemoteAction`:

```bash
rg -n 'switch .*\.action\b|switch action\b' Jarvis/Sources/ \
  | rg -v '//'
```

For each result, confirm either the switch has a `default:` arm or that
`.speakRealtime` is handled explicitly. Responder and guest tier gates
must also make a per-tier decision. Default posture if unclear: deny for
guest, allow for responder (responder tier is trusted for medical speech).

---

## 5. Bug #4 — `project.yml` and new test subfolder

### 5.1 · Check first

```bash
rg -n 'path: Jarvis/Tests/JarvisCoreTests' project.yml
```

If the JarvisCoreTests target uses a glob (e.g. `Jarvis/Tests/JarvisCoreTests/**/*.swift`)
no action needed — xcodegen will pick up the new `Conversation/` subfolder.
If it uses an explicit path list, add `Jarvis/Tests/JarvisCoreTests/Conversation`
to that list.

Regardless, after all edits run:

```bash
xcodegen generate
```

and verify the test file is in the generated project:

```bash
rg 'ConversationEngineTests' Jarvis.xcodeproj/project.pbxproj
# Expected: at least one match.
```

---

## 6. Response shape (follow this section order verbatim)

Your response document at
`Construction/Nemotron/response/VOICE-002-FIX-01-response.md` MUST have
exactly these section headers in this order. Each section is non-optional.

1. `## 1. Summary` — 3–5 sentences. What you changed, what you did not.
2. `## 2. Files touched` — markdown table: path, action (edit/delete), LOC delta.
3. `## 3. Bug #1 resolution — DuplexVADGate / BargeInEvent`
   - 3.1 File deleted (confirm path)
   - 3.2 `ConversationEngine.swift` — **full file source inline**, no abbreviations
4. `## 4. Bug #2 resolution — HTTPTTSBackend Sendable`
   - 4.1 Approach taken (actor / lock fallback)
   - 4.2 `HTTPTTSBackend.swift` — full file source inline
   - 4.3 Protocol definition file(s) if you changed them — full source inline
   - 4.4 Call-site deltas — path + surgical diff for each
5. `## 5. Bug #3 resolution — CompanionCapabilityPolicy`
   - 5.1 `CompanionCapabilityPolicy.swift` — full file source inline
   - 5.2 Other switches audited — list + per-switch disposition
6. `## 6. Bug #4 resolution — project.yml`
   - Output of the `rg` check + any delta
7. `## 7. Verification log` — paste verbatim output of the three commands:
   ```
   xcodegen generate
   xcodebuild … build 2>&1 | grep error:
   xcodebuild … test 2>&1 | tail -20
   ```
8. `## 8. Test count delta` — old suite / new suite / net.

---

## 7. Out of scope (refuse to ship)

- Any change to `Construction/**` other than creating your response doc.
- Any change to `services/f5-tts/**`.
- Any change to `Ambient/AmbientAudioGateway.swift` or other Ambient files.
- Any change to `ConversationSession.swift`, `StreamingProtocols.swift`,
  `StreamingBackendImplementations.swift`, or `ConversationTelemetry.swift`
  that is not strictly required by Bug #1's type-rewire.
- Any new public API.
- Any redesign of the 5-hop latency budget or the SLA miss schema.

---

## 8. Acceptance gate

The patch is accepted iff **all** of the following are true:

1. `xcodebuild … build 2>&1 | grep error:` returns empty.
2. `xcodebuild … test` exits zero with the JarvisCoreTests suite at
   441 + ConversationEngineTests count, **zero regressions** in the
   pre-existing 441.
3. No file under `Construction/Gemini/`, `Construction/Qwen/`,
   `Construction/GLM/` changes.
4. No file under `Jarvis/Sources/JarvisCore/Ambient/` changes.
5. The response doc follows §6 section order exactly.

If any gate fails, ship a `VOICE-002-FIX-02` follow-up. Do not hand-wave.

---

## 9. Greenlight

Ship the patch. One response, one fresh session, full source inline per
§6. Close the loop.
