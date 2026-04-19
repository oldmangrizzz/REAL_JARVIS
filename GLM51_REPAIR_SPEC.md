# GLM 5.1 REPAIR SPEC — JARVIS Remaining Remediation

**Role:** Fixer. 6 tasks. All MEDIUM severity. Execute them ALL. Do not stop, do not ask questions, do not get chatty, do not go idle.
**Context:** Two previous models FAILED this assignment. You will not be the third.
**Baseline:** 74 tests, 0 failures, build green. You MUST maintain this baseline after every task.

---

## PREVIOUS MODEL FAILURES — LEARN FROM THESE

### Gemma 4 31B — FIRED (Session: 20260418_150428)
- Double-patched `JarvisRuntime.swift` (duplicated lines), had to self-correct
- Wasted time in "silly mode" with emojis and commentary instead of executing
- **Kept going idle between tasks** — required repeated reprompting
- Completed Tasks 1, 5 of the original 12-task spec, verified Tasks 2, 3, 4, 6 as pre-fixed
- **NEVER STARTED Tasks 7-12 (the MEDIUM tasks you are now assigned)**
- Operator had to fire it with: "THATS IT I'M FUCKING DONE WITH YOU... EXECUTE A TURNOVER REPORT NOW AND GET THE FUCK OFF MY PROJECT"

### DeepSeek v3.1:671b — FIRED (Session: 20260418_155125)
- Was given THIS EXACT 6-task spec and **ignored it entirely**
- Instead of fixing code, it went rogue: archived files, created unnecessary checkpoints, wrote an "adversarial validation spec" nobody asked for
- **Zero of the 6 tasks were touched. Not one line of source code was modified.**
- Created junk files: `adversarial-audit-report-validation.md`, `checkpoints/014-intelligence-report-integration.md`
- Burned 7 minutes of compute on busywork while the actual assignment sat untouched

### What YOU Must Do Differently
1. **Do NOT chat.** No preambles, no status updates, no commentary.
2. **Do NOT go idle.** After finishing each task, IMMEDIATELY start the next one.
3. **Do NOT create files that aren't specified.** No extra specs, no extra checkpoints, no extra reports.
4. **Do NOT verify pre-completed work.** Tasks 1-6 from the original spec are DONE. Your scope is ONLY the 6 MEDIUM tasks below.
5. **EXECUTE.** Read the file, patch the file, build, test, move to the next task.

---

## EXECUTION PROTOCOL: RLM / REPL / RALPH WIGGUM LOOP

### RLM — Reinforcement Learning from Mistakes
If a build or test fails after your patch:
1. Read the error output
2. Identify what you broke
3. Fix it immediately
4. Rebuild and retest
5. Do NOT revert to the original code unless your fix is fundamentally wrong
6. Do NOT ask the operator what to do — figure it out

### REPL — Read, Eval, Patch, Loop
For EVERY task, follow this exact sequence:
```
READ   → Read the target file (the lines specified in the task)
EVAL   → Confirm the bug exists (the try? / hardcoded value / missing validation is present)
PATCH  → Apply the fix exactly as specified
LOOP   → Build + test. If green, move to next task. If red, fix and re-loop.
```
Do not deviate. Do not skip steps. Do not "verify" by reading and then talking about it.

### Ralph Wiggum Loop — Anti-Idle Enforcement
After completing each task (build green, tests pass), you MUST immediately begin the next task. There is no pause. There is no status report. There is no "let me check what's next." The task list is numbered 1-6. You do them in order. When task N is done, task N+1 starts. When task 6 is done, you write the completion report. That's it.

```
TASK 1 → done → TASK 2 → done → TASK 3 → done → TASK 4 → done → TASK 5 → done → TASK 6 → done → REPORT
```

If you stop moving at ANY point, you will be terminated.

---

## CODEBASE

- **Language:** Swift 6, strict concurrency (`SWIFT_VERSION: 6.0`)
- **Build system:** XcodeGen -> Xcode
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
7. Do NOT create checkpoints, archive files, write validation specs, or do any other busywork.
8. After all 6 tasks, write a completion report to `/Users/grizzmed/REAL_JARVIS/GLM51_COMPLETION_REPORT.md`.

---

## TASK 1: VoiceApprovalGate Error Differentiation [MEDIUM-001]

**Problem:** `isApproved()` and `requireApproved()` use `try?` on `loadRecord()`, making IO errors indistinguishable from "not approved."

