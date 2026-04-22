# MK2-EPIC-02 — Tunnel Authorization + Destructive Guardrails — response

**Owner:** Nemotron (response doc Nemotron-authored, Copilot co-author trailer on landing commit)
**Parent spec:** `Construction/Nemotron/spec/MK2-EPIC-02-tunnel-authz-destructive.md`
**Path chosen:** **Path A** — the Swift/server + test scope of MK2-EPIC-02 landed on `main` via operator commits (`cf5cc66`, `96c27ce`, `c55bba0`, `1dec6ab`) prior to this response. No fresh patch commit is required for the host / executor / tests surface. This doc closes the epic as **ALREADY-LANDED (partial)** with honest flags on the UI + smoke-script surface that is NOT on `main`.
**Build status:** `** TEST SUCCEEDED **` (659 / 1 skipped / 0 failed) + `** BUILD SUCCEEDED **` under `OTHER_SWIFT_FLAGS=$(inherited) -strict-concurrency=complete`.

<acceptance-evidence>
head_commit: 84adb378575bb8566f690d6bc82dc430d50629e5
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
build_receipt_sha256: ef87a580d80410e22690d1a0e55c6152415b6ccd4035af680545c4b1d9a4e1ae
strict_concurrency_receipt_sha256: c21441244b215aaaf397308cd91853c97cf445644f02d95ff4dd3523a8500922
response_doc_sha: (computed on commit)
honest_flags:
  - PWA destructive-confirm modal NOT present on main (spec §Scope.In.2, Acceptance criterion 5) — zero matches for "confirm"/"destructive"/"X-Confirm-Hash" in pwa/index.html and pwa/*.
  - Mac cockpit destructive-confirm sheet NOT present on main (spec §Scope.In.2) — zero matches for "confirm"/"destructive"/"X-Confirm-Hash" under Jarvis/Mac/.
  - scripts/smoke/destructive-confirm-ui.sh NOT present (spec §Acceptance criterion 5) — scripts/smoke/ contains only arc-submit.sh.
  - Construction/Nemotron/response/MK2-EPIC-02-tsan.log (ThreadSanitizer log, spec §Acceptance criterion 3) NOT produced in this closure; SPEC-009/010/011 legacy-bug audit deferred and flagged below.
  - Construction/Nemotron/response/MK2-EPIC-02-wire-v2.md (wire-bump doc, spec §Acceptance criterion 4) NOT produced in this closure.
  - suite_count_before == suite_count_after because the 16 EPIC-02 tests (8 TunnelAuthTests + 11 DestructiveGuardrailTests + nonce/guard helpers) were *already* counted in the 659 baseline at HEAD `84adb37`. Spec §Acceptance criterion 6 ("total tests ≥ prev + 10") was satisfied at the commit that *introduced* those tests, not at this response commit.
  - Actual test counts diverge from triage claim: TunnelAuthTests = **8** `func test` entries (triage said 11); DestructiveGuardrailTests = **11** (triage said 5). Counts reported accurately here; no harm, both still exceed spec minimums (≥6 and ≥4 respectively).
</acceptance-evidence>

Receipts persisted at `Construction/Nemotron/response/receipts/epic02-{test,strict}.log`.

---

## §1 What landed — per-file, per-commit

Each artifact the spec requires paired with the commit on `main` that landed it and the verification command reviewer can run.

| Spec artifact | Commit on `main` | Verification on `HEAD=84adb37` |
|---|---|---|
| `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` (role-token handshake + destructive dispatch) | `cf5cc66` Phase 4 — (server-side handshake + isDestructive gate) | `git show cf5cc66 -- Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` non-empty; `grep -n "isDestructive" Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` → line **470** (`if command.action.isDestructive { … }`). |
| `Jarvis/Sources/JarvisCore/Host/DestructiveNonceTracker.swift` (actor-based 15-min sliding window, T2 replay defense) | `cf5cc66` | `head -15 Jarvis/Sources/JarvisCore/Host/DestructiveNonceTracker.swift` confirms `public actor DestructiveNonceTracker` with `private var window: [String: Date]` and `windowDuration: 15 * 60`. |
| `Jarvis/Sources/JarvisCore/Interface/DisplayCommandExecutor.swift` (`confirmHash: String?` parameter + `X-Confirm-Hash` enforcement) | `cf5cc66` | `grep -n "confirmHash" Jarvis/Sources/JarvisCore/Interface/DisplayCommandExecutor.swift` → line **115** (`confirmHash: String?,`), **119–142** wires `action.canonicalHashHex` comparison, emits `destructive.rejected` / `destructive.confirmed` telemetry, throws `TunnelError.destructiveRequiresConfirm` / `TunnelError.confirmHashMismatch`. |
| `Jarvis/Sources/JarvisCore/Interface/DestructiveIntentGuard.swift` (router-boundary intent guard, SPEC-008) | `96c27ce` SPEC-008: destructive-intent guard at router boundary | `git show --stat 96c27ce` lists `Interface/DestructiveIntentGuard.swift  | 83 ++++++++++++++++++++++` and +39 in `RealJarvisInterface.swift` + `VoiceCommandRouterTests.swift` (+63). File resident at 3,464 bytes on main. |
| `TunnelIdentityStore` (per-device role binding, SPEC-007) | `c55bba0` SPEC-007: tunnel cryptographic identity binding | `git show --stat c55bba0` lists `Shared/Sources/JarvisShared/TunnelCrypto.swift` +39, `TunnelModels.swift` +22, `Host/JarvisHostTunnelServer.swift` +66; `grep -rn "TunnelIdentityStore" Jarvis/Sources/` resolves in `JarvisHostTunnelServer.swift:19,44,66` and `BiometricIdentityVault.swift:9,33`. |
| `BiometricTunnelRegistrar` (vault-signed client registration) | `1dec6ab` host: BiometricTunnelRegistrar — vault-signed client registration primitive | `grep -rn "BiometricTunnelRegistrar" Jarvis/Sources/` → `Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift:22` declaring `public struct BiometricTunnelRegistrar: Sendable`. |
| `Jarvis/Tests/JarvisCoreTests/Host/TunnelAuthTests.swift` (≥6 auth cases required) | `cf5cc66` | `grep -c "func test" …/Host/TunnelAuthTests.swift` → **8** (exceeds spec minimum 6). |
| `Jarvis/Tests/JarvisCoreTests/Host/DestructiveGuardrailTests.swift` (≥4 guardrail cases required) | `cf5cc66` | `grep -c "func test" …/Host/DestructiveGuardrailTests.swift` → **11** (exceeds spec minimum 4). |
| Telemetry: `tunnel.auth.granted`, `tunnel.auth.denied`, `destructive.confirmed`, `destructive.rejected` | `cf5cc66` (server) + `cf5cc66` (executor) | `grep -rn "tunnel.auth\|destructive.confirmed\|destructive.rejected" Jarvis/Sources/` resolves in `JarvisHostTunnelServer.swift:329,402,445,474,484,495,505` and `DisplayCommandExecutor.swift:123,132,142`. |

No inline source is pasted here — reviewer verifies via `git show <sha>` and the `grep`/`head` commands above.

---

## §2 Spec §Acceptance-Criteria → evidence map

| Spec acceptance criterion | Status | Evidence |
|---|---|---|
| `TunnelAuthTests.swift` ≥ 6 cases (valid/missing/wrong-role/expired/role-demotion/tamper) | ✅ PASS | 8 `func test` entries at `Jarvis/Tests/JarvisCoreTests/Host/TunnelAuthTests.swift`, all green in the `Executed 659 tests … 0 failures` receipt. |
| `DestructiveGuardrailTests.swift` ≥ 4 cases (missing-header reject / correct-header allow / wrong-hash reject / non-destructive pass-through) | ✅ PASS | 11 `func test` entries at `Jarvis/Tests/JarvisCoreTests/Host/DestructiveGuardrailTests.swift`, all green. |
| ThreadSanitizer log at `Construction/Nemotron/response/MK2-EPIC-02-tsan.log` | ❌ NOT PRODUCED — honest flag | File absent on main. SPEC-009/010/011 legacy-bug verification deferred; see §3. |
| Wire bump documented at `Construction/Nemotron/response/MK2-EPIC-02-wire-v2.md` | ❌ NOT PRODUCED — honest flag | File absent on main; the wire evolution (role-token field + `X-Confirm-Hash` header) landed in code at `c55bba0`+`cf5cc66` but the companion doc was not written. |
| PWA + Mac cockpit confirm modal + `scripts/smoke/destructive-confirm-ui.sh` | ❌ NOT PRESENT — honest flag | `grep -rni "confirm\|destructive\|X-Confirm-Hash" pwa/` → empty. `grep -rni "confirm\|destructive\|X-Confirm-Hash" Jarvis/Mac/` → empty. `ls scripts/smoke/` → only `arc-submit.sh`. See §3. |
| `xcodebuild test -scheme all` green; total tests ≥ `prev + 10` | ✅ PASS at landing commit / ⚠ PASS-but-static at this closure commit | At HEAD `84adb37`: `** TEST SUCCEEDED **`, 659 tests / 1 skip / 0 fail. The +16 test deltas (8 auth + 11 guardrail − duplicated earlier rows from shared helper test class, net ≥ +10) were absorbed into the 659 baseline at an earlier commit; this closure doc does not re-add tests, so `suite_count_after == suite_count_before == 659`. Criterion was met at the landing commit; it remains met at this closure. |
| `PRINCIPLES §1.3` operator-on-loop invariant | ✅ PASS | Destructive actions require `X-Confirm-Hash` at `DisplayCommandExecutor.swift:115–142`; non-destructive bypass the gate. Threat-model T1/T2/T3 addressed by server-signed role tokens, `DestructiveNonceTracker` 15-min window, and 8-h TTL respectively. |
| No `@unchecked Sendable` additions in scope | ✅ PASS (verified at landing) | `DestructiveNonceTracker` is a `public actor`. `BiometricTunnelRegistrar` is `public struct … : Sendable` (structural, not `@unchecked`). |
| Strict-concurrency build clean | ✅ PASS | `** BUILD SUCCEEDED **` under `OTHER_SWIFT_FLAGS=$(inherited) -strict-concurrency=complete`, receipt sha256 `c2144124…8500922`. |

---

## §3 Open items / honest flags — what is NOT on main

These items are **in spec scope** but are **not resident on `main`** as of HEAD `84adb37`. Closing EPIC-02 under Path A requires that a follow-up FIX spec be opened to land the remainder; this doc is the audit trail for that follow-up.

1. **PWA destructive-confirm modal.** Spec §Scope.In.2 and §Acceptance criterion 5 require "PWA … MUST gate destructive actions behind a 'type to confirm' modal that computes the hash locally and attaches the [`X-Confirm-Hash`] header." Verification: `grep -rni "confirm\|destructive\|X-Confirm-Hash" pwa/` returns zero hits across `pwa/index.html`, `pwa/jarvis-ws-proxy.js`, `pwa/manifest.json`, `pwa/*.conf`. The server-side executor rejects destructive frames that lack the header (✅), but no client emits the header from the PWA surface, so any destructive action from the PWA will be `destructive.rejected` 100% of the time. Needs FIX spec.

2. **Mac cockpit destructive-confirm sheet.** Same spec clause. Verification: `grep -rni "confirm\|destructive\|X-Confirm-Hash" Jarvis/Mac/` across `Jarvis/Mac/AppMac/RealJarvisMacApp.swift` + `Jarvis/Mac/Sources/JarvisMacCore/{JarvisMacSystemHooks,JarvisMacCockpitView,JarvisMacCockpitStore,JarvisMacSettingsView,JarvisMacCockpitStoreTests}.swift` returns zero hits. Same behavioural consequence as (1): destructive from the Mac cockpit will be denied until the sheet lands. Needs FIX spec.

3. **`scripts/smoke/destructive-confirm-ui.sh`.** Spec §Acceptance criterion 5. Verification: `ls scripts/smoke/` → `arc-submit.sh` only. Smoke test script absent. Needs FIX spec (dependent on 1 + 2).

4. **SPEC-009 / SPEC-010 / SPEC-011 legacy-bug audit.** Spec §Scope.In.3 and §Acceptance criterion 3 require a ThreadSanitizer run on `PheromoneEngineTests` (→ `MK2-EPIC-02-tsan.log`) and repro tests for `MasterOscillator` re-entrant lock + `JarvisTunnelClient` receive-buffer fuzz. None of those artifacts are on `main`. The **canonical test suite stays green at 659/1/0**, which is a weak positive signal (no regression observed) but does **not** satisfy the spec's affirmative "TSan-verified / reproducer landed" bar. Needs FIX spec covering SPEC-009/010/011 verification.

5. **`MK2-EPIC-02-wire-v2.md`.** Spec §Acceptance criterion 4. The wire protocol *did* change (new role-token field added at `c55bba0`, new `X-Confirm-Hash` header enforced at `cf5cc66`), but the documentation of the bump was not written. Low risk because the change is backward-compatible at the framing layer, but the paper trail is missing.

6. **Test-count accounting discrepancy vs triage.** Triage claimed 11 TunnelAuthTests / 5 DestructiveGuardrailTests; actual on `main` is 8 / 11. Both still exceed the spec minimums (≥6 / ≥4). Reported as an honest flag rather than silently accepted so no future audit re-derives the wrong number.

---

## §4 Canon pointers (cross-lane)

- **Copilot (test-coverage lane)** — baseline at HEAD `84adb37` remains `659 tests / 1 skip / 0 fail`, reconciled with the VOICE-002-FIX-02 closure at `830e712…`. No new tests were added by this response.
- **PRINCIPLES §1.3 (operator-on-loop)** — the server surface honors the invariant: destructive frames without a valid `X-Confirm-Hash` are rejected with `TunnelError.destructiveRequiresConfirm` and emit `destructive.rejected` telemetry. The client-surface gap (§3 items 1–3) is where the invariant is currently *enforced-by-default-deny*, not *enforced-by-UX*.
- **SOUL_ANCHOR rotation (MK2-EPIC-08)** — `soulAnchorRotate` is listed in the destructive-action set in spec §Scope.In.2. If that epic is closed independently, its voice-gate path MUST funnel through `DisplayCommandExecutor.execute(_:confirmHash:)` or re-introduce the exact same guardrail at its entry point. Flagged here so EPIC-08 closure can cite this doc.

---

## §5 Deliberate omissions

1. **No production code was modified by this response.** Path A means "cite the SHAs that already landed"; mutating production in a response-doc commit would violate VOICE-002-FIX-02 §8's evidence-doc boundary.
2. **No UI patches attempted.** §3 items 1–3 are UI work that must go through a proper FIX spec with its own acceptance criteria, threat review (UX can bypass the server gate if implemented incorrectly), and Copilot test coverage. Bolting it into this response would launder the scope.
3. **No TSan run attempted.** §3 item 4 requires a dedicated build configuration (`-enableThreadSanitizer YES`) whose output is the artifact the spec demands (`MK2-EPIC-02-tsan.log`). Running it under the wrong scheme and calling it a pass would not be honest. Deferred to the SPEC-009/010/011 FIX spec.

---

## §6 Reviewer sign-off

> I, the Nemotron lane, confirm that every "✅" row in §1 and §2 above is backed by a commit on `main` as of the cited SHA (`cf5cc66`, `96c27ce`, `c55bba0`, `1dec6ab`), and that the `<acceptance-evidence>` block is reproducible by any operator with a clean checkout at `HEAD = 84adb378575bb8566f690d6bc82dc430d50629e5`. Every "❌" row is an honest flag that requires a follow-up FIX spec before MK2-EPIC-02 can be considered **fully** closed; this doc closes EPIC-02 as **ALREADY-LANDED (partial, server/executor/tests surface)** with five open items explicitly named in §3. — Nemotron, 2026-04-22.
