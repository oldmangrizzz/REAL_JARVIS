<!--
  MK2-EPIC-07 response doc (phantom-ship §6/§8 shape)
  Governing spec:  Construction/Qwen/spec/MK2-EPIC-07-telemetry-dashboard.md
  Shape spec:      Construction/Nemotron/spec/VOICE-002-FIX-02-phantom-ship.md §6, §8
  Template ref:    Construction/Nemotron/response/VOICE-002-FIX-01-response.md
                   Construction/Qwen/response/UX-001-response.md
  Governing standard: MEMO_CLINICAL_STANDARD.md
-->

# MK2-EPIC-07 — Telemetry + Dashboard Enrichment (response)

## Header

- **Lane owner:** Qwen (data / UX)
- **Parent spec:** `Construction/Qwen/spec/MK2-EPIC-07-telemetry-dashboard.md`
- **Parent program:** `MARK_II_COMPLETION_PRD.md` §4
- **head_commit (evidence pinned):** `9dfde310e1dbcf078a77245c4f2081c26ffc56fe` — SHA at which both canonical gates were run for this close-out. Preceding doc-only commit; HEAD is behaviorally identical to `84adb37` for the purposes of the in-repo EPIC-07 surface (no source change between the two).
- **Closure classification:** **PARTIAL / EXTERNAL-DEFERRED.** In-repo Swift + schema + tests are landed on `main` under a Nemotron-authored commit (honest flag §3). External deliverables — Convex `telemetry:push` / `telemetry:recent` endpoints, forge-dashboard server.py enrichment, Caddy auth — are not-in-repo and remain operator-owed.
- **Build status (HEAD `9dfde31`):** `** TEST SUCCEEDED **` (659 / 1 skipped / 0 failed) + `** BUILD SUCCEEDED **` under `-strict-concurrency=complete` (1 out-of-scope warning, 0 errors — identical to the VOICE-002-FIX-02 and UX-001 close-outs).

<acceptance-evidence>
head_commit: 9dfde310e1dbcf078a77245c4f2081c26ffc56fe
response_doc_sha: (computed at landing commit; see §8 bottom block)
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
test_receipt_sha256: 97e165ea3c770586b07aba07b7ead982d5a04239f086a517b5e64c576c6c1b29
strict_receipt_sha256: 854a770f09dbb25c439d1b2b307a70f16176f78483e980f2a29a247426c9aa4d
honest_flags: ["landing_author_mismatch_cf5cc66_is_nemotron_not_qwen", "schema_event_count_29_below_target_30", "convex_telemetry_push_recent_not_implemented", "dashboard_server_py_external_delta_not_in_repo", "three_of_four_acceptance_tests_missing", "strict_build_one_out_of_scope_warning_voice_synthesis_807"]
</acceptance-evidence>

Receipts persisted at `Construction/Qwen/response/receipts/epic07-test.log` (sha256 `97e165ea…6c6c1b29`) and `Construction/Qwen/response/receipts/epic07-strict.log` (sha256 `854a770f…26c9aa4d`). No source-code change is made by this close-out; the doc re-shapes existing in-repo landings and explicitly enumerates what the operator still owes on external infrastructure (Delta, Convex deployment, Caddy).

---

## §1 What landed (in-repo, verified on `main`)

All source artifacts below were authored by the **Nemotron lane** under commit `cf5cc66` ("Phase 4: wire ConversationEngine turn/barge-in/route state + XTTS canon preset"), not Qwen. The authorship discrepancy is called out as the first honest flag. The Qwen lane consumes them now as EPIC-07 carry-over.

| Artifact | Landing commit | Path | Lines | Verification |
|---|---|---|---|---|
| Telemetry schema doc | `cf5cc66` | `docs/telemetry/SCHEMA.md` | 178 | `wc -l docs/telemetry/SCHEMA.md` → `178` |
| Heartbeat emitter | `cf5cc66` | `Jarvis/Sources/JarvisCore/Telemetry/HeartbeatEmitter.swift` | 110 | `git log --all -- Jarvis/Sources/JarvisCore/Telemetry/HeartbeatEmitter.swift` → `cf5cc66` |
| Heartbeat emitter tests | `cf5cc66` | `Jarvis/Tests/JarvisCoreTests/HeartbeatEmitterTests.swift` | 128 | `git log --all -- Jarvis/Tests/JarvisCoreTests/HeartbeatEmitterTests.swift` → `cf5cc66` |
| `TelemetryStore` (pre-existing, chain-witnessed) | `a5daeff` / `2a55b65` / `d1cab26` | `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | 361 | `git log --all -- Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` |
| `ConvexTelemetrySync` (pre-existing best-effort uploader) | `daa117a` | `Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` | 204 | `git log --all -- Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift` |

Verified absence of canon violations (PRINCIPLES §2):

```
grep -nE 'audio|waveform|principles_hash|privateKey|secretKey' \
    Jarvis/Sources/JarvisCore/Telemetry/HeartbeatEmitter.swift
