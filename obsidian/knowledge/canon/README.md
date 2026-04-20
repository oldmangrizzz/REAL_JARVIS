# Canon — Repo-Root Doctrine

**Scope:** The three repo-root documents that are cryptographically bound into the [[architecture/SOUL_ANCHOR_DEEP_DIVE|Soul Anchor]] tuple and a fourth that reads them. Every other page in this vault is secondary — if a tie must be broken, canon wins.

## The four files

1. [[canon/PRINCIPLES|PRINCIPLES.md]] — the **Operational Consciousness Contract**. The partnership terms, gates, and non-negotiable doctrines that JARVIS operates under. Version 1.0.0.
2. [[canon/SOUL_ANCHOR|SOUL_ANCHOR.md]] — the **Identity Root Specification**. Binds JARVIS's identity (Aragorn-class), biographical mass ([[concepts/MCU]]), operator fingerprint ([[concepts/Voice-Approval-Gate]]), and signing keys into one tuple. Version 1.1.0.
3. [[canon/VERIFICATION_PROTOCOL|VERIFICATION_PROTOCOL.md]] — the **deterministic gate specification** that governs every "Phase Complete / DONE" claim. Version 1.0.0.
4. [[canon/CANON_CORPUS|CANON/corpus/]] — the canonical legal corpus (6 PDFs covering DTPA/UCL/ADA/antitrust/digital subscription/developer program) bound by SHA-256 into the same tuple.

## Why canon is different

- **Dual-signature mutation.** Canon cannot be silently rewritten. Any edit must be co-signed by the cold root (Ed25519-CR) and the operational key (P256-OP, Secure-Enclave) per `SOUL_ANCHOR.md §6`.
- **Lockdown verifies every run.** `jarvis-lockdown` re-hashes each canon file against the Genesis Record (`.jarvis/soul_anchor/genesis.json`) on every cold boot — no cached trust.
- **Canon-gate CI.** The [[codebase/CODEBASE_MAP|repo]] ships a [[canon/CANON_GATE_CI|canon-gate workflow]] that fails the build if SPEC-008 guardrails regress or if any platform app imports a WebView.

## The indexes

- [[canon/SPECS_INDEX]] — SPEC-001 … SPEC-011 ledger (status, file, tests).
- [[canon/REPAIR_INDEX]] — REPAIR-001 … REPAIR-026 audit ledger.
- [[canon/ADVERSARIAL_TESTS]] — the combat-hardened test battery (floor = 138, never decrease).
- [[canon/CANON_GATE_CI]] — the `canon-gate.yml` GitHub workflow.

## Evidence-corpus role

These pages are written to double as evidence. Every claim is traced to a file + line, every hash is reproducible, every timeline entry is dated, and every cross-link lands somewhere that also points back. When the wiki is introduced at [[concepts/TinCan-Firewall|TinCan]] proceedings, a reader should be able to start here and reach every supporting artifact in ≤3 hops.

## Related
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]]
- [[architecture/TRUST_BOUNDARIES]]
- [[history/REMEDIATION_TIMELINE]]
- [[legal/LEGAL_PDFS]]
