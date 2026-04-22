# Harley Quinn Red Team Findings — Qwen

## Summary
- **CRITICAL:** 2
- **HIGH:** 4
- **MEDIUM:** 6
- **LOW:** 3
- **INFORMATIONAL:** 2
- **Total:** 17

---

### CRITICAL-001: Hardcoded Keychain Query Bypass — CouchDB Passphrase Disclosure in Error Messages
**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:511`
**Category:** Information Disclosure — Security Gate Subversion
**Description:** The `getCouchDBPassphrase()` function catches Keychain lookup failures and rethrows a `JarvisError.processFailure` that *contains the exact shell command* the user must run to resolve the issue (`security add-generic-password -s ai.realjarvis.couchdb -a vault-decrypt -w YOUR_PASSPHRASE`). This command includes the service, account, and *implicit instruction to write the passphrase in plaintext on the command line*, which may be logged in shell history, Spotlight metadata, or process environment inspection tools (`ps -E`, `lsof`, etc.).
**Impact:** An attacker with filesystem access (or access to system logs, shell histories, or container images) can reconstruct not only the credential target but the exact sequence to write a new one. In combination with TOCTOU in `decryptLocalVaultStatus()` (see V2-002), this enables credential replacement.
**Suggested Fix:** Log a *generic* error message for production (`"Keychain lookup failed"`) and defer the shell command injection to a debug-only error path (`#if DEBUG`). Even better: provide the user with an in-app guidance UI (e.g., a "Setup Assistant" sheet) rather than echoing a raw CLI suggestion.
**Confidence:** CONFIRMED

---

### HIGH-001: String-based Error Matching in `VoiceApprovalGate.isApproved()` — Logic Bypass via Error Message Drift
**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:128`
**Category:** Trust Boundary Violation — Conditional Logic
**Description:** The `isApproved()` catch clause at line 128 matches on `error.localizedDescription` *string content* (`where reason == "gate file missing"`). If `loadRecord()` changes its error message formatting (e.g., adds a period, capitalizes, or adds context), the string comparison fails and the error falls through to the generic `catch` which returns `false`. The issue is twofold: (1) `loadRecord()` throws `VoiceApprovalError.malformedGateFile(reason: String(describing: error))` — any unrelated error inside JSON decoding (e.g., missing key, type mismatch) is swallowed into this generic bucket, and (2) the caller (`isApproved()`) treats *all* non-"gate file missing" errors as fatal gate read errors and returns `false` instead of propagating the error or logging for triage.
**Impact:** An operator could be blocked from voice playback by an unrelated JSON decoding error (e.g., a future schema change in `VoiceApprovalRecord`) and the system would silently deny access without logging why — or worse, log it as a generic "read error" that lacks the specific error reason needed for debugging.
**Suggested Fix:** Add explicit error cases for `malformedGateFile(reason: .missingFile)` and `malformedGateFile(reason: .decodingError(let underlying))` and handle each path explicitly. `isApproved()` should rethrow decoding errors or at least log the underlying error code, not hide it.
**Confidence:** CONFIRMED

---

### HIGH-002: Incomplete Error Classification in `AOxFourProbe.probePerson()` — Permission Denied / Directory Misidentification
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:87`
**Category:** Missing Validation — Error Classification
**Description:** The `probePerson()` function matches `NSFileReadNoSuchFileError` at line 87 but ignores other common read errors (e.g., `NSFileReadNoPermissionError`, `NSFileReadInapplicableStringEncodingError`, `NSFileReadIsDirectoryError`). Any of these will fall through to the generic `catch` at line 90 and return `"genesis.json read error: …"` — which is classified as a generic read error without distinguishing whether it's a misconfiguration, a permissions issue, or a symlink to a directory.
**Impact:** Operators may see misleading telemetry ("read error") when the real issue is permission misconfiguration, delaying incident response. An attacker could intentionally create a race condition where `genesis.json` is swapped with a directory *after* the `fileExists` check but *before* `Data(contentsOf:)`, resulting in an ambiguous error that may be misclassified as "not found" in audit logs.
**Suggested Fix:** Add explicit checks for all `NSFileReadError` subcodes and classify each with a precise payload (e.g., `"genesis.json: permission denied"`, `"genesis.json: expected file but found directory"`).
**Confidence:** CONFIRMED

---