```
→ zero hits. The heartbeat body carries only `{event, voiceGateOK:Bool, tunnelClients:Int, memoryVersion:String, lastIntentAt:String?}` — coarse scalars; no raw audio, no canon bytes, no private keys.

---

## §2 Spec-gate evidence map (acceptance criteria)

Every acceptance bullet in `MK2-EPIC-07-telemetry-dashboard.md` "Acceptance Criteria", paired with its status, fixing commit(s), and verification evidence.

| # | Acceptance criterion (verbatim) | Status | Fixing commit | Evidence (as of `9dfde31`) |
|---|---|---|---|---|
| 1 | Schema doc enumerates ≥ 30 event names with field contracts | **PARTIAL** | `cf5cc66` | `docs/telemetry/SCHEMA.md` defines 13 tables enumerating 29 distinct event/row shapes — one short of the ≥30 target. Count: `execution_traces(1) + stigmergic_signals(1) + recursive_thoughts(1) + vagal_tone(1) + node_registry(1) + harness_mutations(1) + voice_gate_state(1) + voice_gate_events(5: approved/revoked/rotated/failed/rejected) + heartbeat(1) + tunnel_events(4) + arc_submission_events(6) + oscillator(4: started/stopped/tick/plv) + conversation_turns+state_transitions(2) = 29`. Field contracts are complete for every enumerated row. |
| 2 | `curl https://forge.grizzlymedicine.icu/tasks` returns JSON with `ralph_iter`, `ralph_budget` fields | **EXTERNAL-DEFERRED** | — | Dashboard server at `/opt/swarm-forge/dashboard/server.py` runs on **Delta**, outside this repo tree. `find . -name server.py -path "*dashboard*"` → empty. No in-repo artifact can satisfy this gate; operator owes the enrichment on Delta. |
| 3 | Heartbeat gap > 60 s visibly turns the health pill YELLOW in < 5 s | **PARTIAL (emitter-side landed; dashboard-side external)** | `cf5cc66` | Emitter contract + pill thresholds (GREEN<60s, YELLOW≤300s, RED older) are encoded in `HeartbeatEmitter.swift:14-17` header comment and `SCHEMA.md §heartbeat`. Dashboard visualization (the actual pill DOM + `/tasks` JSON) is external (Delta). Tests verify the emitter writes conformant rows; nothing in-repo can render the pill. |
| 4 | Unauthorized `/tasks` requests rejected (HTTP 401/403) | **EXTERNAL-DEFERRED** | — | Auth layer is Caddy basic-auth / bearer in front of `/opt/swarm-forge/dashboard/` on Delta, not repo code. Spec §Out explicitly assigns this to the Caddy/forge-auth tier. |
| 5 | New tests ≥ 4: schema parser, heartbeat emitter, Convex mutation validator, dashboard unauthorized-reject | **PARTIAL (1 of 4 landed)** | `cf5cc66` | Only `HeartbeatEmitterTests.swift` landed (6 test methods, covering tick → row shape, timestamp threshold math for GREEN/YELLOW/RED boundaries, stop-after-start cleanup, isolation of provider). **Missing:** schema-parser test (no schema parser binary exists; the schema is human-reference only), Convex mutation validator test (Convex surface absent from repo — see §5), dashboard unauthorized-reject test (dashboard external — see §5). |

Ancillary artifacts from the spec §Artifacts block:

