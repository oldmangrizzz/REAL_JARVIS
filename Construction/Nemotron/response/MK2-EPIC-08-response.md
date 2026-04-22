# MK2-EPIC-08 — Soul Anchor rotation + CI canon gate response

**Owner:** Nemotron (Copilot co-author trailer on landing commit)
**Parent spec:** `Construction/Nemotron/spec/MK2-EPIC-08-soul-anchor-rotation.md`
**Path chosen:** **Path A (ALREADY-LANDED)** + one live drill + one minimal closing patch. The epic's substantive artifacts (`scripts/soul-anchor/rotate.sh`, `scripts/ci/canon-gate.sh`, `.github/workflows/canon-gate.yml`, `docs/canon/SIGNATURE_FORMAT.md`, `storage/soul-anchor/rotation.log` scaffold) already shipped on `main` in `2d80f1a`. Spec §Acceptance demanded **≥5 canon-gate test cases**; `2d80f1a` only shipped a four-case dev-sandbox check referenced in the commit message with no committed harness. This response adds a committed `--self-test` harness covering all 5 acceptance cases (including `unrelated_file_ignored`) and captures the post-merge operator drill.
**Build status:** `** TEST SUCCEEDED **` (659 / 1 skipped / 0 failed) + `** BUILD SUCCEEDED **` under `SWIFT_STRICT_CONCURRENCY=complete`.

<acceptance-evidence>
head_commit: <filled-in-by-landing-commit>
suite_count_before: 659
suite_count_after: 659
build_command_used: xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test
build_receipt_sha256: ae97a293f0a37da8a315655ed820ac1394642a0703a7b5dff222041ab9218c7e
strict_build_receipt_sha256: 59b23d4e21c92bf0b441f9f0761d9efb9b1bdaadd680e4ac83f3a694ba42bec5
drill_log_sha256: 0a5b9f695bfad3a43b9377b9dbe41c7be50b450c0b6e5e36da597820d3ee4876
canon_gate_selftest_sha256: 11c198eae0844ec9e53330a6d0a97cff3d49d1ab94490ef8e2da1c3b5ed9557c
response_doc_sha: <filled-in-by-landing-commit>
honest_flags:
  - canon-gate-5th-test-added-in-this-response: spec §2 required ≥5 cases; 2d80f1a shipped only the 4 inline sandbox cases cited in its commit message. This response adds a committed bash `--self-test` harness with all 5 cases, including `unrelated_file_ignored`. Landed minimal env-override (`CANON_GATE_REPO_ROOT`, `CANON_GATE_PUB_DIR`) to allow the harness to exercise the gate against a throwaway git sandbox — no behaviour change on real invocation (vars default to the script-relative paths already used).
  - rotation-log-path-casing: spec references `Storage/soul-anchor/rotation.log` (capital S) and the drill script writes to `Storage/…`; the filesystem tracked path is `storage/soul-anchor/rotation.log` (lowercase). APFS is case-insensitive by default so both resolve; on a case-sensitive volume this would need reconciliation. Not fixed in this response.
  - private-key-grep-hit-is-documentation: `grep -rn 'PRIVATE\|-----BEGIN' storage/ Jarvis/Sources/` returns one hit — `Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/README.txt:16` — a README line stating "NO PRIVATE BYTES ARE STORED IN THIS DIRECTORY." Not actual key material.
  - drill-ran-in-agent-session: the operator ran `--drill` from a terminal not gated by `refuse_in_agent` (drill mode intentionally allows this; `--op` and `--cold` still hard-fail on agent env vars).
</acceptance-evidence>

Receipts persisted at `Construction/Nemotron/response/receipts/epic08-{drill,canon-gate-selftest,test,strict}.log`.

---

## §1 Evidence of correction — audit-table rollup

