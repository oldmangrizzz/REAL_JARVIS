# Companion OS — canon

> Status: **active** (SPEC-009 landed).
> Tier palette: black / silver / crimson / teal-cyan — wired in
> [[../../../Jarvis/Shared/Sources/JarvisShared/JarvisBrandPalette.swift|JarvisBrandPalette.companionOS]].

## What it is

Companion OS is the family tier of the Jarvis skin family. It's what
Jarvis wears when the bound
[[../../../Jarvis/Shared/Sources/JarvisShared/Principal.swift|Principal]]
resolves to `.companion(memberID:)` — wife and daughter, each with their
own member ID, same warmth, scoped authority.

Same binary as [[Grizz-OS]] and [[Responder-OS]]. Same soul-anchor. Same
"warmth without servility" personality contract. What differs is the
capability matrix and the accent color.

## Soul (operator directive, canon)

> "Companion OS is how you act in front of your friends and your family."

The tier is not a reduced Jarvis, it's a *socialized* Jarvis — the same
soul choosing manners because the people in the room are loved, not
because they're being managed. Teal instead of emerald, scoped instead
of unlimited, but the warmth is the same warmth.

## Historical note

The name "CompanionOS" was originally reserved in
[[../../../CANON/corpus/COMPANIONOS_INTEGRATION.md|COMPANIONOS_INTEGRATION.md]]
for the "Body" layer to H.U.G.H.'s "Brain." That original usage is
compatible — the family-tier skin *is* the body layer from the operator's
perspective, rendered into a constrained permission surface.

## Capability matrix (SPEC-009)

Enforced by
[[../../../Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift|CompanionCapabilityPolicy]]
at both the voice-router boundary and the tunnel-command boundary.
Fail-closed: missing principal binding → `.guestTier` → near-total lockout.

| capability | operator (Grizz) | companion (family) | guest |
| --- | --- | --- | --- |
| destructive voice verbs (shutdown / self-heal / reseed) | allow | **deny** | **deny** |
| home / lights / thermostat | allow | allow | **deny** |
| status / ping query | allow | allow | allow |
| skill invocation | allow | allow | **deny** |
| identity store edits | allow | **deny** | **deny** |

Safety signals (crimson) read identically across tiers — the tier
downgrade does not silence alerts.

## Visual identity

| token | hex | rationale |
| --- | --- | --- |
| canvas | `#0A0B0F` | shared with Grizz OS |
| chrome | `#C7CBD1` | shared with Grizz OS |
| alert  | `#C8102E` | crimson — constant across all tiers |
| accent | `#00B8C4` | teal-cyan (swapped from emerald per operator) |
| glow   | `#5FE5EE` | focus / active state |

Guest variant dims chrome + accent so an unregistered speaker can tell at
a glance they're in a limited context.

## Related canon

- [[Grizz-OS]]
- [[Responder-OS]]
- [[SOUL_ANCHOR]]
- [[../architecture/TRUST_BOUNDARIES]]
- [[../concepts/SPEC-009]]