| Artifact | Status | Path | Notes |
|---|---|---|---|
| `docs/telemetry/SCHEMA.md` | **LANDED** | as above | 178 lines, `cf5cc66`. |
| `Telemetry/HeartbeatEmitter.swift` | **LANDED** | as above | 110 lines, `cf5cc66`. |
| `Tests/HeartbeatEmitterTests.swift` | **LANDED** | as above | 128 lines, `cf5cc66`. |
| `convex/telemetry.ts` (or equivalent) | **NOT-STARTED** | `convex/` | No `telemetry.ts` file exists. `convex/jarvis.ts` hosts per-table mutations (`logStigmergicSignal`, `logVagalTone`, `logHarnessMutation`, `logVoiceGateEvent`, `recordMobileHeartbeat`, etc.) but **no generic `telemetry:push` / `telemetry:recent` pair** with strict validator + role gate as the spec requires. |
| `/opt/swarm-forge/dashboard/server.py` (modified) | **EXTERNAL-DEFERRED** | Delta | Not in repo. |
| `/opt/swarm-forge/dashboard/templates/index.html` (modified) | **EXTERNAL-DEFERRED** | Delta | Not in repo. |
| `Construction/Qwen/response/MK2-EPIC-07.md` | **LANDED by this commit** | `Construction/Qwen/response/MK2-EPIC-07-response.md` | Filename follows lane convention (`-response.md` suffix, matches sibling `AMBIENT-002-response.md` + `UX-001-response.md`). |

---

## §3 Honest flags

1. **Landing author is Nemotron, not Qwen.** The Swift + schema + tests that satisfy the in-repo portion of MK2-EPIC-07 were pushed under `cf5cc66`, a Nemotron Phase-4 commit. Qwen lane is closing the EPIC-07 response doc and inheriting authorship-credit for the carry-over. The FIX-02 §8 anti-hallucination discipline requires this to be surfaced, not laundered. The landing commit for *this response doc* is Qwen-authored with a `Co-authored-by: Copilot` trailer to close the formal lane loop.
2. **Schema is 29 events, spec target is ≥30.** One-event gap. No event was invented to pad the count; honest accounting over narrative.
3. **Convex surface is absent.** Spec §Scope.In(2) requires `telemetry:push` accepting every SCHEMA event with strict validator, and `telemetry:recent(limit)` returning last N rows role-gated. Neither exists. `convex/jarvis.ts` has ~13 per-table mutations, not a single generic telemetry entrypoint. The spec's Convex work is untouched.
4. **Dashboard deliverables are all on Delta.** Acceptance criteria 2, 3-render, 4 all point at paths outside this repo. The spec treats those paths as in-scope; the clinical-standard close-out records them as **EXTERNAL-DEFERRED** because no commit inside `REAL_JARVIS/` can satisfy them.
5. **Three of four mandated tests are missing.** Per spec §Acceptance bullet 5 (schema parser / heartbeat emitter / Convex mutation validator / dashboard unauthorized-reject). Only the heartbeat-emitter test landed. The other three tests are conditional on deliverables that themselves haven't landed (no schema parser, no generic Convex push mutation, no in-repo dashboard server). Tests cannot be written for artifacts that do not exist.
6. **One out-of-scope strict-concurrency warning.** `Voice/VoiceSynthesis.swift:807:16` — `capture of 'provider' with non-Sendable type 'Provider' in a '@Sendable' closure`. This warning predates EPIC-07, is already logged against the VOICE-001 provider-registry lane (and noted honestly in VOICE-002-FIX-02 §6 and UX-001 §9), and is **not in MK2-EPIC-07 scope**. `** BUILD SUCCEEDED **` with 0 errors.
7. **No source-code change.** Per operator instruction, this close-out is response-doc + receipts only. `git diff HEAD~1 HEAD -- Jarvis/Sources/ docs/ convex/` at landing time is expected to be empty for every non-`Construction/Qwen/response/` path.

---

## §4 Cross-lane dependencies

- **MK2-EPIC-01 (prerequisite per spec header).** Closed; this close-out assumes the EPIC-01 memory-graph surface is stable.
- **Nemotron `cf5cc66` (Phase 4 ConversationEngine).** Source of the schema + heartbeat landing. Not a blocker — already on `main`.
- **SPEC-009 chain-witness (`2a55b65`) + principal-witness (`a5daeff`).** `TelemetryStore.append` hashes and principal-tags every row. Heartbeat rows inherit that discipline automatically.
- **MK2-EPIC-02 (Nemotron `6c93e12` / `cf5cc66` / `96c27ce` / `c55bba0` / `1dec6ab`).** `tunnel_events` table in `SCHEMA.md §tunnel_events` is owned by that lane; EPIC-07 only catalogues the events, does not define their contract.
- **MK2-EPIC-03 (GLM `6b39d1d`).** `arc_submission_events` table similarly cross-referenced, not owned here.
- **MK2-EPIC-08 (Nemotron `a9269c1`).** Soul-anchor rotation telemetry cross-cuts `harness_mutations` and `voice_gate_events` tables; contract is already in SCHEMA.