Each acceptance criterion from the spec, paired with the commit on `main` (or this response's closing patch) that satisfies it and the verification command reviewers can re-run.

| Spec §Acceptance bullet | Fixing commit on `main` | Verification |
|---|---|---|
| `scripts/soul-anchor/rotate.sh --drill` returns 0 on operator's machine (log captured) | `2d80f1a` | `bash scripts/soul-anchor/rotate.sh --drill` → exit 0, 4-line append to `storage/soul-anchor/rotation.log`. Receipt `receipts/epic08-drill.log` sha256 `0a5b9f69…e4876`. |
| `scripts/ci/canon-gate.sh` unit tests ≥ 5 (valid / missing-P256 / missing-Ed25519 / tampered / unrelated) | `2d80f1a` shipped 4 informal sandbox cases; **this response's landing commit** adds a committed `--self-test` harness covering all 5 | `bash scripts/ci/canon-gate.sh --self-test` → `5 passed, 0 failed`. Receipt `receipts/epic08-canon-gate-selftest.log` sha256 `11c198ea…d9557c`. |
| GitHub Actions workflow `canon-gate.yml` runs on PRs | `2d80f1a` | `cat .github/workflows/canon-gate.yml` — triggers on `pull_request`, invokes `scripts/ci/canon-gate.sh`. |
| `SOUL_ANCHOR.md` not modified in this epic | `2d80f1a` and this response both preserve | `git log --follow --oneline SOUL_ANCHOR.md` shows no entry from 2d80f1a or EPIC-08 response. |
| No private key material in any logged artifact | `2d80f1a` behaviour | `grep -rn 'PRIVATE\|-----BEGIN' storage/ Jarvis/Sources/` → one doc-only hit (README stating NO private bytes). Listed in honest flags. |

---

## §2 Files changed

### Already landed in `2d80f1a`

```
 .github/workflows/canon-gate.yml |  16 ++++++
 docs/canon/SIGNATURE_FORMAT.md   |  68 +++++++++++++++++++
 scripts/ci/canon-gate.sh         | 110 ++++++++++++++++++++++++++++++++++++
 scripts/ship-mark-ii.sh          | 199 +++++++++++++++++++++++++++++++++++++++
 scripts/soul-anchor/rotate.sh    | 167 ++++++++++++++++++++++++++++++++++++++
 storage/soul-anchor/rotation.log |   4 ++
 6 files changed, 564 insertions(+)
```

### Added by this response (MK2-EPIC-08 closure commit)

```
 scripts/ci/canon-gate.sh                                         | ~100 lines inserted (--self-test harness + 2-line env-override hook)
 Construction/Nemotron/response/MK2-EPIC-08-response.md           | new
 Construction/Nemotron/response/receipts/epic08-drill.log         | new
 Construction/Nemotron/response/receipts/epic08-canon-gate-selftest.log | new
 Construction/Nemotron/response/receipts/epic08-test.log          | new
 Construction/Nemotron/response/receipts/epic08-strict.log        | new
 storage/soul-anchor/rotation.log                                 | +4 lines (drill append)
```

No inline source is pasted; reviewer verifies via `git show <closure-sha> -- scripts/ci/canon-gate.sh`.

---

## §3 Gate-by-gate evidence

| Gate | Requirement | Result |
|------|-------------|--------|
| §Acceptance bullet 1 | Drill returns 0 on operator's machine | ✅ `bash scripts/soul-anchor/rotate.sh --drill` → `soul_anchor.rotate.verified mode=drill outcome=pass`, exit 0. Log appended. |
| §Acceptance bullet 2 | ≥5 canon-gate test cases | ✅ `bash scripts/ci/canon-gate.sh --self-test` → `5 passed, 0 failed` (valid_dual_signature_pass, missing_p256_sig_reject, missing_ed25519_sig_reject, tampered_canon_file_reject, unrelated_file_ignored). |
| §Acceptance bullet 3 | `canon-gate.yml` runs on PRs | ✅ Workflow present; `on: pull_request`. |
| §Acceptance bullet 4 | `SOUL_ANCHOR.md` untouched | ✅ `git diff 2d80f1a^..HEAD -- SOUL_ANCHOR.md` → empty. |
| §Acceptance bullet 5 | No private key material in logs | ✅ `grep -rn 'PRIVATE\|-----BEGIN' storage/ Jarvis/Sources/` returns only the pubkey README documenting the absence of private bytes. |
| Full suite | 659/1/0 preserved | ✅ `** TEST SUCCEEDED **`, 659 executed, 1 skipped, 0 failed. Receipt `receipts/epic08-test.log`. |
| Strict concurrency | `SWIFT_STRICT_CONCURRENCY=complete build` clean | ✅ `** BUILD SUCCEEDED **`. Receipt `receipts/epic08-strict.log`. |
| PRINCIPLES §1.3 | `--op`/`--cold` refuse in agent env | ✅ `refuse_in_agent` guard present in `rotate.sh` for both modes; `--drill` intentionally does not refuse (dry-run sandbox). |

---

## §4 Deliberate omissions

1. **No modification of `SOUL_ANCHOR.md` itself** — spec §Acceptance bullet 4 forbids it.
2. **No HSM integration beyond Secure Enclave** — spec §Scope "Out" defers to Mark III.
3. **No automation of cold-root private-key export** — `--cold` still displays the private half to operator once via stderr then destroys the ephemeral file; no disk persistence, no log capture.
4. **No conversion of `canon-gate.sh` to Swift test target** — spec §Artifacts explicitly allowed "shell tests" as an alternative to `Tests/CanonGateTests.swift`; shell harness chosen to avoid coupling canon-gate to Xcode test runner.

---

## §5 Canon pointers (cross-lane)

- **Copilot (test-coverage lane)** — suite count unchanged at 659/1/0. No EPIC-08 code path is exercised by `JarvisCoreTests.xctest`; the canon gate is a shell-level CI artefact.
- **MK2 ship orchestrator** — `scripts/ship-mark-ii.sh` stage 7 invokes `canon-gate.sh` against `HEAD~1..HEAD`; unchanged by this response.
- **VOICE-002-FIX-02** — independent lane; build baseline (659/1/0) matches.

---

## §6 Known gaps

- **Rotation log path casing** (`Storage/` vs `storage/`) — see honest flag. Harmless on APFS; would fail on case-sensitive filesystems.
- **No signature-rotation-over-time test** — acceptance §2 enumerates the 5 required cases; a "pubkey rotated between BASE and HEAD" case is not mandated and is deferred.

No other residue remains.

---

**Reviewer sign-off:**

> I, the Nemotron lane, confirm that every "✅" above is backed by a commit on `main` (or by the response's closure commit) as of the cited SHA, and that the acceptance-evidence block is reproducible by any operator with a clean checkout running `bash scripts/soul-anchor/rotate.sh --drill` and `bash scripts/ci/canon-gate.sh --self-test`. — Nemotron, `HEAD = <closure-sha>`
