# JARVIS — ROUND 2 REMEDIATION HANDOFF REPORT

**Date:** 2026-04-18  
**Auditor (Harley Round 2):** Qwen3-Coder-Next  
**Cross-Reference & Remediation (Joker v2):** GLM-5.1  
**Prior State:** CX-001 through CX-047 FIXED, build green, 74/74 tests passing  
**Post-Remediation State:** Build green, 74/74 tests passing, 0 regressions  

---

## 1. INCOMING AUDIT SUMMARY

Harley Round 2 delivered 11 findings (R01–R11) targeting the post-CX-047 codebase, specifically looking for regressions from prior fixes and residual attack surface:

| ID | Severity | File | Category | One-line |
|----|----------|------|----------|----------|
| R01 | CRITICAL | VoiceApprovalGate.swift:88,284-286 | TOCTOU | Lock ordering inversion between gateLock and telemetryLock |
| R02 | CRITICAL | VoiceApprovalGate.swift:417,432,475,495 | RESOURCE | Telemetry counter can underflow, breaking backpressure |
| R03 | HIGH | MemoryEngine.swift:306-313 | CRYPTO | SHA256→Int truncation drops 216 bits, collision risk |
| R04 | HIGH | TelemetryStore.swift:36-38 | RESOURCE | .jsonl.1 rotation never cleaned, disk exhaustion |
| R05 | HIGH | PythonRLMBridge.swift:87-101 | INJECTION | DispatchSource timer may kill wrong process |
| R06 | HIGH | JarvisHostTunnelServer.swift:10,88 | CONFIG | Default "terminal" source bypasses authorization |
| R07 | MEDIUM | ArchonHarness.swift:288-298 | INJECTION | validateCommand misses single backtick vector |
| R08 | MEDIUM | AOxFourProbe.swift:262-263 | INTEGRITY | Freshness calculation skips negative clock skew check |
| R09 | MEDIUM | ARCGridAdapter.swift:40-61 | CONFIG | Empty grid wipes existing state before validation |
| R10 | LOW | VoiceApprovalGate.swift:115-125 | TOCTOU | Fingerprint read race on mutable session |
| R11 | LOW | ConvexTelemetrySync.swift:8,107-122 | INTEGRITY | Hardcoded Convex URL in source |

---

## 2. VERIFICATION RESULTS — FINDING-BY-FINDING

Every finding was verified against live source code at the cited line numbers. Result: 6 false positives, 2 inflated, 3 confirmed.

### R01 — CRITICAL → FALSE POSITIVE

**Claim:** Lock ordering inversion between `gateLock` and `telemetryLock` causes deadlock. `syncStateRaw()` acquires `telemetryLock` then calls `loadRecord()` which needs `gateLock`.

**Reality (verified at lines 379-390, 458-497):**  
- `loadRecord()` is a **private helper that does NOT acquire any lock** — it's a plain file read.
- `syncStateRaw()` acquires `telemetryLock` (470-476, 494-496) and calls `telemetry.syncVoiceGateState()`. It **never calls `loadRecord()`**.
- `syncState()` (436-456) calls `Self.digestReferenceAudio()` and `Self.digestString()` **before** calling `syncStateRaw()`. Neither acquires any lock.
- Lock ordering is **always**: `gateLock` → `telemetryLock`, or `telemetryLock` alone. No thread ever acquires them in reverse order.

**Verdict:** No deadlock possible. Both locks are correctly scoped and never nested in reverse order.

---

### R02 — CRITICAL → FALSE POSITIVE

**Claim:** `pendingTelemetryCount` can underflow to -1, breaking backpressure.

**Reality (verified at lines 412-418, 431-433, 470-476, 494-496):**  
- Every `+= 1` (line 417, 475) is inside `telemetryLock.lock()/unlock()`.
- Every `-= 1` (line 432, 495) is inside `telemetryLock.lock()/unlock()`.
- The counter starts at `0` and every increment is paired with exactly one decrement in the same function scope.
- Since both operations are protected by the same lock, concurrent access cannot produce an unpaired decrement.

**Verdict:** Underflow is impossible with correct lock discipline. The counter is always ≥ 0.

---

### R03 — HIGH → LOW (SEVERITY INFLATED)

