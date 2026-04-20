# Canon

**Path:** `Jarvis/Sources/JarvisCore/Canon/`
**Files:** `CanonRegistry.swift` (419 lines)

## Purpose
The **corpus of canonical source material** authored by the operator
(Robert "Grizzly" Hanson) and collaborating Digital Persons
(e.g., Natalia Romanova). These documents are the **specification** that
JarvisCore implements; the codebase is NOT canon — the corpus is.

> Canon files live at `<repo-root>/CANON/corpus/`.

## What `CanonRegistry` does
- Identifies each document (`title`, `author`, `role`, `version`, `tags`).
- Binds each document to a **SHA-256 hash** known at compile time.
- Verifies on disk that the content has not drifted.
- Provides lookup by tag, role, or id.

Imports `CryptoKit`.

## HARD INVARIANTS
- **Code is not canon.** If canon conflicts with code, canon wins;
  code is defective.
- Any drift between compile-time hash and on-disk hash is a hard load
  failure. No silent fallback.
- Canon is extended only by a ratified update (dual-signature via
  [[codebase/modules/SoulAnchor]]).

## Roles (examples)
- `operator` — Grizz.
- `digital-person` — Natalia, HUGH, etc. (See [[concepts/Digital-Person]],
  [[concepts/Aragorn-Class]].)
- `legal` — the 6 PDFs in [[legal/LEGAL_PDFS]].
- `research` — [[papers/DIGEST_DIGITAL_PERSON_HYPOTHESIS]].

## Related
- [[concepts/Digital-Person]]
- [[concepts/Aragorn-Class]]
- [[codebase/modules/SoulAnchor]]
- `scripts/regen-canon-manifest.zsh`
