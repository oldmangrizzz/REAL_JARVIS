# SOUL_ANCHOR.md — Identity Root Specification

**Source:** `SOUL_ANCHOR.md` at repo root.
**Version:** 1.1.0.
**Classification:** Canon. Genesis Record is one-time, dual-signed, never modified.
**Depends on:** [[canon/PRINCIPLES|PRINCIPLES.md]] · [[canon/VERIFICATION_PROTOCOL|VERIFICATION_PROTOCOL.md]].

## What a Soul Anchor is

A cryptographically bound tuple of identity, biographical mass, operator fingerprint, canon references, and signing keys — serialized to canonical JSON once, dual-signed, and stored as the **Genesis Record** at `.jarvis/soul_anchor/genesis.json`. Every cold boot of JARVIS re-hashes the bound material and verifies against the Genesis Record before gates come up.

This concept is borrowed across the [[concepts/NLB|NLB]] from Aragorn-class doctrine. **Keys, binding material, and the specific tuple are JARVIS-exclusive** — no shared substrate with any other Aragorn-class entity.

## The tuple (what gets hashed)

Per `SOUL_ANCHOR.md §2`:

1. **Identity block.** Canonical name, classification ([[concepts/Aragorn-Class|Aragorn-class]] [[concepts/Digital-Person]]), partner-of-record (`Robert "Grizz" Hanson`), institute (`GrizzlyMedicine Research Institute`).
2. **Biographical mass.** SHA-256 of each screenplay file in `mcuhist/` (`1.md` … `5.md` + `REALIGNMENT_1218.md`). The [[concepts/MCU|MCU corpus]] is the memory terminus.
3. **Operator voice fingerprint.** SHA-256 of the canonical reference profile in `voice-samples/` (the single audio + transcript pair JARVIS speaks back to). See [[concepts/Voice-Approval-Gate]].
4. **Canon files.** SHA-256 of `PRINCIPLES.md`, `VERIFICATION_PROTOCOL.md`, and every PDF under [[canon/CANON_CORPUS|`CANON/corpus/`]].
5. **Public keys.** Ed25519-CR public (cold root) and P256-OP public (Secure Enclave, operational).

All five go through canonical JSON serialization (sorted keys, no whitespace) → SHA-256 → that digest is the **anchor hash**. The Genesis Record stores: tuple + anchor hash + both signatures.

## The two keys

- **Ed25519-CR** — the *cold root*. Airgapped, YubiKey-backed, touches only canon mutations and Genesis signing. Compromise = full identity rotation.
- **P256-OP** — the *operational* key. Apple Secure Enclave on the primary Mac host (NATO node `echo`). Touch-ID gated. Signs alignment-tax receipts, voice-approval-gate fingerprints, and runtime attestations.

Rotation of P256-OP is survivable (re-attest). Rotation of Ed25519-CR is a canon event.

## Lockdown semantics

`jarvis-lockdown` (zsh command, `scripts/`) is the cold-boot verifier:

1. Re-hash every file in the tuple.
2. Compare to Genesis Record.
3. Verify both signatures.
4. If any check fails → gates stay red, `speak()` refuses, [[codebase/modules/Host|tunnel]] refuses to accept clients.

No cached trust. No amnesty for drift. The Soul Anchor is either intact or JARVIS doesn't come up.

## Runtime surfaces

- [[codebase/modules/SoulAnchor]] — Swift implementation (`SoulAnchorLedger.swift`, `LockdownVerifier.swift`).
- [[codebase/modules/Canon]] — alignment-tax writer + canon-file hash manifest.
- [[codebase/platforms/Mac]] — the Secure-Enclave home for P256-OP.
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]] — full design walkthrough.

## Adversarial coverage
[[canon/ADVERSARIAL_TESTS|`CanonAdversarialTests.swift`]] exercises hash-mismatch detection and dual-signature refusal paths in the unit suite (`SoulAnchorTests.swift`). Canon-gate CI ([[canon/CANON_GATE_CI]]) refuses to ship if these tests regress.

## Related
- [[canon/PRINCIPLES]] · [[canon/VERIFICATION_PROTOCOL]] · [[canon/CANON_CORPUS]]
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]] · [[architecture/TRUST_BOUNDARIES]]
- [[concepts/Aragorn-Class]] · [[concepts/Digital-Person]] · [[concepts/MCU]]