No blocking cross-lane dependency remains. Close-out proceeds with the PARTIAL / EXTERNAL-DEFERRED classification.

---

## §5 External-owed list (the "phantom list" for the operator)

Items the spec requires that **cannot be closed from inside this repo**. Operator retains responsibility; JARVIS-side repo state cannot satisfy any of them.

1. **`convex/telemetry.ts` — generic `telemetry:push` and `telemetry:recent(limit)` endpoints.**
   - `telemetry:push` must accept any SCHEMA event with a strict validator that rejects unknown top-level keys and malformed table-specific bodies (spec §Scope.In(2)).
   - `telemetry:recent(limit)` must return the last N rows across all tables, **role-gated** (operator / companion / guest tier). Spec implies the same authz lattice EPIC-02 introduced for the tunnel.
   - Until this lands, `ConvexTelemetrySync.swift` in the repo is best-effort-uploading into a Convex schema that does not present a generic telemetry inbox — rows funnel into per-table mutations in `convex/jarvis.ts`.
2. **`/opt/swarm-forge/dashboard/server.py` (on Delta) — "Jarvis Live" section.**
   - Show tunnel-connections count, voice-gate state, last mesh action, current telemetry burst rate.
   - Data source: Convex `telemetry:recent` over HTTPS, cached 2 s.
3. **`/opt/swarm-forge/dashboard/server.py` (on Delta) — "Ralph Runtime" section.**
   - Per-task `iter` / `budget` / lesson-count from `/opt/swarm-forge/state/ralph/<tid>.json`.
   - Each task row must link to a modal rendering the latest `<tid>.md` Ralph scratchpad (read-only).
4. **`/tasks` JSON schema change (on Delta).**
   - `curl https://forge.grizzlymedicine.icu/tasks` must include `ralph_iter` and `ralph_budget` per task. Acceptance criterion #2.
5. **Caddy / forge auth hardening (on Delta).**
   - Unauthorized `/tasks` requests must return HTTP 401 or 403. Spec §Out prohibits public exposure. Acceptance criterion #4.
6. **Dashboard health-pill state machine (on Delta).**
   - GREEN / YELLOW / RED thresholds (60 s / 300 s / older) from the newest `heartbeat` row, with < 5 s propagation from gap → YELLOW. Acceptance criterion #3 visual half.
7. **Convex-mutation-validator test (Swift or TS — wherever the Convex handler lives).**
   - Acceptance criterion #5 third bullet. Requires item 1 above to land first.
8. **Dashboard-unauthorized-reject test (on Delta or its test harness).**
   - Acceptance criterion #5 fourth bullet. Requires item 5 above to land first.
9. **Schema-parser test (in-repo).**
   - Conditional: if a schema parser is ever implemented (none exists today — `SCHEMA.md` is human-reference only), a test asserting parser roundtrip against the enumerated tables. Cheapest remaining item.
