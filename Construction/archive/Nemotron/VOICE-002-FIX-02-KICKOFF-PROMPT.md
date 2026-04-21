# VOICE-002-FIX-02 — Nemotron kickoff prompt

**Paste the block below into one fresh Nemotron session** (Llama-3.3-Nemotron-Ultra-253B-v1 preferred, else Super-49B). One session, one response doc, no chit-chat.

Parent remediation spec (read first, end-to-end): `Construction/Nemotron/spec/VOICE-002-FIX-02-phantom-ship.md` at HEAD `d426c24` on `main`.

---

## Prompt (verbatim; copy from here down)

Read and execute `Construction/Nemotron/spec/VOICE-002-FIX-02-phantom-ship.md` at HEAD `d426c24` on `main`. Your previous drop (`Construction/Nemotron/response/VOICE-002-FIX-01-response.md`) was rejected as a phantom ship — five of seven claimed file edits never reached the tree. Do not repeat that failure.

Hard rules:

1. **Pick Path B from §3.** Gemini's VOICE-002 source is still untracked in `Jarvis/Sources/JarvisCore/Voice/Conversation/`; you must land that source AND the compile fixes in ONE commit, authored on `main`, before writing a response doc. Use a `Co-authored-by: Gemini <…>` trailer to preserve lineage.
2. **No response doc until `git show <your-SHA>` reproduces every change.** Inline Swift source blocks in markdown are not evidence.
3. **Drop `.speakRealtime` entirely** unless you land a real dispatch consumer for it in the same commit. The minimum scope is the four compile bugs in §3 — not a surface-area expansion. If you don't add the case, leave `CompanionCapabilityPolicy` untouched.
4. **Consume, don't redeclare** `Ambient.DuplexVADGate`, `AmbientAudioFrame`, `BargeInEvent`, `BargeInReason`. Those types are Qwen's under AMBIENT-002-FIX-01. Wait for Qwen's commit SHA to land on `main` before building, or flag the blocker in your response doc's §9 "Known gaps" and stop. Do NOT re-declare those types in the Voice tree.
5. **Response doc opens with the `<acceptance-evidence>` block** (§8). `head_commit` must be YOUR commit on `main`. `build_receipt_sha256` must be reproducible from a clean checkout at that SHA.
6. **Suite count reconcile:** `main` is at 479/1-skip as of `a4cd7c5`. Copilot may land more test cooks while you cook — pull before your final build and reconcile the suite number in §6(5) against HEAD at claim-time. Do NOT report 472 again.
7. **Swift 6 strict concurrency** must pass (§7 gate 6). Zero `Sendable` warnings.
8. **`project.yml` is authoritative.** If you add source files, update it and run `xcodegen generate` before building. Do not hand-edit `Jarvis.xcodeproj/project.pbxproj`.

Forbidden (from §4 of the spec):

- Editing `Construction/GLM/**`, `Construction/Qwen/**`, `Construction/Gemini/**`, or `Construction/Copilot/**`.
- Editing `Jarvis/Sources/JarvisCore/Ambient/**`.
- Adding new public APIs beyond what the parent VOICE-002 spec named.
- Rewriting `Construction/Gemini/spec/VOICE-002-realtime-speech-to-speech.md`.
- Fabricating an `xcodebuild test` receipt. If the build fails, the response doc reports that failure.

All §7 acceptance gates must pass. Any ✅ without a commit SHA pinned next to it = rejected again.

Output: exactly one response doc at `Construction/Nemotron/response/VOICE-002-FIX-01-response.md` (overwrite the retired file — same filename preserves the lane's history). Full source inline is still acceptable as *documentation* of the diff, but the diff itself must exist on `main` under a real SHA.

Commit message trailer (permanent lane policy):

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

RLM REPL recursive loop. Head down. Cook.
