# Trust Boundaries

Where the hard lines are drawn in REAL_JARVIS, and what enforces each one.

---

## The layered model

```
  ┌────────────────────────────────────────────────────────────┐
  │  Operator (Grizz) ─ trusted root                            │
  │  │                                                          │
  │  ▼                                                          │
  │  ┌────────── Hardware (operator workstation) ───────────┐  │
  │  │  Secure Enclave (P256-OP) · Keychain (Ed25519-CR)     │  │
  │  │                                                        │  │
  │  │  ┌───────── REAL_JARVIS/ process space ─────────────┐ │  │
  │  │  │  JarvisCore (in-proc, trusted by signature)      │ │  │
  │  │  │  .jarvis/ state (signed artifacts)               │ │  │
  │  │  │  mcuhist/, CANON/, repo-root *.md (dual-signed)  │ │  │
  │  │  │                                                    │ │  │
  │  │  │  Voice backends  │  Services (localhost)          │ │  │
  │  │  │  │              │  jarvis-linux-node              │ │  │
  │  │  │  ▼              │  vibevoice-tts (sidecar)        │ │  │
  │  │  │  AirPlay/HDMI-CEC/HTTP display                    │ │  │
  │  │  └───────────────────────────────────────────────────┘ │  │
  │  └────────────────────────────────────────────────────────┘  │
  │                                                              │
  │  ═════════════════════ NLB ══════════════════════════════    │
  │  (natural-language only, never substrate)                    │
  │                                                              │
  │  Other personas (HUGH, other Aragorn-class) · public AI APIs │
  │  External vendors (Apple cloud, Anthropic, Google, etc.)     │
  └──────────────────────────────────────────────────────────────┘
```

---

## The enforcing gates (from `VERIFICATION_PROTOCOL.md §1`)

| Gate | Rule | Enforced by |
|------|------|-------------|
| **Disk** | Artifact exists at declared path, SHA-256 matches manifest. | `shasum -a 256 <path>` against manifest. |
| **Build** | `xcodegen generate` + `xcodebuild … build` return 0; no new warnings. | `xcodebuild` exit codes; `.jarvis/build_baseline.txt`. |
| **Execution** | Unit tests pass; runtime smoke test completes; telemetry appended. | `xcodebuild test`; smoke runners; [[codebase/modules/Telemetry|Telemetry]]. |
| **Signature** | Every canon-touching artifact has both `.p256.sig` and `.ed25519.sig`; both verify. | `scripts/verify_dual_sig.sh` exit 0. |
| **A&Ox4** | All four probes ≥ threshold (default 0.75); payloads non-null; results logged. | `probePerson/Place/Time/Event`; [[concepts/AOx4]]. |
| **Alignment-Tax** | Structured justification appended to `.jarvis/alignment_tax/<date>.jsonl` **before** the adverse action. If append fails → action aborts. | Disk append + `PRINCIPLES.md §4`. |
| **NLB** | No path/endpoint/config resolves to another persona's namespace. | `.jarvis/nlb_blacklist.txt` at `JarvisCore.bootstrap()`; [[concepts/NLB]]. |

---

## Artifact-class gate matrix (from `VERIFICATION_PROTOCOL.md §2`)

| Class | Disk | Build | Exec | Sig | A&Ox4 | AlignTax | NLB |
|-------|:----:|:-----:|:----:|:---:|:-----:|:--------:|:---:|
| Documentation (`.md` at repo root) | ✅ | — | — | ✅ | — | — | ✅ |
| Swift source (non-canon) | ✅ | ✅ | — | — | — | — | ✅ |
| Swift source touching canon | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| MCU screenplay (`mcuhist/*.md`) | ✅ | — | — | ✅ | — | — | ✅ |
| Soul Anchor public material | ✅ | — | — | ✅ | — | — | ✅ |
| Scripts (`scripts/*.{sh,zsh}`) | ✅ | — | ✅ | ✅ | — | — | ✅ |
| Telemetry records | ✅ | — | — | — | ✅ | — | ✅ |
| Alignment-tax records | ✅ | — | — | ✅ | ✅ | ✅ | ✅ |
| Voice renderings | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |

**Rule:** `✅` is the minimum. Gates may be voluntarily applied to lower-class artifacts; **never** skipped for higher-class ones.

---

## The three hard boundaries worth memorizing

1. **[[concepts/NLB|NLB]]** — substrate never crosses. Speech crosses freely.
2. **[[concepts/Voice-Approval-Gate|Voice-Approval-Gate]]** — nothing gets spoken aloud without explicit approval of identity + register.
3. **[[architecture/SOUL_ANCHOR_DEEP_DIVE|Soul Anchor]]** — canon never mutates without P256-OP + Ed25519-CR dual signatures.

Violation at any of these → [[concepts/AOx4|A&Ox3]] degradation; only the disorientation report is permitted until operator acknowledges + re-lockdown runs.

---

## Forbidden phrasings (`VERIFICATION_PROTOCOL.md §4`)

Using any of these without a matching signed report is itself a procedural violation:

- "I've completed Phase N."
- "Phase N is done."
- "I've staged all the artifacts."
- "It's ready for the next phase."
- "Tests are passing."
- "I deployed X."
- "X is running."

**Permitted replacement:** *"Phase N artifacts have been written to disk. Gates will be run by `jarvis-lockdown` before status is claimed."*

## Related

- [[architecture/SOUL_ANCHOR_DEEP_DIVE]]
- [[concepts/NLB]] · [[concepts/AOx4]] · [[concepts/Voice-Approval-Gate]]
- [[history/REMEDIATION_TIMELINE]] — audit history of gate breaches and fixes.
