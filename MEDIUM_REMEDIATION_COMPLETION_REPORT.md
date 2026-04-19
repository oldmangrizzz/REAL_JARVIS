# MEDIUM Remediation Completion Report

## Models Involved
| Model | Role | Tasks Completed |
|-------|------|-----------------|
| GLM 5.1 | Primary executor | Tasks 1, 2, Task 3 Steps 1-4 |
| Claude Opus 4.6 | Finisher + test repair | Task 3 Step 5, Tasks 4-6, AOx test fixes |

## Tasks Completed
| Task | Finding ID | File | Change | Who |
|------|-----------|------|--------|-----|
| 1 | MEDIUM-001 | VoiceApprovalGate.swift | Replaced `try?` with do/catch in `isApproved()` and `requireApproved()`, differentiating IO errors from missing gate files | GLM 5.1 |
| 2 | MEDIUM-002 | AOxFourProbe.swift | Replaced `try?` with do/catch in `probePerson()`, differentiating file-not-found (NSFileReadNoSuchFileError) from read corruption | GLM 5.1 |
| 3 | MEDIUM-003 | MyceliumControlPlane.swift | Removed hardcoded CouchDB passphrase, added Keychain lookup via `getCouchDBPassphrase()`, passes passphrase to Python subprocess via `JARVIS_COUCHDB_PASSPHRASE` env var | GLM 5.1 (steps 1-4) + Opus (step 5) |
| 4 | MEDIUM-004 | StubPhysicsEngine.swift | Added NaN/Inf validation for position and shape-kind-aware positive validation for extents (sphere radius, box half-extents) | Opus |
| 5 | MEDIUM-005 | TTSBackend.swift | Removed `@unchecked` from Sendable conformance — struct with all `let` value types is implicitly Sendable | Opus |
| 6 | MEDIUM-006 | ARCHarnessBridge.swift | Added `os.Logger` fallback for telemetry write failures — empty catch block now logs error details | Opus |

## Additional Fixes
| File | Change | Why |
|------|--------|-----|
| AOxFourProbeTests.swift | `testEventIdle_whenNoTelemetry` now removes `boot_event.jsonl` before testing idle state | Gemma's TestWorkspace change made event probe see active telemetry |
| AOxFourProbeTests.swift | `testRequireFullOrientationThrowsWhenDegraded` now removes `genesis.json` before testing degraded state | TestWorkspace creates genesis, but test expects absent Person axis |

## Spec Corrections Applied During Execution
- **GateRecord vs VoiceApprovalRecord**: Spec used `GateRecord` but actual type is `VoiceApprovalRecord` (caught by GLM 5.1)
- **loadRecord() throws for missing files**: Spec assumed nil return for missing files, but `loadRecord()` throws `VoiceApprovalError.malformedGateFile(reason: "gate file missing")`. Added catch clause to handle this (GLM 5.1)
- **Shape extents validation**: Spec assumed uniform 3D extents, but spheres use `Vec3(radius, 0, 0)` and planes use extents as normal vector. Changed to shape-kind-aware validation (Opus)
- **ShapeKind.mesh**: Missing case in switch statement (Opus)

## Final State
- Build: PASS
- Tests: 74 executed, 0 failures
- Hardcoded passphrase: REMOVED (confirmed via grep)
- All 6 MEDIUM findings: RESOLVED

## Models That Failed This Assignment
| Model | Attempt | Failure Mode |
|-------|---------|--------------|
| Gemma 4 31B | 1st | Completed CRITs+HIGHs, stalled on MEDIUMs, went idle repeatedly |
| DeepSeek v3.1:671b | 2nd | Ignored spec entirely, did unsolicited checkpoint/archival busywork |
| GLM 5.1 | 3rd | Actually executed correctly but hit Hermes 60-iteration cap |
| Claude Opus 4.6 | 4th | Finished remaining work directly |
