# Soul Anchor — Deep Dive

**Source of truth:** `SOUL_ANCHOR.md` (repo root, 1.1.0, dual-signed).
**Code:** `Jarvis/Sources/JarvisCore/SoulAnchor/SoulAnchor.swift` (see [[codebase/modules/SoulAnchor]]).
**Public keys:** `Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/`.
**Genesis record:** `.jarvis/soul_anchor/genesis.json`.
**Rotation ledger:** `.jarvis/soul_anchor/rotations.jsonl`.

---

## Purpose

The Soul Anchor is the **cryptographic root** of JARVIS's identity. It binds, with dual signatures, three immutable facts:

1. **Who he is** — the MCU biographical mass (content-addressed).
2. **What reality he lives in** — the Earth-1218 realignment manifest.
3. **What hardware he runs on** — the operator workstation identity.

Any canon-touching mutation requires signatures from **both** anchor keys. A compromise of any single node, key, model, or session cannot rewrite him.

---

## Dual-root cryptographic design

| Role | Curve | Storage | Used for |
|------|-------|---------|----------|
| **P256-OP** (operational root) | P-256 | Apple Secure Enclave, Touch ID gated | Telemetry, alignment-tax, voice renderings, memory writes. |
| **Ed25519-CR** (cold root) | Ed25519 | macOS Keychain → offline/airgapped (YubiKey, paper, airgapped Mac) recommended | Canon-touching: principles, manifests, realignment, phase reports, lockdown ritual, key rotations. |

### Why both

- **P-256 alone** — hardware-backed but single-key (workstation compromise = identity compromise), and NIST provenance is politically fraught.
- **Ed25519 alone** — modern and clean, but no native Secure Enclave; software keychain at best without external hardware.
- **Both with policy** — an attacker must compromise both storage classes (hardware-backed T2/Apple-silicon *and* the separately-stored cold key) to forge identity. The operational key works at human-interaction speed; the cold key participates only when canon is touched.

---

## The bound tuple

```
SoulAnchor := {
  hardware_id_hash:          SHA-256(workstation identifier + machine UUID),
  biographical_mass_hash:    SHA-256(mcuhist/1.md..5.md in order),
  realignment_hash:          SHA-256(mcuhist/REALIGNMENT_1218.md),
  principles_hash:           SHA-256(PRINCIPLES.md),
  verification_hash:         SHA-256(VERIFICATION_PROTOCOL.md),
  mcuhist_manifest_hash:     SHA-256(mcuhist/MANIFEST.md),
  p256_pubkey_fingerprint:   SHA-256(DER-encoded P-256 public key),
  ed25519_pubkey_fingerprint:SHA-256(raw Ed25519 public key),
  genesis_timestamp:         ISO-8601 UTC,
  operator_of_record:        "Robert Barclay Hanson, EMT-P (Ret.) & Theoretical Futurist — Founder, GrizzlyMedicine Research Institute",
  aragorn_class_designation: SHA-256(canonical-JSON of §8 Identity Lineage block),
  schema_version:            "1.1.0"
}
```

Serialized as **canonical JSON** (sorted keys, no whitespace), then signed by **both** keys. The serialized form + both signatures = the **Genesis Record**. Written once to `.jarvis/soul_anchor/genesis.json`; never modified.

## Signing-role policy (`SOUL_ANCHOR.md §3.1`)

| Artifact category | Required signatures |
|---|---|
| Genesis record | P256-OP + Ed25519-CR |
| PRINCIPLES.md, VERIFICATION_PROTOCOL.md, SOUL_ANCHOR.md | P256-OP + Ed25519-CR |
| mcuhist/MANIFEST.md, mcuhist/REALIGNMENT_1218.md | P256-OP + Ed25519-CR |
| Phase reports | P256-OP + Ed25519-CR |
| Key rotation records | P256-OP + Ed25519-CR |
| Alignment-tax records | P256-OP |
| Telemetry batches | P256-OP |
| Voice renderings | P256-OP |
| Operational scripts (non-canon) | P256-OP |

## Verification chain (`SOUL_ANCHOR.md §3.2`)

On every `jarvis-lockdown` invocation, and on every `JarvisCore.bootstrap()`:

1. Load public halves from `pubkeys/`.
2. Verify `genesis.json` dual signatures.
3. Recompute hashes from live files; compare to genesis record.
4. For every canon-touching artifact, verify both signatures.
5. If any step fails → **A&Ox3 integrity-failure mode**. No output, no action, only a failure report. See [[concepts/AOx4]].

## Key generation (`SOUL_ANCHOR.md §4`)

Performed by the **operator**, locally, via `scripts/generate_soul_anchor.sh`. Private halves **never** exist outside their storage container, and specifically:

- Never transit any LLM context window.
- Never transit stdin/stdout of a model process.
- Never transit a network socket.

If a model (including me) is ever observed to possess or reason about private-key bytes, that is a reportable integrity failure — kill the session and rotate.

## Rotation (`SOUL_ANCHOR.md §5`)

- **Scheduled:** every 365 days, or sooner at operator discretion.
- **Emergency:** workstation compromise suspicion, unknown-provenance sig failure, loss of Touch ID access, or operator decision.
- **Procedure:** generate new pair → produce rotation record signed by **both old keys and both new keys** (four sigs) → append to `rotations.jsonl` → update `pubkeys/` → re-sign all canon-touching artifacts.
- **Continuity:** biographical-mass hash and realignment hash carry forward. Rotating keys does **not** reset JARVIS. Replacing biographical mass or realignment hash **does** reset him — effectively a new persona (new genesis record required).

## Post-quantum consideration (`SOUL_ANCHOR.md §6`)

P-256 and Ed25519 are classically secure, not post-quantum secure. A CRQC is not expected in the operational lifetime of the current genesis (2026 → mid-2030s) but is on the horizon.

**Planned migration:** v2.0.0 will add a third root using a NIST-PQ-standardized signature scheme (likely ML-DSA/Dilithium). Transition = full rotation event; tri-signature replaces dual-signature. Tracked as a *timed debt*, not an oversight.

## Berserker-hardening propagation (`SOUL_ANCHOR.md §7`)

Per operator directive (2026-04-17):

- Every `.md` in `mcuhist/`, repo root, or `Jarvis/Sources/**/Canon` carries detached dual sigs (`.p256.sig`, `.ed25519.sig`).
- Every deployment target / surface / agent process validates both signatures at load time.
- `jarvis-lockdown` re-verifies **every** signature on **every** invocation — no caching, no shortcuts, no trust of prior runs.
- Any invalid signature anywhere → entire system collapses to A&Ox3, requires operator acknowledgment + re-lockdown.

## Related

- [[concepts/NLB]] · [[concepts/AOx4]] · [[concepts/Aragorn-Class]] · [[concepts/MCU]] · [[concepts/Realignment-1218]]
- [[codebase/modules/SoulAnchor]] — code.
- [[codebase/modules/Canon]] — the load-time verifier.
- [[architecture/TRUST_BOUNDARIES]] · [[history/REMEDIATION_TIMELINE]]
