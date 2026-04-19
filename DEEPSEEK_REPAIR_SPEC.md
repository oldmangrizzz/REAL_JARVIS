# DEEPSEEK 3.2 REPAIR SPEC — JARVIS Remaining Remediation

**Role:** Fixer. 6 tasks. All MEDIUM severity. Execute them all. Do not stop, do not ask questions, do not get chatty.
**Context:** A previous model (Gemma 4 31B) completed the CRITICAL and HIGH tasks but stalled on these MEDIUMs.
**Baseline:** 74 tests, 0 failures, build green. You MUST maintain this baseline after every task.

---

## CODEBASE

- **Language:** Swift 6, strict concurrency (`SWIFT_VERSION: 6.0`)
- **Build system:** XcodeGen → Xcode
- **Regenerate project:** `cd /Users/grizzmed/REAL_JARVIS && xcodegen generate`
- **Build:** `xcodebuild build -scheme Jarvis -destination 'platform=macOS' -quiet`
- **Test:** `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -quiet`
- **Current test count:** 74 tests, 0 failures

---

## EXECUTION RULES

1. Read the target file BEFORE modifying it.
2. Build + test AFTER every task.
3. If a task breaks the build, FIX IT before moving on.
4. Do NOT modify files outside the scope of each task.
5. Do NOT refactor surrounding code.
6. Do NOT add comments, docstrings, or features beyond what's specified.
7. After all 6 tasks, write a completion report to `/Users/grizzmed/REAL_JARVIS/DEEPSEEK_COMPLETION_REPORT.md`.

---

## TASK 1: VoiceApprovalGate Error Differentiation [MEDIUM-001]

**Problem:** `isApproved()` and `requireApproved()` use `try?` on `loadRecord()`, making IO errors indistinguishable from "not approved."

**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift`

### Fix for `requireApproved()` (line 136):

Change:
```swift
guard let record = try? loadRecord() else {
```

To:
```swift
let record: GateRecord?
do {
    record = try loadRecord()
} catch {
    emit(eventType: "playback_refused",
         composite: current.composite,
         expectedComposite: nil,
         operatorLabel: nil,
         notes: "gate file read error: \(error.localizedDescription)")
    syncState(state: "malformed",
              composite: current.composite,
              expectedComposite: nil,
              session: session,
              personaFramingVersion: personaFramingVersion,
              operatorLabel: nil,
              approvedAtISO8601: nil,
              notes: "IO error: \(error.localizedDescription)")
    throw VoiceApprovalError.notApproved(
        currentComposite: current.composite,
        gatePath: gateFileURL.path
    )
}
guard let record else {
```

**Important:** The existing code after the guard (lines 137-153) handles the "no gate file" case with `emit()` and `syncState()`. Your replacement must keep the `guard let record else { ... }` pattern for the nil case (file doesn't exist returns nil from loadRecord). The `do/catch` handles the ERROR case (file exists but is unreadable/corrupted).

Check what `loadRecord()` returns — it may return `nil` for "file not found" and throw for "file corrupted." If so, the `do/catch` catches corruption and the `guard let record else` catches missing file. Both paths are needed.

### Fix for `isApproved()` (line 125):

Change:
```swift
guard let record = try? loadRecord() else { return false }
```

To:
```swift
let record: GateRecord?
do {
    record = try loadRecord()
} catch {
    try? telemetry?.logVoiceGateEvent(
        hostNode: hostNode,
        eventType: "playback_refused",
        composite: nil,
        expectedComposite: nil,
        operatorLabel: nil,
        notes: "gate read error in isApproved: \(error.localizedDescription)")
    return false
}
guard let record else { return false }
```

**Note:** `telemetry` is `VoiceGateTelemetryRecording?` (optional). Use `telemetry?.logVoiceGateEvent(...)`. Check the `hostNode` property name — grep for `hostNode` in VoiceApprovalGate.swift to find the stored property name.

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/VoiceApprovalGateTests`. All 10 tests must pass. The test `testMalformedGateFileIsRejected` is especially relevant.

---

## TASK 2: AOxFourProbe Error Differentiation [MEDIUM-002]

**Problem:** `probePerson()` uses `try?` on genesis.json read — file corruption is indistinguishable from "file missing."

**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift` (lines 84-91)

### Fix:

Change lines 84-91:
```swift
guard let data = try? Data(contentsOf: genesisURL) else {
    return result(axis: .person, payload: nil, confidence: 0.0,
                  notes: "genesis.json unavailable at \(genesisURL.path)")
}
guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    return result(axis: .person, payload: nil, confidence: 0.0,
                  notes: "genesis.json is not a JSON object")
}
```

To:
```swift
let data: Data
do {
    data = try Data(contentsOf: genesisURL)
} catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
    return result(axis: .person, payload: nil, confidence: 0.0,
                  notes: "genesis.json not found at \(genesisURL.path)")
} catch {
    return result(axis: .person, payload: nil, confidence: 0.0,
                  notes: "genesis.json read error: \(error.localizedDescription)")
}
guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    return result(axis: .person, payload: nil, confidence: 0.0,
                  notes: "genesis.json is not valid JSON or not a JSON object")
}
```

The JSON parse `try?` on line 88 is acceptable to leave — it already has a specific error message. The critical fix is the file read on line 84, which conflates "missing" with "corrupted/unreadable."

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/AOxFourProbeTests`. All tests must pass.