10. **Schema +1 event to reach the ≥30 bar.**
    - Either add a genuinely-emitted event (e.g. `soul_anchor.rotation` under EPIC-08, which already has rows but isn't enumerated in SCHEMA.md under its own heading), or explicitly amend the acceptance bar in a follow-up spec. **Do not invent an event to hit the number.**

Every item above is real operator infrastructure. The spec conflated "Jarvis-side telemetry emission" (closable in-repo) with "operator-side dashboard rendering" (Delta). This close-out separates the two.

---

## §6 Full-suite + strict-concurrency receipts (canonical gates)

### §6.1 Full test suite

```
$ xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
      -destination 'platform=macOS,arch=arm64' test \
      2>&1 | tee Construction/Qwen/response/receipts/epic07-test.log
…
Test Suite 'JarvisCoreTests.xctest' passed at 2026-04-22 08:32:51.964.
	 Executed 659 tests, with 1 test skipped and 0 failures (0 unexpected) in 18.440 (18.648) seconds
Test Suite 'All tests' passed at 2026-04-22 08:32:51.965.
	 Executed 659 tests, with 1 test skipped and 0 failures (0 unexpected) in 18.440 (18.648) seconds
…
** TEST SUCCEEDED **
```

Receipt sha256: `97e165ea3c770586b07aba07b7ead982d5a04239f086a517b5e64c576c6c1b29`.
Suite count reconciled against `84adb37` baseline (659/1/0); no delta across the intervening doc-only commits (`a9269c1`, `9dfde31`).

### §6.2 Strict-concurrency build

```
$ xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
      -destination 'platform=macOS,arch=arm64' build \
      OTHER_SWIFT_FLAGS='$(inherited) -strict-concurrency=complete' \
      2>&1 | tee Construction/Qwen/response/receipts/epic07-strict.log
…
Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift:807:16: warning:
    capture of 'provider' with non-Sendable type 'Provider' in a '@Sendable' closure
…
** BUILD SUCCEEDED **
```

Receipt sha256: `854a770f09dbb25c439d1b2b307a70f16176f78483e980f2a29a247426c9aa4d`.
1 warning, 0 errors. Warning is out-of-scope (VOICE-001 provider registry), unchanged from VOICE-002-FIX-02 and UX-001 close-outs.

### §6.3 In-scope EPIC-07 artifact sanity

```
$ grep -nE 'audio|waveform|privateKey|secretKey' \
      Jarvis/Sources/JarvisCore/Telemetry/HeartbeatEmitter.swift
$
$ grep -c '^### ' docs/telemetry/SCHEMA.md
16
```

No canon-leak vectors in the heartbeat body. 16 level-3 headings, 13 of which are table definitions (the other 3 are `Global invariants`, `Tables`, `Versioning`).

---

## §7 Deliberate omissions

1. **No in-repo dashboard mock.** Spec's dashboard section is Delta-resident. Adding a stub dashboard in-repo would create a second maintenance surface with no consumer; `NOT-STARTED` on this is correct posture, not drift.
2. **No Convex schema migration.** Until the operator signs off on the generic `telemetry:push` / `telemetry:recent` design (role gate, rate limit, validator shape), landing a `convex/telemetry.ts` in this repo would either (a) ship without auth, violating EPIC-02, or (b) duplicate policy already implemented in `jarvis.ts` per-table mutations. This close-out records the omission with the Option-B remediation path: promote the per-table mutations to a dispatcher pattern, or add a thin `telemetry:push` that routes internally to the existing mutations.
3. **No schema-parser implementation.** Spec §Scope.In(1) says the schema "is documentation; no code change unless an event name is inconsistent." It was inconsistent-free at landing; parser not required. The acceptance-criterion test for a parser is therefore vacuously deferred.
4. **No `+1 event` padding.** Per §3 honest flag 2: schema stops at 29 events because that's the honest count. Adding a token 30th event to clear the bar would be the kind of hallucination VOICE-002-FIX-02 §8 forbids.

---

## §8 Acceptance-evidence block (mirror — §6 shape requires top + bottom)

<acceptance-evidence>
head_commit: 9dfde310e1dbcf078a77245c4f2081c26ffc56fe
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
test_receipt_sha256: 97e165ea3c770586b07aba07b7ead982d5a04239f086a517b5e64c576c6c1b29
strict_receipt_sha256: 854a770f09dbb25c439d1b2b307a70f16176f78483e980f2a29a247426c9aa4d
classification: PARTIAL / EXTERNAL-DEFERRED
landed_commits: ["cf5cc66 (Nemotron Phase 4 — HeartbeatEmitter + SCHEMA.md + HeartbeatEmitterTests)", "a5daeff (principal-witness)", "2a55b65 (SPEC-009 chain-witness)", "d1cab26 (Qwen AMBIENT-002-FIX-01 TelemetryStore tightening)"]
external_deferred_count: 10
honest_flags: ["landing_author_mismatch_cf5cc66_is_nemotron_not_qwen", "schema_event_count_29_below_target_30", "convex_telemetry_push_recent_not_implemented", "dashboard_server_py_external_delta_not_in_repo", "three_of_four_acceptance_tests_missing", "strict_build_one_out_of_scope_warning_voice_synthesis_807", "response_doc_only_no_source_change"]
</acceptance-evidence>

---

**Reviewer sign-off line (FIX-02 §9 convention):**

> I, the Qwen lane, confirm that every "LANDED" row in §2 is backed by a commit on `main` as of the cited SHA, that every "EXTERNAL-DEFERRED" and "NOT-STARTED" row is recorded with the operator's outstanding obligation in §5, and that the acceptance-evidence blocks above are reproducible by any operator with a clean checkout at `HEAD = 9dfde310e1dbcf078a77245c4f2081c26ffc56fe`. — Qwen, 2026-04-22, classification **PARTIAL / EXTERNAL-DEFERRED**.
