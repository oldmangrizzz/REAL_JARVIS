# Grizz OS — canon

> Status: **active**.
> Tier palette: black / silver / crimson / Munro emerald — wired in
> [[../../../Jarvis/Shared/Sources/JarvisShared/JarvisBrandPalette.swift|JarvisBrandPalette.grizzOS]].

## What it is

Grizz OS is the operator tier of the Jarvis skin family. It is the surface
Jarvis wears when the bound [[../../../Jarvis/Shared/Sources/JarvisShared/Principal.swift|Principal]]
resolves to `.operatorTier` — i.e. the device is one of Robert "Grizzly"
Hanson's vetted personal machines and the session's identity proof chain
traces back to the operator identity key.

Same binary as [[Companion-OS]] and [[Responder-OS]]. Difference is
runtime: capability matrix, palette, and escalation defaults all branch
on the active principal.

## Authority

Grizz OS is the **single privileged principal** in the trust model.
- Full capability matrix.
- Can rotate tokens, edit `identities.json`, flip canon policy.
- Can command display control over α / β / δ / ε / φ surfaces.
- Only tier allowed to issue destructive intents (still gated by
  [[../concepts/SPEC-008]] token bucket — the guard is additive, not
  replaced).

Everything else in the house — family members on [[Companion-OS]],
unknown voices on guest, duty devices on [[Responder-OS]] — is a
sub-principal defined by what it *can't* do relative to Grizz OS.

## Visual identity

| token | hex | rationale |
| --- | --- | --- |
| canvas | `#0A0B0F` | near-black, home baseline |
| chrome | `#C7CBD1` | cool silver |
| alert  | `#C8102E` | crimson — constant across all tiers |
| accent | `#00A878` | Clan Munro emerald |
| glow   | `#38E0A6` | focus / active state |

## Related canon

- [[Companion-OS]]
- [[Responder-OS]]
- [[SOUL_ANCHOR]]
- [[PRINCIPLES]]
- [[../architecture/TRUST_BOUNDARIES]]