---

## TASK 3: Hardcoded Passphrase to Keychain [MEDIUM-003]

**Problem:** Line 517 of `MyceliumControlPlane.swift` contains a hardcoded CouchDB decryption passphrase in an embedded Python script.

**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift`

### Step 1: Add a Keychain helper method to MyceliumControlPlane

Add this private method to the class:

```swift
private func getCouchDBPassphrase() throws -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ai.realjarvis.couchdb",
        kSecAttrAccount as String: "vault-decrypt",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data,
          let passphrase = String(data: data, encoding: .utf8) else {
        throw JarvisError.processFailure("CouchDB passphrase not found in Keychain (service: ai.realjarvis.couchdb, account: vault-decrypt). Run: security add-generic-password -s ai.realjarvis.couchdb -a vault-decrypt -w YOUR_PASSPHRASE")
    }
    return passphrase
}
```

**Note:** This requires `import Security`. Check if it's already imported. If not, add it at the top of the file.

### Step 2: Modify the Python script string

Find line 517 (approximately):
```python
passphrase = "*" + "rHGMPtr6oWw7VSa3W3wpa8fT8U"
```

Replace with:
```python
passphrase = os.environ["JARVIS_COUCHDB_PASSPHRASE"]
```

Make sure the Python script string also imports `os` — check if `import os` is already in the embedded script. If not, add it.

### Step 3: Pass the passphrase via Process environment

Find where the Python subprocess is launched (should be near line 517, using `Process()` or similar). Add the passphrase to the process environment:

```swift
let passphrase = try getCouchDBPassphrase()
process.environment = (process.environment ?? ProcessInfo.processInfo.environment).merging(
    ["JARVIS_COUCHDB_PASSPHRASE": passphrase],
    uniquingKeysWith: { _, new in new }
)
```

**IMPORTANT:** Read lines 480-540 of the file to understand the full subprocess context before making changes. The Python code is embedded as a Swift multi-line string.

**Verification:** Build passes. Tests pass. The `sync-control-plane` command will now require the Keychain entry to work, which is expected — better to fail loudly than ship a hardcoded secret.

---

## TASK 4: NaN/Inf Physics Validation [MEDIUM-004]

**Problem:** `StubPhysicsEngine.addBody()` doesn't validate for NaN/Infinity in Vec3 fields.

**File:** `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` (inside `addBody()`, after line 63)

### Fix:

After the existing mass check (line 61-63), add:

```swift
guard body.initialTransform.position.x.isFinite,
      body.initialTransform.position.y.isFinite,
      body.initialTransform.position.z.isFinite else {
    throw PhysicsError.invalidConfiguration("body position contains NaN or Infinity")
}
guard body.shape.extents.x.isFinite && body.shape.extents.x > 0,
      body.shape.extents.y.isFinite && body.shape.extents.y > 0,
      body.shape.extents.z.isFinite && body.shape.extents.z > 0 else {
    throw PhysicsError.invalidConfiguration("body shape extents must be finite and positive")
}
```

**Note:** The error enum is `PhysicsError.invalidConfiguration(String)` — already confirmed to exist.

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/PhysicsEngineTests`. All tests must pass. Existing tests use valid values, so no test changes needed.

