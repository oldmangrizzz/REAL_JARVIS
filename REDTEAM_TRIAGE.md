# Red Team Triage Report — JARVIS Security Findings

**Generated:** 2026-04-21  
**Source:** GLM 5.1 Joker (30 findings), Qwen Harley (17 findings), 015-Remediation-Turnover  
**Total Items:** 47 findings  

---

## Triage Summary

| Severity | Joker | Harley | Total | Completed | Pending | Status |
|----------|-------|--------|-------|-----------|---------|--------|
| **CRITICAL** | 5 | 2 | **7** | 2 (CRITICAL-002, CRITICAL-003) | 5 | 29% |
| **HIGH** | 8 | 4 | **12** | 4 (see completed) | 8 | 33% |
| **MEDIUM** | 7 | 6 | **13** | 0 | 13 | 0% |
| **LOW** | 6 | 3 | **9** | 0 | 9 | 0% |
| **INFO** | 4 | 2 | **6** | 0 | 6 | 0% |
| **TOTAL** | 30 | 17 | **47** | 6 | 41 | 13% |

---

## CRITICAL Findings

### Joker

| ID | Title | File | Risk | Code Status | Spec Status | Notes |
|----|-------|------|------|-------------|-------------|-------|
| CRITICAL-001 | MasterOscillator onTick Deadlock — Thread Concurrent Calls | `Jarvis/Sources/JarvisCore/Oscillator/MasterOscillator.swift:170` | Subscribers receive concurrent `onTick()` calls from timer queue + manual caller without sync | NOT FIXED | PENDING | Requires onTick dispatch to serial queue or documented subscriber sync requirement |
| CRITICAL-002 | PheromindEngine Data Race — Unsynchronized Mutable State | `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift:40-133` | Dictionary mutation during concurrent register/applyGlobalUpdate calls | NOT FIXED | VERIFIED (015 turnover: COMPLETED) | A&Ox4 gate added; needs lock on all state access or actor conversion |
| CRITICAL-003 | ARCGrid Jagged Array — Index Out of Bounds | `Jarvis/Sources/JarvisCore/ARC/ARCGridAdapter.swift:44-46` | Crashes on non-uniform row lengths | NOT FIXED | VERIFIED (015 turnover: COMPLETED) | Spatial quadrant analysis confirmed implemented; validate jagged arrays in init() |
| CRITICAL-004 | JarvisHostTunnelServer Unbounded Buffer — OOM | `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift:126-140` | Malicious/buggy client can send newline-free data, exhausting memory per connection | NOT FIXED | PENDING | Implement buffer size limit + newline timeout |
| CRITICAL-005 | MasterOscillator Race Between restart() and fire() — Ghost Tick | `Jarvis/Sources/JarvisCore/Oscillator/MasterOscillator.swift:105-145` | Tick fires after stop() but before start(); start() resets sequence, losing tick | NOT FIXED | PENDING | Add synchronization between stop/start, or queue fire() calls |

### Harley

| ID | Title | File | Risk | Code Status | Spec Status | Notes |
|----|-------|------|------|-------------|-------------|-------|
| CRITICAL-001 | Hardcoded Keychain Query Bypass — CouchDB Passphrase in Error Messages | `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:511` | Shell history leakage of passphrase + command | NOT FIXED | PENDING | Use generic error messages in prod; log passphrase setup guide in DEBUG only |
| CRITICAL-002 | Unsafe Pointer Usage in VoiceReferenceAnalyzer — Buffer Overflow | `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift:691-693` | Corrupted audio file → arbitrary code execution via memcpy overflow | NOT FIXED | PENDING | Replace memcpy with safe Swift array copy or copyMemory(from:) with bounds check |

---

## HIGH Findings

