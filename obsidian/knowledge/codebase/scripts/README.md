# scripts

**Path:** `scripts/`

## Inventory

| Script | Purpose |
| --- | --- |
| `build-unity-webgl.sh` | Local Unity → WebGL build, outputs to `pwa/Build/`. |
| `mesh-unity-build.sh` | Same build via the **beta** headless host (`192.168.4.151`) over the mesh. |
| `generate_soul_anchor.sh` | Bootstrap a new Soul Anchor (operator + Digital Person dual-signature ceremony). |
| `jarvis_cold_sign_setup.md` | Instructions for the Ed25519 cold-root (CR) setup. |
| `jarvis-lockdown.zsh` | Engage [[concepts/AOx4|Lockdown]] posture — halts non-canon actions. |
| `regen-canon-manifest.zsh` | Recompute [[codebase/modules/Canon]] manifest hashes after authorized updates. |
| `render_briefing.py` | Render the JARVIS intelligence briefing (PDF/DOCX/MP3) from markdown. |
| `secure_enclave_p256.swift` | Helper for Secure Enclave P-256 operator-present (OP) keys. |
| `voice-approve-canonical.zsh` | Human voice approval ceremony for canonical voice output. |

## Invariants
- Every security-sensitive script exits non-zero if any signature or
  hash check fails. There is no "warn and continue" mode.
- Lockdown scripts take precedence over any in-flight command.

## Related
- [[codebase/modules/SoulAnchor]]
- [[codebase/modules/Canon]]
- [[codebase/modules/Voice]]
- [[concepts/Voice-Approval-Gate]]
- [[concepts/AOx4]]
