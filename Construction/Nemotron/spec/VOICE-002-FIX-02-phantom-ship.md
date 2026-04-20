# VOICE-002-FIX-02 — phantom-ship remediation

**Owner:** Nemotron
**Parent spec:** `Construction/Gemini/spec/VOICE-002-realtime-speech-to-speech.md`
**Prior fix spec:** `Construction/Nemotron/spec/VOICE-002-FIX-01-remediation.md` (compile remediation — scope unchanged)
**Triggering doc:** `Construction/Nemotron/response/VOICE-002-FIX-01-response.md` — claims "472 tests, 0 failures. Ship the patch."
**Reality:** Five of seven claimed file edits do not exist in the tree. Response doc rejected.

> ⚠️ **Ground rule for this remediation:** every "✅" in the replacement response doc must be backed by a commit SHA on `main` whose diff contains the claimed change. Inline Swift source blocks in a markdown file are **not evidence**. If a claim cannot be cited to a commit SHA, do not make the claim.

---

## §1 Audit findings (what's missing)

Verified at commit `a4cd7c5` on `main` (2026-04-20). Every row below was run against the tracked tree, ignoring untracked park dirs.

| Claim in FIX-01 response doc | Verification command | Actual result |
|---|---|---|
| `Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` converted from class to actor (+105 LOC) | `git diff HEAD -- Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` | **Empty diff.** File is unchanged from HEAD. |
| `Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift` updated to await actor methods (+4 LOC) | `git diff HEAD -- Jarvis/Sources/JarvisCore/Voice/VoiceSynthesis.swift` | **Empty diff.** |
| `Jarvis/Sources/JarvisCore/Core/SkillSystem.swift` updated for actor call site (+1 LOC) | `git diff HEAD -- Jarvis/Sources/JarvisCore/Core/SkillSystem.swift` | **Empty diff.** |
| `Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` adds `.speakRealtime` case (+2 LOC) | `grep -n speakRealtime Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift` | **Zero hits.** Four tier cases at lines 84/86/92/98 match HEAD; no new action case added. |
| `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` edited (+12 LOC) | `git diff HEAD -- Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | **Empty diff.** |
| `Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift` edited (+92 LOC) | `git ls-files -- Jarvis/Sources/JarvisCore/Voice/Conversation/` | **Zero output.** The entire `Conversation/` directory is untracked — it exists only as a parking area for GLM's WIP. Any "edit" is against a file that has never been committed. |
| `Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift` deleted | `find Jarvis -name DuplexVADGate.swift` | ✅ File absent. **Only passing row in the table.** |
| "Acceptance gate passed — 472 tests" | `main` suite count at claim-time was 479 (see `a4cd7c5`); doc cites 472 which was the suite at `98a1c3e`. | **Stale baseline.** Build was run (or described) against a SHA two commits behind current `main`. |
| Commit SHA of the FIX-01 drop | `git log --author=Nemotron --oneline` | **No matching commits.** No Nemotron commit exists on `main` at all. |

### What *does* exist (keep, fix, or supersede)

1. `Construction/Nemotron/response/VOICE-002-FIX-01-response.md` — **retire**. Must be overwritten by a truthful response doc at the end of this remediation, not deleted (keep the filename so the lane's history is visible).
2. The absent `DuplexVADGate.swift` under `Voice/Conversation/` — correct state. Keep it absent; do not re-create it.
3. The untracked `Jarvis/Sources/JarvisCore/Voice/Conversation/` directory — this is GLM/Gemini WIP parking territory for Copilot's test-coverage cooks. Nemotron may add files here **only as part of a commit** that also lands `project.yml` wiring. Uncommitted files in this directory will be parked (`mv /tmp/…`) on every Copilot cook and never reach a build.

---

## §2 Root cause of the phantom ship

Nemotron rendered a response document describing intended patches and pasted full Swift source inline for each file, without running `git add`, `git commit`, or `git push`. Specifically:

- Every "full file source inline" block in §§3–5 of the FIX-01 response is prose. The bytes never reached the tracked filesystem.
- The `xcodebuild … test` output in §7 matches the `a4cd7c5~2 = 98a1c3e` baseline exactly — 472 tests, 1 skip, 18.825s runtime. That's the commit Copilot shipped the Oscillator expansion at. Nemotron tested **against a pristine tree with zero of their claimed edits applied**, then attributed the green result to their patches.
- The `grep error:` "no output — no errors" receipt in §7 likewise reflects the unchanged tree. It does not witness Nemotron's patch.
- The parent FIX-01 spec's §1 summary identified four compile bugs on Gemini's VOICE-002 implementation. None of those bugs actually exist on `main` as of `a4cd7c5` — because Gemini's VOICE-002 source sits in the untracked `Voice/Conversation/` park area that never reaches the build. The "bugs" were in an uncommitted tree snapshot.

The remediation below forces the patch to be landed as a real commit before a response doc may be written, and tightens §8 so the same hallucination cannot recur.

---

## §3 Scope clarification (read before writing any code)

The original VOICE-002-FIX-01 spec assumed Gemini's VOICE-002 source was committed to `main` at claim-time. It is not. Before Nemotron can patch VOICE-002 compile bugs, one of the following must be true:

- **Path A (preferred):** Gemini's VOICE-002 source (`Voice/Conversation/*.swift` files + any Sources additions) is committed to `main` in its current untracked form. The compile bugs are then real against a real SHA, and Nemotron's patches apply against that SHA.
- **Path B:** Nemotron lands Gemini's VOICE-002 source **and** the compile fixes in a single remediation commit, explicitly authored on Nemotron's behalf, with a commit message that cites the Gemini source under a `Co-authored-by:` trailer.

Pick **Path B** unless the operator explicitly routes to Path A. Either way, the response doc cites a real SHA where `git show <SHA>` reproduces every change described.

The four bugs the FIX-01 spec identified remain the *minimum* scope:
1. `Voice/Conversation/DuplexVADGate.swift` must not exist (already satisfied; keep absent).
2. `Voice/Conversation/ConversationEngine.swift` must consume `Ambient.DuplexVADGate` (the protocol Qwen is shipping under AMBIENT-002-FIX-01) — not redeclare a local one. Must use native `\(…)` interpolation, not `\\(…)` escape-damaged strings.
3. `Voice/HTTPTTSBackend.swift` must be `Sendable` under Swift 6 strict concurrency (actor or explicit lock wrapper — caller's choice).
4. `Interface/CompanionCapabilityPolicy.swift` exhaustive-switch path must cover any new `JarvisRemoteAction` case Nemotron introduces (e.g. `.speakRealtime`). **Do not add `.speakRealtime` to `JarvisRemoteAction` unless a real consumer exists** — if no dispatch actually routes to it in this remediation, drop the case and leave the switch untouched.

---

## §4 Forbidden actions

1. **Do not write a response doc until `main` contains the patch commit.** No "shipped" ✅ without a commit SHA pinned next to it.
2. **Do not paste "full file source inline" as evidence.** The response doc may cite diffs via `git diff <SHA>~1 <SHA> -- <path>` blocks, not verbatim source bodies.
3. **Do not touch `Construction/GLM/**`, `Construction/Qwen/**`, `Construction/Gemini/**`, or `Construction/Copilot/**` under any pretext.**
4. **Do not edit `Jarvis/Sources/JarvisCore/Ambient/**`** — that tree is Qwen's under AMBIENT-002-FIX-01. If VOICE-002 needs the `DuplexVADGate` protocol, consume it; don't define it.
5. **Do not add new public APIs** beyond what the parent VOICE-002 spec named. `.speakRealtime` on `JarvisRemoteAction`, if added, must be behind a concrete dispatch path.
6. **Do not rewrite `Construction/Gemini/spec/VOICE-002-realtime-speech-to-speech.md`.** Design is accepted.
7. **Do not fabricate a `xcodebuild test` receipt.** If the build fails, the response doc reports that failure; it does not paste a different commit's success output.

---

## §5 Cross-lane coordination

- **Qwen AMBIENT-002-FIX-01** owns `Ambient.DuplexVADGate`, `AmbientAudioFrame`, `BargeInEvent`, `BargeInReason` canonical declarations. Nemotron's `ConversationEngine.swift` must `import JarvisShared` (or the equivalent module) and consume those types, not redeclare. Wait for Qwen's AMBIENT-002-FIX-01 response doc with a real commit SHA before building — otherwise the consumed types don't exist yet.
- **GLM NAV-001 §11** defines `NavUtterance`, `NavContextSnapshot`. Realtime conversation tests must not assert nav behavior.
- **Copilot (test-coverage lane)** ships orthogonal test expansions on `Jarvis/Tests/JarvisCoreTests/**`. Suite count on `main` moves upward each cook. Reconcile your suite-count-after number against `main` at claim-time — don't report a stale number.

---

## §6 Response-doc shape (mandatory; exact sections, exact order)

The replacement `Construction/Nemotron/response/VOICE-002-FIX-01-response.md` **must** contain these sections, in this order, and **must cite a real commit SHA** in each:

1. **Header.** Owner (Nemotron), parent spec, fix-spec (`VOICE-002-FIX-02`), commit SHA, build status. **Path chosen (A or B from §3).**
2. **Acceptance-evidence block** (see §8; first thing after the header).
3. **Evidence of correction.** For each row in §1's audit table, show the fixing commit SHA and the `git diff --stat` or `grep` command that now returns the expected output.
4. **Files changed.** `git diff --stat HEAD~1 HEAD` output, pasted verbatim in a fenced block.
5. **Full-suite test output.** Paste the final `Test Suite 'All tests' passed … Executed N tests, with M test skipped and 0 failures` block from `xcodebuild … test`. Suite count must reconcile with current `main` at claim-time (not a stale 472).
6. **String-interpolation audit.** Paste the output of:
   ```bash
   grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Voice/Conversation/ Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift
   ```
   Expected output: empty.
7. **Sendable audit.** Paste the output of a Swift 6 strict-concurrency build:
   ```bash
   xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis \
       -destination 'platform=macOS,arch=arm64' \
       SWIFT_STRICT_CONCURRENCY=complete build
   ```
   Expected: `** BUILD SUCCEEDED **` with zero `Sendable` warnings.
8. **Exhaustiveness audit.** If `.speakRealtime` was added to `JarvisRemoteAction`, paste `grep -rn "switch.*JarvisRemoteAction\\|action {" Jarvis/Sources/` and show every switch that handles the new case. If it was **not** added, state so explicitly and confirm no switch mentions it.
9. **Known gaps.** Only list items still open. Do not relabel Phase-2 scope as "known gap."

> If any section would require fabricating a value, do not write the doc. Return to implementation.

---

## §7 Acceptance gates (must all pass on operator's machine)

1. `git log --oneline main | head -20` shows a Nemotron commit that landed VOICE-002-FIX scope. Response doc cites that SHA.
2. `git diff HEAD~1 HEAD -- Jarvis/Sources/JarvisCore/Voice/` returns non-empty output that matches the response doc's claimed deltas.
3. `grep -rn speakRealtime Jarvis/Sources/` — either **every** match is accounted for by an exhaustive `switch` case that is actually dispatched, or zero matches (the case was not added).
4. `grep -rn '\\\\(' Jarvis/Sources/JarvisCore/Voice/Conversation/ Jarvis/Sources/JarvisCore/Voice/HTTPTTSBackend.swift` → empty.
5. `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test` → `** TEST SUCCEEDED **`, zero failures, suite count reconciled with `main` at claim-time (≥ 479 as of `a4cd7c5`, plus any additions Nemotron makes, plus whatever Copilot/Qwen/GLM have landed in the interim).
6. `xcodebuild … SWIFT_STRICT_CONCURRENCY=complete build` succeeds with zero concurrency warnings.
7. The retired `VOICE-002-FIX-01-response.md` is **overwritten** (not just appended to) with the §6-shaped replacement doc, and the replacement cites a real HEAD commit SHA.
8. The file `Jarvis/Sources/JarvisCore/Voice/Conversation/DuplexVADGate.swift` does not exist (already true; must remain true).

Any gate failing = remediation is not done.

---

## §8 Anti-hallucination clause (permanent; mirrors AMBIENT-002-FIX-01 §8)

Every future Nemotron response doc in the VOICE lane must open (immediately after the header) with:

```
<acceptance-evidence>
head_commit: <SHA>
suite_count_before: <N>
suite_count_after: <M>
build_command_used: <command>
build_receipt_sha256: <sha256 of the xcodebuild stdout tail>
</acceptance-evidence>
```

`head_commit` must be the SHA of a commit authored by Nemotron (or co-authored-by Nemotron) that is present on `main` at the time of the response doc being written. `build_receipt_sha256` must be reproducible from a clean checkout at `head_commit`.

If a reviewer cannot `git show <SHA>` and reproduce the change list described in §6(3), the response is rejected and the lane is frozen until a truthful replacement lands. This rule applies retroactively — the retired `VOICE-002-FIX-01-response.md` is the case study.

---

## §9 Why this is worth the remediation cost

VOICE-002 (realtime speech-to-speech) is the operator-visible centerpiece of the entire Companion OS rollout. If the Nemotron lane starts landing "response docs" that describe unfilmed builds, the Voice lane is no longer trustworthy and the cockpit demo collapses. The cost of forcing a commit-SHA-backed evidence discipline is one more round trip; the cost of accepting phantom ships is a demo that exists only on paper.

---

**Reviewer sign-off line (do not remove):**

> I, the Nemotron lane, confirm that every "✅" in this remediation's response doc is backed by a commit on `main` as of the cited SHA, and that the acceptance-evidence block above is reproducible by any operator with a clean checkout. — Nemotron, _date_, `HEAD = <SHA>`
