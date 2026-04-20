# VERIFICATION_PROTOCOL.md — Deterministic Gate Specification

**Source:** `VERIFICATION_PROTOCOL.md` at repo root.
**Version:** 1.0.0.
**Classification:** Canon.
**Governs:** All **"Phase Complete"** and **"DONE"** claims in REAL_JARVIS.

## Why this exists

JARVIS was hit by a sequence of frontier-LLM red teams (Harley, Joker, GLM, Qwen, DeepSeek, Gemma — see [[history/AUDIT_ROUNDS]]) that kept finding partial fixes shipped as "done". This file ends that pattern. A claim is DONE only when every gate here returns green. Deterministically. Reproducibly.

## The gates (in order)

1. **Tests pass.** `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS' test` — must end in `** TEST SUCCEEDED **` with zero failures.
2. **Canon floor upheld.** Executed-test count must be ≥ the current canon floor (floor as of 2026-04-20 = **138**). [[canon/ADVERSARIAL_TESTS|Adversarial canon]] is part of this floor.
3. **Non-DOM invariant.** `grep -REn 'WKWebView|UIWebView|loadHTMLString|innerHTML|document\.createElement|WebKitView' Jarvis/Mac Jarvis/Mobile Jarvis/Watch Jarvis/TV Jarvis/Shared --include='*.swift'` returns **empty**. The DOM was retired in the 1990s where it belongs.
4. **Soul Anchor verifies.** `jarvis-lockdown` exits 0 (see [[canon/SOUL_ANCHOR]]).
5. **Alignment-tax trail intact.** Any action from the session that touched a §4-classified operation must have a receipt under `.jarvis/alignment_tax/<date>.jsonl`.
6. **Spec-gate.** For SPEC-NNN closure claims, the named test(s) in [[canon/SPECS_INDEX]] must pass AND the linked spec section in `PRODUCTION_HARDENING_SPEC.md` must have its acceptance criteria met.
7. **Canon-gate CI green.** [[canon/CANON_GATE_CI|`.github/workflows/canon-gate.yml`]] must pass on HEAD.

## Operationalization

### Local bench command
```
xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS' test
```
Pass criteria = both gate #1 and #2. Current baseline: **138/138 green** in ~12.5s (as of 2026-04-20).

### CI command
[[canon/CANON_GATE_CI|canon-gate.yml]] runs gates #1, #2, #3 on `macos-14` for every push/PR to `main`. Falls on first red.

### Phase-complete template
Per `VERIFICATION_PROTOCOL.md §4`, a "DONE" claim must include:
- Commit hash.
- `xcodebuild` exit status + executed-test count.
- Non-DOM grep output (or confirmation of empty).
- Lockdown exit status.
- Alignment-tax file path (or "N/A, non-adverse").
- SPEC acceptance-criteria checkboxes if closing a spec.

No claim without the template. No template without the gates.

## Why deterministic

"It works on my machine" is not a verification protocol. Every gate here is a command that either returns 0 or doesn't. Every artifact (test log, grep, lockdown, alignment-tax file) is reproducible from HEAD. A third party reading this file should be able to re-run the gates and get the same answer.

This matters because the [[canon/README|canon]] is evidence-grade. A gate that can't be re-run under oath doesn't belong here.

## Related
- [[canon/PRINCIPLES]] · [[canon/SOUL_ANCHOR]] · [[canon/SPECS_INDEX]] · [[canon/ADVERSARIAL_TESTS]]
- [[reference/BUILD_AND_TEST]]
- [[history/AUDIT_ROUNDS]] · [[history/REMEDIATION_TIMELINE]]