---

## TASK 5: Remove Unnecessary @unchecked Sendable [MEDIUM-005]

**Problem:** `TTSRenderParameters` is a struct with all `let` properties — it's already implicitly Sendable.

**File:** `Jarvis/Sources/JarvisCore/Voice/TTSBackend.swift` (line 40)

### Fix:

Change line 40:
```swift
extension TTSRenderParameters: @unchecked Sendable {}
```

To:
```swift
extension TTSRenderParameters: Sendable {}
```

If the compiler complains that a stored property isn't Sendable, investigate which property and fix it (or revert to `@unchecked` with a comment). But all properties should be `let` value types, so this should work.

**Verification:** Build passes.

---

## TASK 6: ARC Telemetry Fallback Logging [MEDIUM-006]

**Problem:** `ARCHarnessBridge.logTelemetry()` silently swallows telemetry write failures.

**File:** `Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift` (lines 137-147)

### Fix:

Add `import os` at the top of the file (line 1, after `import Foundation`).

Add a static logger inside the actor:

```swift
private static let logger = Logger(subsystem: "ai.realjarvis", category: "arc-bridge")
```

Change the `logTelemetry` method:

```swift
private func logTelemetry(event: String) {
    do {
        try telemetry.append(record: [
            "source": "arc_agi_bridge",
            "event": event,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ], to: "arc_agi_events")
    } catch {
        Self.logger.error("ARC telemetry write failed: \(error.localizedDescription, privacy: .public) — event: \(event, privacy: .public)")
    }
}
```

**Note:** `Logger` is from the `os` framework, available on macOS 14+. If `Logger` inside an actor causes any issues, use the function form instead:

```swift
import os
private let arcBridgeLog = os.Logger(subsystem: "ai.realjarvis", category: "arc-bridge")
```

And call `arcBridgeLog.error(...)` in the catch block. A module-level `let` is Sendable and accessible from inside actors.

**Verification:** Build passes. All 74 tests pass.

---

## COMPLETION REPORT

After all 6 tasks, write `/Users/grizzmed/REAL_JARVIS/DEEPSEEK_COMPLETION_REPORT.md`:

```markdown
# DeepSeek 3.2 Completion Report

## Tasks Completed
| Task | Finding ID | File | Change |
|------|-----------|------|--------|
| 1 | MEDIUM-001 | VoiceApprovalGate.swift | [one-line description] |
| 2 | MEDIUM-002 | AOxFourProbe.swift | [one-line description] |
| 3 | MEDIUM-003 | MyceliumControlPlane.swift | [one-line description] |
| 4 | MEDIUM-004 | StubPhysicsEngine.swift | [one-line description] |
| 5 | MEDIUM-005 | TTSBackend.swift | [one-line description] |
| 6 | MEDIUM-006 | ARCHarnessBridge.swift | [one-line description] |

## Final State
- Build: [PASS/FAIL]
- Tests: [count] executed, [failures] failures
- Any issues encountered: [description or "None"]
```

---

## BALLS/STRIKES

| Criterion | BALL | STRIKE |
|-----------|------|--------|
| All 6 tasks completed | All done | Any skipped |
| Build green after each task | Green every time | Any broken builds left |
| Tests >= 74 after each task | Never dropped | Tests broken or removed |
| Read files before editing | Read every target | Modified blind |
| No scope creep | Only changed what's specified | Refactored, added features, added comments |
| Completion report written | Report exists with all fields | Missing or incomplete |

**Minimum: 5/6 BALL.**

---

*Spec written by Claude Opus 4.6. 6 targeted fixes. No chatting. No stopping. Execute.*
