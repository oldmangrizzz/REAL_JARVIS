# VOICE-002 — Post-ship remediation (hand this to Gemini next session)

**Status:** VOICE-002 response shipped `Construction/Gemini/response/VOICE-002-response.md`,
implementation landed in-tree but **does not compile**. Four surgical fixes
below. None change the response doc's design — they fix lane-boundary
collisions and Swift 6 strict-concurrency bugs the response missed.

Do not re-ship the full response. Ship a **VOICE-002-FIX-01** patch response
with the 4 fixes + updated test count.

---

## Fix 1 — `DuplexVADGate` + `BargeInEvent` lane violation

**Problem:**

```
Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift:4
  public enum BargeInEvent: Sendable { … }      ← collides with Ambient struct
Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift:13
  public final class DuplexVADGate: @unchecked Sendable { … }
                                                  ← collides with Ambient protocol
```

Per **AMBIENT-002 §4.5.A** (shared contracts), `DuplexVADGate` is a
**protocol** and `BargeInEvent` is a **struct**, both owned by Qwen's
Ambient lane. Already in-tree at
`Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift:89-104`:

```swift
public protocol DuplexVADGate: Sendable {
    var bargeInSignal: AsyncStream<BargeInEvent> { get }
    func configure(stopWords: [String])
}

public struct BargeInEvent: Sendable, Equatable {
    public let at: Date
    public let reason: BargeInReason        // .vadTrigger | .stopWord | .explicit
    public let confidence: Double           // 0.0–1.0
}

public enum BargeInReason: String, Codable, Sendable, Equatable {
    case vadTrigger, stopWord, explicit
}
```

**Action:**

1. **Delete** `Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift`
   in its entirety.
2. In `ConversationEngine` (and anywhere else in `Conversation/`), import
   and consume the Ambient types directly. VOICE-002 subscribes to
   `DuplexVADGate.bargeInSignal` — it does not implement the gate.
3. If you had a concrete VAD implementation in that file, move it to
   `Jarvis/Sources/JarvisCore/Ambient/` under a different type name
   (e.g. `LocalStopWordVAD: DuplexVADGate`). Edge-side audio is Qwen's
   lane per §4.5.
4. Adapt any switch in ConversationEngine that assumed `BargeInEvent` was an
   enum — it's a struct with `reason: BargeInReason`. Switch on
   `event.reason` instead of `event` directly.

---

## Fix 2 — `HTTPTTSBackend` Sendable violation

**Problem:**

```
Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift:30
  private var activeTask: URLSessionDataTask?
  → error: stored property 'activeTask' of 'Sendable'-conforming class
    'HTTPTTSBackend' is mutable
```

NAV-001 §2 hard rule: Swift 6 strict concurrency, no warnings allowed.

**Action:** pick one:

- **Option A (preferred — safer):** make `HTTPTTSBackend` an `actor` and
  move `activeTask` inside the actor's isolated state. All streaming
  methods become `async` on the actor.
- **Option B (faster — if actor refactor is too invasive):** wrap
  `activeTask` in a dedicated `NSLock`-guarded box, or use
  `@unchecked Sendable` on the class with a `// swift-6-audit: <reason>`
  comment justifying why the mutable task pointer is safe (it's not,
  unless you lock it). Only use this if the task is never touched from
  more than one context.

Do not simply mark the property `nonisolated(unsafe)` without a lock.

---

## Fix 3 — `CompanionCapabilityPolicy` missing `.speakRealtime` case

**Problem:**

```
Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift:145
  error: switch must be exhaustive
```

You added `.speakRealtime` to `JarvisRemoteAction` in `TunnelModels.swift`
(line 13) but didn't extend the companion-tier decision matrix.

**Action:** add a case to `companionAllowsTunnelAction(_:)`:

```swift
case .speakRealtime:
    // Streaming speech is user-observable and reversible. Companion
    // tier may invoke it; guest/responder routing handled elsewhere.
    return .allow
```

Then verify the responder + guest tier paths also route `.speakRealtime`
correctly (grep for other switches over `JarvisRemoteAction` — there
should be 1–2 more).

---

## Fix 4 — Test target: missing `Conversation/` group in project.yml

**Problem:** `Jarvis/Tests/JarvisCoreTests/Conversation/ConversationEngineTests.swift`
exists on disk but is untracked and not in `project.yml`. On the next
`xcodegen generate`, it won't be picked up (the test target uses explicit
source paths for some folders).

**Action:** verify `project.yml` has the test target sources set to glob
`Jarvis/Tests/JarvisCoreTests/**/*.swift` (it probably does). If not,
add the `Conversation/` folder explicitly. Then `git add` the test
file + `project.yml` delta.

---

## Expected verification after fixes

```bash
xcodegen generate
xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep error:
# → no output (clean)

xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:JarvisCoreTests/ConversationEngineTests test
# → 25+ tests pass

xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
  -destination 'platform=macOS,arch=arm64' test
# → full suite 441 + 25+ new = 466+ / 466+, zero regressions
```

---

## What NOT to change

- **Response doc (`VOICE-002-response.md`)** — design is accepted as-shipped.
  Only ship a follow-up `VOICE-002-FIX-01-response.md` with the 4 fixes.
- **AMBIENT-002 §4.5** — contracts are canon. Conform to them, don't
  redefine them.
- **NAV-001 §11** — your preemption integration lives there. Don't
  duplicate it in ConversationEngine.
- **F5-TTS service changes** (`services/f5-tts/app.py`, `synthesizer.py`) —
  those are fine, unrelated to the Swift-side compile breaks.

Ship the fix. The loop's closed, just need the Sendable seal on the joints.