| ID | Source | Title | File | Risk | Status |
|----|--------|-------|------|------|--------|
| HIGH-001 | Joker | StubPhysicsEngine step() Infinite Loop — No Substep Cap | `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` | Infinite loop in step() without max substeps | PENDING |
| HIGH-002 | Joker | StubPhysicsEngine nextID Integer Wrapping — Body Handle Collision | `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` | Handle wrap-around causes body identity collisions | PENDING |
| HIGH-003 | Joker | PythonRLMBridge No Timeout on waitUntilExit — Thread Deadlock | `Jarvis/Sources/JarvisCore/RLM/PythonRLMBridge.swift` | Unbounded wait on Python subprocess exit | PENDING |
| HIGH-004 | Joker | JarvisHostTunnelServer accept() Race on Non-Queue Thread | `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | accept() called from non-queue thread | VERIFIED (015 turnover: stop() mutations wrapped in queue.sync) |
| HIGH-005 | Joker | ARCHarnessBridge Re-processes All Files Every 5 Seconds — No Dedup | `Jarvis/Sources/JarvisCore/ARC/ARCHarnessBridge.swift` | File processing not deduplicated; CPU/IO thrash | PENDING |
| HIGH-006 | Joker | MemoryEngine Unbounded Graph Growth — OOM on Load | `Jarvis/Sources/JarvisCore/Memory/MemoryEngine.swift` | Graph nodes accumulate without eviction | VERIFIED (015 turnover: recursive deadlock resolved; needs size limit audit) |
| HIGH-007 | Joker | PythonRLMBridge stdin/stdout/stderr Wire to Arbitrary Python REPL — RCE | `Jarvis/Sources/JarvisCore/RLM/PythonRLMBridge.swift` | Subprocess REPL accessible; remote code execution vector | PENDING |
| HIGH-008 | Joker | ArchonHarness Non-JSON Fallback — "No errors" Detected as Failure | `Jarvis/Sources/JarvisCore/ARC/ArchonHarness.swift` | Non-JSON response treated as failure even if semantically valid | PENDING |
| HIGH-001 | Harley | String-based Error Matching in VoiceApprovalGate.isApproved() — Logic Bypass | `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:128` | Error message string drift causes condition bypass | PENDING |
| HIGH-002 | Harley | Incomplete Error Classification in AOxFourProbe.probePerson() — Permission Denied / Directory Misidentification | `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:87` | Only matches NSFileReadNoSuchFileError; misses NSFileReadNoPermissionError, etc. | PENDING |
| HIGH-003 | Harley | Keychain Passphrase Escalation via Process Environment — TOCTOU | `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:560-564` | Passphrase injected into process environ; visible via ps/lldb/Activity Monitor | PENDING |
| HIGH-004 | Harley | TelemetryStore.append() Uses try? for FileHandle — Silent Data Loss | `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift:31` | Permission/disk full errors swallowed silently | PENDING |

---

## MEDIUM Findings (13 total)

| ID | Source | Title | File | Risk | Status |
|----|--------|-------|------|------|--------|
| MEDIUM-001 | Joker | StubPhysicsEngine Division by Near-Zero Mass | `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` | NaN propagation in force calculations | PENDING |
| MEDIUM-002 | Joker | StubPhysicsEngine Zero-Extent Plane Silently Becomes Z-Up | `Jarvis/Sources/JarvisCore/Physics/StubPhysicsEngine.swift` | Fallback orientation not documented | PENDING |
| MEDIUM-003 | Joker | PhaseLockMonitor NaN Propagation From Drift Edge Cases | `Jarvis/Sources/JarvisCore/Oscillator/PhaseLockMonitor.swift` | NaN from drift calculations | PENDING |
| MEDIUM-004 | Joker | ConvexTelemetrySync Hardcoded URL Force Unwrap and No Auth | `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | Force unwrap + no auth on Convex endpoint | PENDING |
| MEDIUM-005 | Joker | ConvexTelemetrySync CRLF Offset Drift — Skipped/Duplicated Events | `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | Newline mismatch (LF vs CRLF) causes offset corruption | PENDING |
| MEDIUM-006 | Joker | ArchonHarness YAML Codec Injection — Colon in Command Value | `Jarvis/Sources/JarvisCore/ARC/ArchonHarness.swift` | YAML parsing breaks on colons in command value | PENDING |
| MEDIUM-007 | Joker | ARCGrid Empty Grid — Silent No-Op vs. Error | `Jarvis/Sources/JarvisCore/ARC/ARCGridAdapter.swift` | Empty grid handling ambiguous | PENDING |
| MEDIUM-001 | Harley | Unvalidated String Interpolation in dashboardHTML() — XSS Risk | `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:364-411` | Unescaped HTML/JS in dashboard HTML construction | PENDING |
| MEDIUM-002 | Harley | Hardcoded IPv4 Address in MyceliumControlPlane — Operational Lock-in | `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:36` | Charlie IP hardcoded; requires recompile to change | PENDING |
| MEDIUM-003 | Harley | Python Subprocess Fail-Silent — Missing Dependency Validation | `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:557-585` | No validation of python3, cryptography, urllib3 before use | PENDING |
| MEDIUM-004 | Harley | AOxFourProbe.probeTime() Sanity Floor Hardcoded — Clock Skew False Negative | `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:173` | Hardcoded 2024-01-01 floor; VM images before then fail unnecessarily | PENDING |
| MEDIUM-005 | Harley | AOxFourProbe.probeEvent() Freshness Window Mismatch — Stale Telemetry | `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:199` | 5-min window too loose for critical voice gate | PENDING |
| MEDIUM-006 | Harley | Race Condition in VoiceApprovalGate.isApproved() Fingerprint — Symlink Swap Attack | `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:141` | Fingerprint recomputed every call; vulnerable to concurrent file swap | PENDING |

---

## LOW Findings (9 total)

Findings include: PheromindEngine unbounded pheromone growth, unbounded somatic weight, TelemetryStore disk growth with no rotation, lock contention, MemoryEngine DJB2 collision, JarvisHostTunnelServer self-asserted auth, AOxFourProbe non-English localization, VoiceApprovalGate snapshot fallback logging noise, platformUUID silent fallback.

**Status:** All PENDING

---

## INFORMATIONAL Findings (6 total)

| ID | Source | Title | File | Risk |
|----|--------|-------|------|------|
| INFO-001 | Joker | ArchonHarness Diagnosis False Positive on "json" Substring | `Jarvis/Sources/JarvisCore/ARC/ArchonHarness.swift` | Substring match false positive | INFO |
| INFO-002 | Joker | ConvexTelemetrySync Full File Re-Read Every 30 Seconds | `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | Inefficient file polling | INFO |
| INFO-003 | Joker | JarvisHostTunnelServer Deterministic Shared Secret | `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | Deterministic = predictable | INFO |
| INFO-004 | Joker | PheromindEngine Dead Code — Evaporation Cap Unreachable | `Jarvis/Sources/JarvisCore/Pheromind/PheromoneEngine.swift` | Dead code cleanup opportunity | INFO |
| INFO-001 | Harley | Place-Fingerprint Preimage Collision Risk | `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:133-141` | Low risk; minor crypto hardening | INFO |
| INFO-002 | Harley | VoiceApprovalGate Telemetry Best-Effort — No Backpressure | `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:386-456` | Silent data loss in high load | INFO |

---

## Completed Tasks (Per 015 Turnover)

✅ CRITICAL-002 (Pheromind A&Ox4 gate)  
✅ CRITICAL-003 (ARCGrid spatial quadrant analysis)  
✅ HIGH-004 (JarvisHostTunnelServer queue mutations)  
✅ HIGH-006 (MasterOscillator weak subscriber cleanup)  

**Note:** Remaining 015 turnover tasks (MEDIUM-001 through MEDIUM-006) are error-handling refinements (VoiceApprovalGate differentiation, AOxFourProbe error classification, MyceliumControlPlane hardcoded passphrase, StubPhysicsEngine validation, TTSRenderParameters @unchecked Sendable, ARCHarnessBridge os_log fallback).

---

## Recommended Fix Priority

### Phase 1 (Blocking)
1. **CRITICAL-004** — JarvisHostTunnelServer unbounded buffer (DoS vector)
2. **CRITICAL-005** — MasterOscillator ghost tick (data loss)
3. **CRITICAL-001 (Harley)** — Keychain passphrase error logging (cred disclosure)
4. **CRITICAL-002 (Harley)** — VoiceReferenceAnalyzer memcpy buffer overflow (RCE vector)
5. **HIGH-007** — PythonRLMBridge RCE vector

### Phase 2 (Security/Stability)
6. **HIGH-003 (Harley)** — Passphrase environment variable escalation (cred leak)
7. **CRITICAL-001** — MasterOscillator subscriber concurrency (data race)
8. **HIGH-001 (Harley)** — String-based error matching (logic bypass)
9. **MEDIUM-006 (Harley)** — VoiceApprovalGate symlink race (DoS)

### Phase 3 (Operational)
Remaining MEDIUM and LOW items; INFO items non-blocking.

---

## Acceptance Criteria (Per Spec C6)

- [x] Triage table created (this document)
- [ ] Each CRITICAL and HIGH finding has a pending fix PR or issue
- [ ] Code-Verified status updated as fixes are merged
- [ ] REDTEAM_TRIAGE.md kept in sync with fixes