**Claim:** SHA256→Int truncation drops 216 bits, causing ~280 collisions in 50k node graph.

**Reality (verified at lines 306-313):**  
The function uses the first 64 bits of SHA256 (via `UInt64` → `Int(truncatingIfNeeded:)`). The birthday paradox calculation for 50k items in 2^64 space is:

```
P(collision) ≈ n²/(2·2^64) = 2.5×10⁹/(3.7×10¹⁹) ≈ 1.35×10⁻¹⁰
```

The report's claim of "280 expected collisions" applies the formula for 2^32 space (4 billion items), not 2^64. 64 bits is more than sufficient for local in-memory indexing.

**Verdict:** LOW risk for local use. Still good practice to use full hex for IDs (which we did — see FIX section), but the collision alarm was mathematically incorrect.

---

### R04 — HIGH → LOW (SEVERITY INFLATED)

**Claim:** Rotation creates unbounded `.jsonl.1`, `.jsonl.1.1`, `.jsonl.1.1.1` chain, risking disk exhaustion.

**Reality (verified at lines 36-38):**  
- Line 37: `try? fm.removeItem(at: rotated)` — removes the old `.jsonl.1` **before** moving.
- Line 38: `try? fm.moveItem(at: url, to: rotated)` — moves current file to `.jsonl.1`.
- The result: at most **2 files** exist (`.jsonl` + `.jsonl.1`). The "unbounded chain" claim is false — `deletingPathExtension().appendingPathExtension("jsonl.1")` always produces the same filename pattern.

**Verdict:** LOW — rotation is bounded but could benefit from explicit chain retention (which we added). Not a disk exhaustion vector.

---

### R05 — HIGH → FALSE POSITIVE

**Claim:** `DispatchSource` timer may kill wrong Python process.

**Reality (verified at lines 90-101):**  
- Line 91: `let processRef = process` — captures a reference to **this specific** Process object.
- Line 92-94: The event handler checks `processRef.isRunning` before terminating.
- Line 100: `process.waitUntilExit()` blocks until THIS process exits.
- Line 101: `killTimer.cancel()` fires immediately after exit.
- Each function invocation creates its own timer and process. No timer leaks to the next invocation.

**Verdict:** Impossible for Process A's timer to kill Process B. The timer is scoped, checked, and cancelled.

---

### R06 — HIGH → CONFIRMED ✓

**Claim:** Default source `"terminal"` at line 88 passes authorization at line 205-206, bypassing the auth gate.

**Reality (verified at lines 10, 88, 205-206):**  
```swift
private let authorizedSources = Set(["obsidian-command-bar", "terminal"])  // line 10
clientSources[identifier] = "terminal"  // line 88
```
Any new connection is immediately authorized because `"terminal"` is in `authorizedSources`. This is a regression from CX-038 which added the source-check mechanism but left `"terminal"` as the default. The `.register` handler at line 177-185 does NOT update the source — it just returns a confirmation.

**Verdict:** CONFIRMED HIGH. This is a real auth bypass.

---

### R07 — MEDIUM → FALSE POSITIVE

**Claim:** `validateCommand()` doesn't reject single backtick `` ` ``.

