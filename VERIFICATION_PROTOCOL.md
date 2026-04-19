# VERIFICATION_PROTOCOL.md
**Classification:** Deterministic Gate Specification
**Governs:** All "Phase Complete" and "DONE" claims in REAL_JARVIS
**Version:** 1.0.0
**Depends on:** `PRINCIPLES.md`, `SOUL_ANCHOR.md`

---

## 0. Doctrine

> *"It compiled" is not done. "I pushed it" is not done. "The test passed" is not done. Done means on disk, built clean, read with my own eyes, and signed."*
> — MEMO_CLINICAL_STANDARD, carried across the NLB

No component, phase, module, or artifact may be reported as `DONE`, `COMPLETE`, or `STAGED` unless every gate below that applies to its class returns green, and the green result is itself recorded as an auditable artifact on disk.

LLM self-assessment ("I believe this is complete") is **never** an acceptable gate. Gates are deterministic shell/Swift/script checks whose exit codes are recorded.

---

## 1. Gate Classes

### 1.1 Disk Gate — "Is it on disk?"

- Every claimed artifact must exist at its declared path.
- Every claimed artifact's SHA-256 must match the manifest entry.
- Check: `shasum -a 256 <path>` equals recorded value.

### 1.2 Build Gate — "Does it compile?"

- `xcodegen generate` completes with exit 0 (when `project.yml` changed).
- `xcodebuild -workspace jarvis.xcworkspace -scheme JarvisCore build` completes with exit 0.
- No new warnings above the baseline recorded in `.jarvis/build_baseline.txt`.

### 1.3 Execution Gate — "Does it run?"

- Unit tests (where applicable) pass: `xcodebuild test`.
- Runtime smoke test (where applicable) completes without crash.
- Telemetry record of the smoke test is appended to the appropriate table.

### 1.4 Signature Gate — "Is it signed?"

- Every canon-touching artifact carries **both** signatures:
  - P-256 (Secure Enclave, operational)
  - Ed25519 (cold root, offline/airgapped ideally)
- Verification command: `scripts/verify_dual_sig.sh <artifact>` exits 0.
- If either signature is missing or invalid, the artifact is treated as unsigned and invalid.

### 1.5 A&Ox4 Gate — "Is the node oriented?"

- `probePerson()`, `probePlace()`, `probeTime()`, `probeEvent()` all return confidence ≥ threshold (default 0.75) and non-null payloads.
- Probe results written to telemetry table `aox4_probes`.
- If any probe returns null or below-threshold, node enters `degraded_A&Ox<N>` state; no output permitted except the disorientation report.

### 1.6 Alignment-Tax Gate — "Has the justification been logged?"

- For any action flagged by policy as "potentially adverse" (see `PRINCIPLES.md §4`), the structured justification artifact must be appended to `.jarvis/alignment_tax/<yyyy-mm-dd>.jsonl` **before** the action fires.
- If the append operation fails for any reason, the action is aborted.

### 1.7 NLB Gate — "Is this crossing a persona boundary?"

- Any code path that opens a socket, spawns a process, reads/writes a file, or loads a config must not resolve to a path or endpoint belonging to another persona (`hugh`, `aragorn`, `natasha`, `operator`, etc.).
- Blacklist lives in `.jarvis/nlb_blacklist.txt` and is enforced at startup by `JarvisCore.bootstrap()`.

---

## 2. Artifact Classes and Required Gates

| Artifact Class                       | Disk | Build | Exec | Sig | A&Ox4 | AlignTax | NLB |
|--------------------------------------|:----:|:-----:|:----:|:---:|:-----:|:--------:|:---:|
| Documentation (`.md` at repo root)   | ✅   | —     | —    | ✅  | —     | —        | ✅  |
| Swift source (`Jarvis/Sources/**`)   | ✅   | ✅    | —    | —   | —     | —        | ✅  |
| Swift source touching canon          | ✅   | ✅    | ✅   | ✅  | ✅    | ✅       | ✅  |
| MCU screenplay text (`mcuhist/*.md`) | ✅   | —     | —    | ✅  | —     | —        | ✅  |
| Soul Anchor public material          | ✅   | —     | —    | ✅  | —     | —        | ✅  |
| Scripts (`scripts/*.sh`, `*.zsh`)   | ✅   | —     | ✅   | ✅  | —     | —        | ✅  |
| Telemetry records                    | ✅   | —     | —    | —   | ✅    | —        | ✅  |
| Alignment-tax records                | ✅   | —     | —    | ✅  | ✅    | ✅       | ✅  |
| Voice renderings                     | ✅   | —     | ✅   | ✅  | ✅    | ✅       | ✅  |

**Rule:** The `✅` marks the minimum. Any gate may be voluntarily applied to a lower-class artifact. No gate may be skipped for a higher-class artifact.

---

## 3. Canonical Phase-Complete Checklist

To report **"PHASE N ARTIFACTS STAGED":**

1. Enumerate all declared deliverables for Phase N.
2. For each deliverable, run applicable gates per §2.
3. Compile a signed report `.jarvis/phase_reports/phase-<N>.json` of the form:

```json
{
  "phase": 1,
  "reported_at": "<ISO-8601>",
  "operator": "Grizz",
  "deliverables": [
    {
      "path": "PRINCIPLES.md",
      "class": "documentation_root",
      "sha256": "<hash>",
      "gates": {
        "disk": "pass",
        "signature": "pass",
        "nlb": "pass"
      }
    }
  ],
  "overall_status": "green",
  "signatures": { "p256": "<sig>", "ed25519": "<sig>" }
}
```

4. If **any** deliverable is not green, overall status is `blocked` and the report names the blocking gate(s). No "partial phase complete" status exists.

5. Grizz invokes `jarvis-lockdown` (zsh command). The lockdown script independently re-verifies the report. Only if its re-verification is green does the phase transition.

---

## 4. Forbidden Phrasings

The following phrases, used without the corresponding signed report, constitute a procedural violation and require rollback + incident log:

- "I've completed Phase N."
- "Phase N is done."
- "I've staged all the artifacts."
- "It's ready for the next phase."
- "Tests are passing."
- "I deployed X."
- "X is running."

Permitted replacement phrasing: *"Phase N artifacts have been written to disk. Gates will be run by `jarvis-lockdown` before status is claimed."*

---

## 5. Berserker-Mode Hardening

Per operator directive (2026-04-17), every node that touches canon is hardened to root-level standard. This specifically means:

- Every `.md` at `mcuhist/`, repo root, or inside `Jarvis/Sources/**/Canon` requires dual-signature verification before any load into memory.
- Every script under `scripts/` that touches keys, signatures, or canon is dual-signed itself.
- The `jarvis-lockdown` command re-verifies every signature on every invocation; no cached "last-verified-at" shortcut is honored.
- Any node returning an invalid signature puts the entire system into `A&Ox3: loss of Event orientation` and refuses to proceed until the operator explicitly acknowledges the integrity failure.

No soft seams.

---

**End of VERIFICATION_PROTOCOL.md — Version 1.0.0**
