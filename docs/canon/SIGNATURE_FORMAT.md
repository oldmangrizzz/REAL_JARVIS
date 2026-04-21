# Canon Signature Format

Every canon-touching file (see §Scope below) must carry a pair of detached
signature sidecars committed alongside it. CI enforces this via
`scripts/ci/canon-gate.sh` (see `.github/workflows/canon-gate.yml`).

## Scope

A file is "canon-touching" if it matches any of:

- `PRINCIPLES.md`
- `SOUL_ANCHOR.md`
- `VERIFICATION_PROTOCOL.md`
- `CANON/**`
- `Jarvis/Sources/JarvisCore/Canon/**`

Sidecar signature files (`.p256.sig`, `.ed25519.sig`) are ignored for the
purpose of the gate itself but must be present for every listed file.

## Sidecar files

For a canon file `path/to/FILE.md` the committer produces:

| Sidecar                         | Algorithm      | Producer                                       |
|---------------------------------|----------------|------------------------------------------------|
| `path/to/FILE.md.p256.sig`      | ECDSA-P256 over SHA-256 of the raw file bytes | Secure Enclave on the operator's Mac via `scripts/sign_canon.sh` |
| `path/to/FILE.md.ed25519.sig`   | raw Ed25519 over the raw file bytes           | Cold root (YubiKey / airgapped Mac / paper)    |

Both must verify against the public halves committed at
`Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/`:

- `p256.pub.der`     — DER-encoded P-256 public key
- `ed25519.pub.pem`  — PEM Ed25519 public key (or `ed25519.pub.der`, which
  the gate converts on demand)

## Rationale

Detached `.sig` sidecars were chosen over git-notes or in-file embedded
signatures because:

1. They are trivially verifiable with a vanilla `openssl` install — CI
   runners and operator machines do not need any custom tooling.
2. They survive git operations that discard notes (rebases, history
   rewrites via `git filter-repo`, squash merges on GitHub).
3. A tampered file is detected immediately because the sidecar still
   encodes the original bytes' hash/signature; a matching re-sign would
   require access to both Secure Enclave and the cold root — the dual
   compromise the Soul Anchor is designed to force.

## Verification

    bash scripts/ci/canon-gate.sh <base-sha> <head-sha>

Exits 0 when no canon files changed, or when every changed canon file
carries valid P-256 and Ed25519 signatures. Exits 1 on any failure with a
`canon-gate: FAIL <file> — <reason>` line identifying the offender.

## Signing workflow (operator)

1. Make the canon change locally.
2. Run `scripts/sign_canon.sh path/to/FILE.md` — this invokes the Secure
   Enclave helper for the P-256 sidecar and prompts for cold-root
   participation for the Ed25519 sidecar.
3. `git add path/to/FILE.md path/to/FILE.md.p256.sig path/to/FILE.md.ed25519.sig`
4. Commit, push, open PR. The `canon-dual-sig` CI job must pass.

Private keys are never handled by this script or CI. Only public halves
live in the repo.
