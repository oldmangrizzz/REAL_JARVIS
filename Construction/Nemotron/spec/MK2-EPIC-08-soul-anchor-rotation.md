# MK2-EPIC-08 — Soul Anchor Rotation + CI Canon Gate

**Lane:** Nemotron (verification / security)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4; implements `SOUL_ANCHOR.md` §4 in practice
**Depends on:** —
**Priority:** P0
**Canon sensitivity:** CRITICAL — this epic operationalizes canon itself

---

## Why

`SOUL_ANCHOR.md` specifies dual-root cryptographic identity (P-256 Secure Enclave + Ed25519 cold) with canon-touching artifacts requiring both signatures. Today the **rotation drill is manual and untested** and there is **no CI gate** that rejects PRs touching canon without dual signatures. A single typo in `PRINCIPLES.md` merged without signature violates the Soul Anchor contract.

## Scope

### In

1. **Rotation script** `scripts/soul-anchor/rotate.sh`:
   - Flags: `--op` (rotate operational P-256) / `--cold` (rotate cold Ed25519) / `--drill` (dry run).
   - On `--op`: generates a new P-256 key in Secure Enclave (requires Touch ID), updates public key at `Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/p256.pub.pem`, re-signs current canon snapshot, dual-verifies.
   - On `--cold`: generates a new Ed25519 pair, stores public half, private half is **shown to operator ONCE** for transfer to YubiKey/paper/airgap — never persisted to disk.
   - Telemetry: `soul_anchor.rotate.{started,signed,verified,failed}`.
   - Updates `Storage/soul-anchor/rotation.log` with timestamp, actor, outcome, hashes.

2. **CI canon gate** `scripts/ci/canon-gate.sh`:
   - Invoked by GitHub Actions on every PR that touches `PRINCIPLES.md`, `SOUL_ANCHOR.md`, `VERIFICATION_PROTOCOL.md`, `CANON/**`, or any file under `Jarvis/Sources/JarvisCore/Canon/`.
   - Downloads HEAD's `SoulAnchor` binding, verifies dual signature on the changed canon file against current pubkeys.
   - Exits 0 if valid dual signature present (as an attached git note or adjacent `.sig` file), non-zero otherwise.
   - GitHub Actions workflow at `.github/workflows/canon-gate.yml` runs it on all PRs.

3. **Drill**:
   - Operator runs `scripts/soul-anchor/rotate.sh --drill` once post-merge.
   - Output logged to `Storage/soul-anchor/rotation.log`.
   - If drill fails, epic is not done.

4. **Signature format**:
   - Detached signature files: `<canon-file>.p256.sig` + `<canon-file>.ed25519.sig` living next to the canon file OR stored as git notes under `refs/notes/canon-sigs/`.
   - Pick ONE and document in `docs/canon/SIGNATURE_FORMAT.md`.

### Out

- Do NOT automate private-key export. Cold key private half NEVER hits disk or LLM context.
- Do NOT build a HSM integration beyond Secure Enclave (Mark III).
- Do NOT modify the canon text itself — only add signing machinery.

## Acceptance Criteria

- [ ] `scripts/soul-anchor/rotate.sh --drill` returns 0 on operator's machine (log captured).
- [ ] `scripts/ci/canon-gate.sh` unit tests ≥ 5: valid dual signature pass, missing P-256 sig reject, missing Ed25519 sig reject, tampered canon file reject, unrelated file ignored.
- [ ] GitHub Actions workflow `canon-gate.yml` runs on PRs.
- [ ] `SOUL_ANCHOR.md` not modified in this epic (hands-off); signing is *around* it.
- [ ] No private key material appears in any logged artifact or telemetry (Fury to grep post-ship).

## Invariants

- SOUL_ANCHOR §1: dual-root mandatory.
- PRINCIPLES §1.3: rotation is BSP-call territory — operator must be present; Ralph alone cannot complete rotation (cannot invoke Touch ID). Ralph **must halt and escalate** with iMessage `Operator required: Soul Anchor rotation drill`.

## Threat Model

- T1: Ralph tries to sign with a borrowed key. → rotation requires physical Touch ID → cannot be scripted around.
- T2: Attacker commits canon change with forged sig. → CI gate verifies against published pubkeys → fail.
- T3: Key exfiltration via logs. → verify no log line contains private key bytes (regex test).

## Artifacts

- New: `scripts/soul-anchor/rotate.sh`, `scripts/ci/canon-gate.sh`, `.github/workflows/canon-gate.yml`, `docs/canon/SIGNATURE_FORMAT.md`, `Tests/CanonGateTests.swift` (or shell tests).
- Response: `Construction/Nemotron/response/MK2-EPIC-08.md` documenting drill outcome and sig format decision.