**Reality (verified at line 289):**  
```swift
let forbidden = ["|", ";", "&&", "||", "`", "$(", ">"]
```
The backtick character IS in the array. `command.contains("`")` matches any string containing a backtick, including `` echo `whoami` ``.

**Verdict:** False positive. The backtick is caught.

---

### R08 — MEDIUM → CONFIRMED ✓

**Claim:** Negative `timeIntervalSince` (clock skew backward) inflates freshness to >1.0, clamped to 1.0, giving false confidence of 0.88.

**Reality (verified at line 262):**  
```swift
let freshness = mostRecent != nil ? max(0, 1.0 - now.timeIntervalSince(mostRecent!) / freshnessWindow) : 0.0
```
If NTP sends clock backward by 600s: `age = -600`, `freshness = max(0, 1.0 + 600/300) = max(0, 3.0) = 1.0`, `confidence = 0.55 + 0.33*1.0 = 0.88`. Clock skew produces maximum confidence instead of minimum.

**Verdict:** CONFIRMED MEDIUM. Real bug.

---

### R09 — MEDIUM → FALSE POSITIVE

**Claim:** `loadGrid()` calls `engine.reset()` before `guard grid.rows > 0` check, wiping state on empty grid input.

**Reality (verified at lines 46-50):**  
```swift
guard grid.rows > 0, grid.cols > 0 else {           // line 47 — GUARD FIRST
    throw PhysicsError.invalidConfiguration(...)       // line 48 — throws, exits
}
try engine.reset(world: world)                         // line 50 — reset AFTER guard
```
The guard throws before `engine.reset()`. The report's line references were from a pre-CX-026 version.

**Verdict:** False positive. CX-026 already fixed this correctly.

---

### R10 — LOW → FALSE POSITIVE

**Claim:** `fingerprint()` reads session properties without `gateLock`, creating a TOCTOU window.

**Reality (verified):**  
```swift
public struct VoiceSessionConfiguration: Sendable {  // line 34
    public let selectedVoice: String                  // line 35 — all let
    public let rate: Int                              // line 36
```
It's a `struct` with `let` properties — **immutable by Swift value semantics**. No mutation is possible, so no TOCTOU window exists.

**Verdict:** False positive. Value-type semantics make this safe.

---

### R11 — LOW → CONFIRMED ✓

**Claim:** Hardcoded Convex URL in default parameter.

**Reality (verified at line 17):**  
```swift
convexURLString: String = "https://enduring-starfish-794.convex.cloud/api/mutation"
```
The URL is a default parameter value. It works but can't be changed without source modification.

**Verdict:** CONFIRMED LOW. Configuration hygiene issue.

---

## 3. CROSS-REFERENCE WITH PRIOR CX FIXES

| Finding | Overlaps Prior CX? | Detail |
|---------|---------------------|--------|
| R06 | CX-038 | CX-038 added `authorizedSources` check but set default to `"terminal"` — the fix introduced this bypass. Regression. |
| R08 | CX-031 | CX-031 added freshness scaling but didn't guard against negative `timeIntervalSince`. Same code area, different bug. |
| R03 | CX-037 | CX-037 replaced DJB2 with SHA256 but truncated to `Int`. Improvement over DJB2 but still truncating. |
| R04 | CX-035 | CX-035 added rotation but only kept one backup file. Design intent was correct. |

---

## 4. REMEDIATION — ALL CHANGES

### FIX-R06: Default Source Bypasses Authorization

**File:** `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift`  
**Lines changed:** 88, 177-185

**Change 1** — Default source from `"terminal"` to `"unauthenticated"`:
```swift
// BEFORE:
clientSources[identifier] = "terminal"  // CX-038: default server-assigned source

// AFTER:
clientSources[identifier] = "unauthenticated"  // R06: default unauthenticated — must register to get authorized source
```

**Change 2** — Source upgrade in `.register` handler:
```swift
// BEFORE:
case .register:
    return JarvisTunnelMessage(
        kind: .response,
        response: JarvisTunnelResponse(
            action: .ping,
            spokenText: "Mobile endpoint registered to the Jarvis host tunnel.",
            snapshot: try makeSnapshot()
        )
    )

// AFTER:
case .register:
    // R06: assign source from client registration role
    if let registration = message.registration {
        let identifier = ObjectIdentifier(connection)
        let role = registration.role.lowercased()
        if authorizedSources.contains(role) {
            clientSources[identifier] = role
        }
    }
    return JarvisTunnelMessage(
        kind: .response,
        response: JarvisTunnelResponse(
            action: .ping,
            spokenText: "Mobile endpoint registered to the Jarvis host tunnel.",
            snapshot: try makeSnapshot()
        )
    )
```

**Security model:** `"terminal"` remains in `authorizedSources` for local CLI connections that register with `role: "terminal"`. Mobile connections must register with `role: "obsidian-command-bar"` to be authorized. Unregistered connections default to `"unauthenticated"` which is NOT in `authorizedSources`, causing `ensureAuthorized` to reject them.

---

### FIX-R08: Clock Skew Inflates Freshness

**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift`  
**Lines changed:** 258-267

**Change** — Added clock skew detection and freshness clamping:
```swift
// BEFORE:
let ageSec = Int(now.timeIntervalSince(mostRecent ?? now))
let freshness = mostRecent != nil ? max(0, 1.0 - now.timeIntervalSince(mostRecent!) / freshnessWindow) : 0.0
let confidence = 0.55 + (0.33 * freshness)

// AFTER:
let ageSec = Int(now.timeIntervalSince(mostRecent ?? now))
// R08: detect clock skew — negative age means mtime is in the future
let age = mostRecent != nil ? now.timeIntervalSince(mostRecent!) : 0.0
if age < 0 {
    return result(axis: .event,
                  payload: "clock-skew-detected; age=\(Int(age))s",
                  confidence: 0.10,
                  notes: "Negative event age (\(String(format: "%.1f", age))s) indicates clock skew — confidence degraded")
}
let freshness = max(0, min(1.0, 1.0 - age / freshnessWindow))
let confidence = 0.55 + (0.33 * freshness)
```

**Effect:** When NTP sends clock backward, `age < 0` → confidence degrades to 0.10 instead of inflating to 0.88. Added `min(1.0, ...)` clamp as additional defense.

---

### FIX-R03: SHA256 Truncation → Full Hex String for IDs

**File:** `Jarvis/Sources/JarvisCore/Memory/MemoryEngine.swift`  
**Lines changed:** 111, 137, 306-313

**Change 1** — Added `stableHashHex()` method:
```swift
// NEW METHOD:
private func stableHashHex(_ text: String) -> String {
    let digest = CryptoKit.SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

**Change 2** — Document ID uses full hex:
```swift
// BEFORE:
let documentID = "doc-\(stableHash(content + fileURL.lastPathComponent))"

// AFTER:
let documentID = "doc-\(stableHashHex(content + fileURL.lastPathComponent))"
```

**Change 3** — Entity ID uses full hex:
```swift
// BEFORE:
let entityID = "entity-\(stableHash(entity))"

// AFTER:
let entityID = "entity-\(stableHashHex(entity))"
```

**Preserved:** `stableHash()` returning `Int` is kept for vector bucket indexing at line 285 (`abs(stableHash(...)) % vector.count`) where 64-bit fold is sufficient.

---

### FIX-R04: Telemetry Rotation Chain Retention

**File:** `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift`  
**Lines changed:** 30-39

**Change** — Implemented multi-file rotation with bounded retention:
```swift
// BEFORE:
let fm = FileManager.default
if fm.fileExists(atPath: url.path),
   let attrs = try? fm.attributesOfItem(atPath: url.path),
   let fileSize = attrs[.size] as? Int,
   fileSize > maxFileSizeBytes {
    let rotated = url.deletingPathExtension().appendingPathExtension("jsonl.1")
    try? fm.removeItem(at: rotated)
    try? fm.moveItem(at: url, to: rotated)
}

// AFTER:
let maxRotations = 2
let fm = FileManager.default
if fm.fileExists(atPath: url.path),
   let attrs = try? fm.attributesOfItem(atPath: url.path),
   let fileSize = attrs[.size] as? Int,
   fileSize > maxFileSizeBytes {
    for i in stride(from: maxRotations, through: 1, by: -1) {
        let rotatedN = url.deletingPathExtension().appendingPathExtension("jsonl.\(i)")
        try? fm.removeItem(at: rotatedN)
        if i > 1 {
            let rotatedPrev = url.deletingPathExtension().appendingPathExtension("jsonl.\(i - 1)")
            try? fm.moveItem(at: rotatedPrev, to: rotatedN)
        }
    }
    let rotated1 = url.deletingPathExtension().appendingPathExtension("jsonl.1")
    try? fm.removeItem(at: rotated1)
    try? fm.moveItem(at: url, to: rotated1)
}
```

**Effect:** Rotation now keeps `.jsonl` (current), `.jsonl.1` (previous), `.jsonl.2` (oldest). Max disk usage: 3 × `maxFileSizeBytes` = 30MB. Oldest file is deleted before shifting.

---

### FIX-R11: Convex URL Environment Variable Override

**File:** `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift`  
**Lines changed:** 15-25

**Change** — Externalized URL via optional parameter + env var fallback:
```swift
// BEFORE:
public init(paths: WorkspacePaths,
            hostNode: String = ProcessInfo.processInfo.hostName,
            convexURLString: String = "https://enduring-starfish-794.convex.cloud/api/mutation",
            authToken: String? = nil) throws {
    self.paths = paths
    self.hostNode = hostNode
    guard let url = URL(string: convexURLString) else {
        throw JarvisError.processFailure("Invalid Convex URL: \(convexURLString)")
    }
    self.convexURL = url
    self.authToken = authToken
}

// AFTER:
public init(paths: WorkspacePaths,
            hostNode: String = ProcessInfo.processInfo.hostName,
            convexURLString: String? = nil,
            authToken: String? = nil) throws {
    self.paths = paths
    self.hostNode = hostNode
    // R11: allow environment variable override for Convex URL
    let resolvedURLString = convexURLString
        ?? ProcessInfo.processInfo.environment["CONVEX_URL"]
        ?? "https://enduring-starfish-794.convex.cloud/api/mutation"
    guard let url = URL(string: resolvedURLString) else {
        throw JarvisError.processFailure("Invalid Convex URL: \(resolvedURLString)")
    }
    self.convexURL = url
    self.authToken = authToken
}
```

**Fallback chain:** explicit parameter → `CONVEX_URL` env var → hardcoded default. Fully backward compatible.

---

## 5. BUILD AND TEST VERIFICATION

| Check | Command | Result |
|-------|---------|--------|
| Build | `xcodebuild -workspace jarvis.xcworkspace -scheme JarvisCore build` | **SUCCEEDED** |
| Test | `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis test` | **74/74 passing, 0 failures** |

Each fix was verified individually with build+test between patches. No test regressions.

---

## 6. FALSE POSITIVE ANALYSIS — DETAILED

| ID | Harley Claim | Why False Positive | Evidence |
|----|-------------|-------------------|----------|
| R01 | Lock ordering inversion causes deadlock | `loadRecord()` at line 379 is a lock-free private helper. `syncStateRaw()` never acquires `gateLock`. Lock order is always `gateLock→telemetryLock` or `telemetryLock` alone. | Read lines 379-390, 458-497 live |
| R02 | Counter underflow breaks backpressure | Every `+=1` (417, 475) is paired with `-=1` (432, 495), all inside `telemetryLock`. Counter starts at 0, always returns to 0 after call. | Read lines 412-418, 431-433, 470-476, 494-496 live |
| R05 | Timer kills wrong process | Each `runPythonCommand` call creates its own `DispatchSource` timer + `Process`. Timer cancelled at line 101 after `waitUntilExit()`. No shared state. | Read lines 90-101 live |
| R07 | Backtick not rejected by validateCommand | Backtick `` ` `` is explicitly in the `forbidden` array at line 289. `contains("`")` matches any backtick occurrence. | Read line 289 live |
| R09 | Empty grid wipes state before validation | Guard at line 47 (`grid.rows > 0, grid.cols > 0`) throws BEFORE `engine.reset()` at line 50. CX-026 already fixed this. | Read lines 46-50 live |
| R10 | Fingerprint race on mutable session | `VoiceSessionConfiguration` is `public struct: Sendable` with all `let` properties (line 34-36). Immutable by Swift value semantics. | Read line 34 live |

**Harley's strike rate:** 3 confirmed / 11 total = 27%. The 2 CRITICALs were both false positives. The most consequential finding (R06) was HIGH, not CRITICAL.

---

## 7. FILES MODIFIED

| File | Changes |
|------|---------|
| `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | R06: default source → `"unauthenticated"`, register handler assigns authorized source |
| `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift` | R08: clock skew detection, freshness clamping |
| `Jarvis/Sources/JarvisCore/Memory/MemoryEngine.swift` | R03: added `stableHashHex()`, document/entity IDs use full SHA256 hex |
| `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | R04: bounded rotation chain (.jsonl, .jsonl.1, .jsonl.2) |
| `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | R11: env var override for Convex URL |

---

## 8. OUTSTANDING ITEMS — NONE ACTIONABLE

All confirmed findings are fixed. The 6 false positives require no action. No further regressions detected.

---

*Joker v2 (GLM-5.1) — Round 2 cross-reference and remediation complete. Send Harley back whenever you want.*