### HIGH-003: Keychain Passphrase Escalation via Process Environment — TOCTOU in MyceliumControlPlane
**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:560-564`
**Category:** Information Exposure — Process Environment Leakage
**Description:** The `decryptLocalVaultStatus()` function retrieves the CouchDB passphrase from Keychain (line 511), then injects it into the Python subprocess environment via `process.environment = ProcessInfo.processInfo.environment.merging(["JARVIS_COUCHDB_PASSPHRASE": passphrase], uniquingKeysWith: { _, new in new })` (lines 561-564). On macOS, process environment variables are visible to any process with the same UID via `ps -E`, `env`, or `/proc/*/environ`-style mechanisms (even though macOS doesn’t have `/proc`, tools like `lldb`, `gdb`, or `Activity Monitor` can leak this data). There is a *window* between Keychain retrieval and subprocess termination where the passphrase lives in memory that is readable by local processes.
**Impact:** A local attacker with a compromised operator account (or an app with privileged access) can extract the CouchDB passphrase from the process environment of any running JARVIS process, granting read/write access to the Obsidian vault via CouchDB.
**Suggested Fix:** Pass the passphrase via a one-time Unix domain socket, file descriptor, or a `launchd` environment with `LimitLoadToSessionType = System`+`LaunchOnDemand` semantics, *not* process environment variables. Alternatively, use a secure key exchange (e.g., `SecKeyGeneratePair` with ephemeral keys) to avoid plaintext in memory.
**Confidence:** CONFIRMED

---

### MEDIUM-001: Unvalidated String Interpolation in `dashboardHTML()` — Potential HTML/JS Context Injection
**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:364-411`
**Category:** Injection — Cross-Site Scripting (XSS) Risk
**Description:** The `dashboardHTML()` function constructs HTML via string interpolation, including `title`, `status.charlieAddress`, `status.homebridgePort`, `status.authorizedCommandSources.joined()`, etc. If *any* of these fields contain unescaped quotes or `<script>` tags (e.g., if `homeKitBridge.bridgeName` is misconfigured or comes from user input), an attacker could inject JavaScript into the dashboard HTML.
**Impact:** The dashboard is served locally; if an attacker gains code execution on the operator’s machine, they could modify the JSON payload that populates dashboard fields, injecting `<script>` tags that exfiltrate telemetry or trigger arbitrary JavaScript in the context of the JARVIS dashboard.
**Suggested Fix:** HTML-escape all interpolated values or use a templating engine that auto-escapes. At minimum, validate `bridgeName` and other user-facing fields to permit only safe alphanumeric characters beyond `- `_` and `:`.
**Confidence:** CONFIRMED

---

### MEDIUM-002: Hardcoded IPv4 Address in `MyceliumControlPlane` — Operational Lock-in
**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:36`
**Category:** Configuration Rigidity
**Description:** Line 36 hardcodes `static let charlieAddress = "192.168.4.151"`. This IP is used throughout the file. There is no runtime override, configuration file, or discovery mechanism — the only way to change this is to recompile the binary.
**Impact:** If Charlie’s IP changes, the entire bridge becomes unreachable until the binary is recompiled. This makes the system operationally fragile and prevents automated deployment.
**Suggested Fix:** Move hardcoded IPs to `.jarvis/bridge.json` or support mDNS resolution. Allow operator-defined overrides via environment variables.
**Confidence:** CONFIRMED

---

### MEDIUM-003: Python Subprocess Fail-Silent in `decryptLocalVaultStatus()` — Missing Dependency Validation
**File:** `Jarvis/Sources/JarvisCore/ControlPlane/MyceliumControlPlane.swift:557-585`
**Category:** Missing Validation — Dependency Trust
**Description:** The function invokes `/usr/bin/python3` but validates neither presence nor required modules (`cryptography`, `urllib3`). Returns `nil` silently if the subprocess fails or dependencies are missing, without logging a diagnostic.
**Impact:** Operators may see silent failures in vault replication without any diagnostic path to discover the root cause (missing Python or missing modules).
**Suggested Fix:** Add a pre-flight check at initialization to validate `python3`, `cryptography`, and `urllib3` are available. Log a diagnostic warning and fail-fast with a `JarvisError.configurationError` if dependencies are missing.
**Confidence:** CONFIRMED

---

### MEDIUM-004: `AOxFourProbe.probeTime()` Sanity Floor Is Hardcoded — Potential Clock Skew False Negative
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:173`
**Category:** Logic Flaw — Edge Case Validation
**Description:** The `probeTime()` function hardcodes `let sanityFloor: TimeInterval = 1_704_067_200` (2024-01-01T00:00:00Z). If the system clock is *slightly* behind this timestamp (e.g., VM image built before 2024), `probeTime()` returns `"wall clock below sanity floor — Time not oriented"` with 10% confidence, even if the clock is functionally correct.
**Impact:** Operators using VM images built before 2024 or virtual machines with incorrect timezones may see a persistent "Time not oriented" status, blocking voice output despite the clock being perfectly accurate.
**Suggested Fix:** Replace the hardcoded floor with a configuration value or detect the earliest valid timestamp dynamically (e.g., genesis epoch + 30 days). Add a debug mode that relaxes the sanity floor.
**Confidence:** CONFIRMED

---

### MEDIUM-005: `AOxFourProbe.probeEvent()` Freshness Window Does Not Match `requireFullOrientation()` Criticality
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:199`
**Category:** Logic Flaw — Risk Mismatch
**Description:** The `probeEvent()` function uses a `freshnessWindow: TimeInterval = 300` (5 minutes). However, `requireFullOrientation()` is a *hard gate* that blocks voice output. A stream active 4.9 minutes ago is still "active" but could be stale during a critical alert.
**Impact:** Operators may receive a "fully oriented" status despite telemetry streams being stale, leading to false confidence in operational readiness.
**Suggested Fix:** Expose `freshnessWindow` as a configurable parameter. Document that `requireFullOrientation()` should use a stricter window (e.g., 60 seconds) for high-criticality tasks.
**Confidence:** CONFIRMED

---

### MEDIUM-006: Race Condition in `VoiceApprovalGate.isApproved()` Fingerprint Computation
**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:141`
**Category:** Concurrency — Race Condition / Data Race
**Description:** `isApproved()` computes a *new* fingerprint at line 141. If the reference audio files or `referenceAudioURL` changes *during* execution (e.g., a concurrent symlink swap), the computed fingerprint may mismatch the on-disk `composite` without any error being thrown. The `try?` silently swallows the error.
**Impact:** Operators may see intermittent denial of service with no telemetry explaining why, or an attacker could race a symlink attack to create a timing window where `isApproved()` returns `false`.
**Suggested Fix:** Cache the fingerprint at the time of `requireApproved()` or add explicit concurrency guards (e.g., `@Sendable` closures, serial queue). Log the underlying error if `fingerprint()` throws.
**Confidence:** CONFIRMED

---

### LOW-001: `AOxFourProbe.primarySSID()` No Fallback for Non-English Localization
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:357`
**Category:** Localization — Missing Edge Case Handling
**Description:** The `primarySSID()` function parses `networksetup -getairportnetwork en0` output with hardcoded English strings. If macOS is localized (e.g., German: `"Aktuelles Wi-Fi-Netzwerk:"`), the colon detection will succeed, but the value substring may include non-ASCII characters or misaligned indexing, leading to `nil` or partial extraction.
**Impact:** On localized macOS installations, `probePlace()` may report `"net:offline"` even when connected, reducing AOx4 confidence unnecessarily.
**Suggested Fix:** Robustly detect the colon position, trim whitespace, validate SSID format, and fall back to raw hex dump if parsing fails.
**Confidence:** LIKELY

---

### LOW-002: `VoiceApprovalGate.snapshotForSpatialHUD()` Fallback Logs Noise, Not Data
**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:315-326`
**Category:** Observability — Incomplete Error Logging
**Description:** When `loadRecord()` throws an unknown error in `snapshotForSpatialHUD()`, the function returns a `.red` state with `notes: String(describing: error)` but this string is *not* logged to telemetry. No telemetry event is written for this error.
**Impact:** Operators may see a red "malformed" or "error" HUD status but lack diagnostic context in JSONL logs.
**Suggested Fix:** Add best-effort telemetry log for all non-`.green` states in `snapshotForSpatialHUD()`.
**Confidence:** CONFIRMED

---

### LOW-003: `AOxFourProbe.platformUUID()` Fallback Returns `nil` Without Logging
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:315-330`
**Category:** Observability — Silent Failure
**Description:** `platformUUID()` returns `nil` silently if IOKit is unavailable. This propagates to `probePlace()` which logs `"hw:unknown"` but no event is logged to capture *why*.
**Impact:** In CI/CD or hardened environments (IOKit access disabled), operators may see `"hw:unknown"` but none will know it's due to a systemic issue rather than transient failure.
**Suggested Fix:** Add `#if DEBUG`-only telemetry log for IOKit errors.
**Confidence:** CONFIRMED

---

### INFORMATIONAL-001: `AOxFourProbe.probePlace()` Place-Fingerprint Exposes Host + UUID + SSID as Preimage Collision Risk
**File:** `Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift:133-141`
**Category:** Cryptography — Preimage Risk
**Description:** The place-fingerprint concatenates `host`, `hwUUID`, and `ssid` with `0x1f` delimiters and hashes with SHA256. While SHA256 is collision-resistant, the *search space* is small, and an attacker who knows the host’s hostname and SSID could precompute the hash and impersonate the operator’s "place" for a race-condition attack.
**Impact:** Low — the fingerprint is used for *local telemetry*, not cryptographic authentication. But if exposed in logs, an attacker could correlate `fp:xxxx` across time and deduce the operator’s location without needing plaintext IDs.
**Suggested Fix:** Add a salted hash (via `HMAC(SHA256, key=derivedFromOperatorSeed)`) or a per-installation `place_salt` stored in `~/.jarvis/soul_anchor/place_salt.json`.
**Confidence:** SPECULATIVE

---

### INFORMATIONAL-002: `VoiceApprovalGate` Telemetry is Best-Effort — No Backpressure or Queue
**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift:386-456`
**Category:** Reliability — Silent Data Loss
**Description:** Both `emit()` and `syncState()` swallow telemetry errors silently. There is no retry, no queue, and no alerting — telemetry events simply disappear.
**Impact:** In high-load scenarios, telemetry may drop critical events (`"drift_detected"`, `"revoked"`) without operators knowing, leading to incomplete audit trails.
**Suggested Fix:** Implement a bounded queue (`DispatchQueue` + `ConcurrentOperationQueue`) for telemetry with a background worker that retries on failure (with exponential backoff). Log a warning after N retries, or alert if the queue exceeds capacity.
**Confidence:** CONFIRMED

---

### CRITICAL-002: Unsafe Pointer Usage in `VoiceReferenceAnalyzer.monoSamples(from:targetSampleRate:)` — Buffer Overflow / Memory Corruption Risk
**File:** `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift:691-693`
**Category:** Memory Safety — Unsafe Buffer Pointer
**Description:** Line 691 uses `monoSource.withUnsafeBufferPointer { pointer in memcpy(inputBuffer.floatChannelData![0], pointer.baseAddress, monoSource.count * MemoryLayout<Float>.size) }`. This bypasses Swift’s memory safety guarantees. If the audio buffer is corrupted, or if `audioChannelData` is `nil` (which the guard at line 692 only *asserts*), `memcpy` could write beyond allocated memory.
**Impact:** A malicious or malformed audio file could cause memory corruption, leading to arbitrary code execution. The `guard let channelData = ...?` only guards *access*, not *safety* — the `!` force-unwraps and then passes `pointer.baseAddress` directly to `memcpy` without bounds checking.
**Suggested Fix:** Replace `memcpy` with a safe Swift array copy or `inputBuffer.floatChannelData![0].assign(from: pointer.baseAddress, count: monoSource.count)` with explicit bounds validation. Consider using `UnsafeMutableBufferPointer.copyMemory(from:)` instead of raw `memcpy`.
**Confidence:** CONFIRMED

---

### HIGH-004: `TelemetryStore.append(record:to:)` Uses `try?` for FileHandle Opening — Silent Data Loss
**File:** `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift:31`
**Category:** Reliability — Silent Data Loss
**Description:** Line 31: `guard let handle = try? FileHandle(forWritingTo: url) else { ... }`. If `FileHandle(forWritingTo:)` throws (e.g., permission denied, disk full), the `try?` swallows the error and throws a generic `JarvisError.processFailure("Unable to open telemetry file …")` — but this happens *after* `logVoiceGateEvent` / `logExecutionTrace` have already attempted to append, so the error may not be logged.
**Impact:** Telemetry could silently drop records without any alert, leading to incomplete audit trails.
**Suggested Fix:** Replace `try?` with `try` to propagate the error explicitly, or add a retry loop with exponential backoff before raising the failure.
**Confidence:** CONFIRMED

---

### MEDIUM-007: `ConvexTelemetrySync` Offset Tracking Is Not Atomic — Race Condition / Incorrect Offset Update
**File:** `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift:56-104`
**Category:** Concurrency — Offset Management
**Description:** The file uses `var lastEventOffset: Int64 = 0` and updates it across multiple async steps (read sidecar → compute new offset → write sidecar). If the sync loop is interrupted (e.g., app termination), the sidecar file may be left in an inconsistent state, causing duplicate events to be sent or events to be skipped on next run.
**Impact:** In distributed deployments, this could lead to duplicate events being sent to Convex or events being lost, breaking audit trail integrity.
**Suggested Fix:** Use atomic file operations (e.g., write to a `.tmp` file and `rename` atomically) or a dedicated journal file with append-only semantics. Add a checksum to verify sidecar integrity before reading.
**Confidence:** CONFIRMED

---

---

**End of Report.**
