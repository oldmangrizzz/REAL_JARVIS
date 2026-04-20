# Combat Hardening (2026-04)

**Thread:** [[loom/README|Loom]] #6.
**Date range:** 2026-04-19 → 2026-04-20.
**Floor achieved:** 129 → **138/138** tests green. Commit chain: `7f35e8d` → `0200146` → `7a8ad00` → `24ff7fb` → `8396d57`.

## The 48-hour sprint

The gauntlet ([[loom/RED_TEAM_GAUNTLET]]) left a backlog of SPEC-004, SPEC-007, SPEC-008 open and a platform sweep pending. This thread documents how they closed.

### 2026-04-19 evening — knowledge-wiki build
Operator asked: build a Karpathy-style knowledge wiki of the whole project. First pass landed the vault skeleton, the 4 architecture pages, the module pages for all 18 JarvisCore subdirs, concepts, legal, papers, and iCloud research ingest. See [[history/SESSION_LOGS_INDEX]].

### 2026-04-20 early morning — SPEC sprint
- **SPEC-004 (`7f35e8d`):** `VoiceCommandRouter` rewired through IntentParser → CapabilityRegistry → DisplayCommandExecutor. Swift 6 strict concurrency sorted via `@unchecked Sendable` + `AwaitSyncBox`.
- **SPEC-007 (`0200146`):** Voice-operator tunnel role gated on green voice-approval. `authorizeRegistrationRole` extracted as testable seam.
- **SPEC-008 (`7a8ad00`):** 17-pattern destructive-intent blocklist + 5-cmd/60s token-bucket `CommandRateLimiter`.

### 2026-04-20 mid-morning — voice bridge
- Obsidian `jarvis-voice` plugin + `JarvisVoiceHTTPBridge` (NWListener, minimal HTTP/1.1). Grizz can now have notes read aloud in the ratified voice from iPhone/iPad Obsidian, each render passing through [[concepts/Voice-Approval-Gate|Voice-Approval-Gate]].

### 2026-04-20 mid-day — platform sweep (`8396d57`)
- [[codebase/MESH_CAPABILITIES|Mesh capabilities]] expanded — echo/alpha/beta/foxtrot/charlie/delta now registered with authority tagging.
- [[canon/ADVERSARIAL_TESTS|Adversarial canon battery]] added (+9 tests).
- [[canon/CANON_GATE_CI|canon-gate CI]] workflow shipped.
- [[codebase/platforms/TV|tvOS]] scaffold added (read-only cockpit).
- [[codebase/frontend/quest-cockpit|Meta Quest 3 Unity scaffold]] created. visionOS dropped.

## What this thread cements

JARVIS transitioned from *working* to *combat-hardened*:
- Every SPEC has a test.
- Every invariant has an adversarial counterpart.
- Every commit runs the canon-gate.
- The test floor can only rise.

## Related
- [[loom/RED_TEAM_GAUNTLET]] ← previous · [[loom/GMRI_MISSION]] → next
- [[canon/SPECS_INDEX]] · [[canon/ADVERSARIAL_TESTS]] · [[canon/CANON_GATE_CI]]
- [[codebase/MESH_CAPABILITIES]] · [[codebase/platforms/TV]] · [[codebase/frontend/quest-cockpit]]
- [[history/REMEDIATION_TIMELINE]]