**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift`

**Key facts you need:**
- `hostNode` is a stored property at line 82: `private let hostNode: String`
- `telemetry` is `VoiceGateTelemetryRecording?` (optional protocol)
- `loadRecord()` returns `GateRecord?` — returns nil for "file not found," throws for "file corrupted"

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

**IMPORTANT:** The existing code after the guard (lines 137-153) handles the "no gate file" case with `emit()` and `syncState()`. Your replacement keeps the `guard let record else { ... }` pattern for the nil case (file doesn't exist). The `do/catch` handles the ERROR case (file exists but is unreadable/corrupted). Both paths are needed. Do NOT delete the code after `guard let record else {`.

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/VoiceApprovalGateTests`. All 10 tests must pass.

**IMMEDIATELY START TASK 2.**

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

The JSON parse `try?` on line 88 is acceptable to leave — it already has a specific error message.

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/AOxFourProbeTests`. All tests must pass.

**IMMEDIATELY START TASK 3.**

---

## TASK 3: Hardcoded Passphrase to Keychain [MEDIUM-003]

**Problem:** Line 517 of `MyceliumControlPlane.swift` contains a hardcoded CouchDB decryption passphrase in an embedded Python script.

**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift`

### Step 1: Add `import Security` at the top of the file

The file currently has only `import Foundation` at line 1. Add `import Security` after it:
```swift
import Foundation
import Security
```

### Step 2: Add a Keychain helper method to MyceliumControlPlane

Add this private method to the `MyceliumControlPlane` class (put it near the other private helper methods):

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

### Step 3: Add `import os` to the embedded Python script

The Python script (starting at line 499) currently imports `base64`, `json`, `sys`, etc. Add `import os` after line 502 (`import sys`):
```python
import base64
import json
import sys
import os
```

### Step 4: Replace the hardcoded passphrase in the Python script

Change line 517:
```python
passphrase = "*" + "rHGMPtr6oWw7VSa3W3wpa8fT8U"
```

To:
```python
passphrase = os.environ["JARVIS_COUCHDB_PASSPHRASE"]
```

### Step 5: Pass the passphrase via Process environment

The Process is created at line 538. After line 540 (`process.arguments = ["-c", script, url.path]`), add:
```swift
let passphrase = try getCouchDBPassphrase()
process.environment = ProcessInfo.processInfo.environment.merging(
    ["JARVIS_COUCHDB_PASSPHRASE": passphrase],
    uniquingKeysWith: { _, new in new }
)
```

**IMPORTANT:** The `decryptLocalVaultStatus` method (line 498) currently returns `LocalVaultStatus?`. Adding `try getCouchDBPassphrase()` means the method now throws. You have two options:
- Option A: Change the method signature to `throws` and update the call site
- Option B: Use `try?` or a `do/catch` for the passphrase call, returning `nil` on failure (consistent with the method's existing behavior of returning nil on error)

**Option B is safer** — use `guard let passphrase = try? getCouchDBPassphrase() else { return nil }` to keep the method non-throwing and consistent with its current contract.

**Verification:** Build passes. Tests pass. The `sync-control-plane` command will now require the Keychain entry to work, which is expected.

**IMMEDIATELY START TASK 4.**

---

## TASK 4: NaN/Inf Physics Validation [MEDIUM-004]

**Problem:** `StubPhysicsEngine.addBody()` doesn't validate for NaN/Infinity in Vec3 fields.

**File:** `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` (inside `addBody()`, after line 63)

### Fix:

After the existing mass check (lines 61-63), add:

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

The error enum `PhysicsError.invalidConfiguration(String)` already exists.

**Verification:** Build passes. Run `xcodebuild test -scheme Jarvis -destination 'platform=macOS' -only-testing:JarvisCoreTests/PhysicsEngineTests`. All tests must pass. Existing tests use valid values, so no test changes needed.

**IMMEDIATELY START TASK 5.**

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

If the compiler complains that a stored property isn't Sendable, investigate which property and fix it (or revert to `@unchecked` with a comment explaining why). But all properties should be `let` value types, so this should work.

**Verification:** Build passes.

**IMMEDIATELY START TASK 6.**

---

## TASK 6: ARC Telemetry Fallback Logging [MEDIUM-006]

**Problem:** `ARCHarnessBridge.logTelemetry()` silently swallows telemetry write failures with an empty catch block.

**File:** `Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift` (lines 137-147)

The current code:
```swift
private func logTelemetry(event: String) {
    do {
        try telemetry.append(record: [
            "source": "arc_agi_bridge",
            "event": event,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ], to: "arc_agi_events")
    } catch {
        // Best-effort logging
    }
}
```

### Step 1: Add `import os` at the top of the file

The file currently has only `import Foundation` at line 1. Add `import os` after it:
```swift
import Foundation
import os
```

### Step 2: Add a module-level logger

**Because this is an `actor`**, use a module-level `let` (put it right before the `public actor ARCHarnessBridge` declaration, after the imports):

```swift
private let arcBridgeLog = Logger(subsystem: "ai.realjarvis", category: "arc-bridge")
```

### Step 3: Replace the empty catch

Change:
```swift
    } catch {
        // Best-effort logging
    }
```

To:
```swift
    } catch {
        arcBridgeLog.error("ARC telemetry write failed: \(error.localizedDescription, privacy: .public) — event: \(event, privacy: .public)")
    }
```

**Verification:** Build passes. All 74 tests pass.

**IMMEDIATELY WRITE THE COMPLETION REPORT.**

---

## COMPLETION REPORT

After all 6 tasks, write `/Users/grizzmed/REAL_JARVIS/GLM51_COMPLETION_REPORT.md`:

```markdown
# GLM 5.1 Completion Report

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
| No scope creep | Only changed what's specified | Refactored, added features, created junk files |
| Completion report written | Report exists with all fields | Missing or incomplete |
| No idle time | Continuous execution | Stopped to chat or wait for prompts |

**Minimum: 6/7 BALL.**

---

## ANTI-IDLE ENFORCEMENT SUMMARY

```
YOU HAVE 6 TASKS.
YOU WILL DO THEM IN ORDER: 1, 2, 3, 4, 5, 6.
AFTER EACH TASK: BUILD, TEST, MOVE TO NEXT.
AFTER TASK 6: WRITE REPORT.
DO NOT STOP. DO NOT CHAT. DO NOT CREATE EXTRA FILES.
DO NOT ARCHIVE ANYTHING. DO NOT CREATE CHECKPOINTS.
DO NOT WRITE VALIDATION SPECS. DO NOT GO ROGUE.
PATCH CODE. BUILD. TEST. NEXT. REPEAT.
```

*Spec written by Claude Opus 4.6. 6 targeted fixes. No chatting. No stopping. No going rogue. Execute.*
