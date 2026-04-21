# Companion OS Tier

**Canon:** the four-tier `Principal` model that brands every Jarvis surface
and gates every capability. Server-side resolved — clients never assert
their own principal.

## The four tiers

| Tier                  | `Principal` case          | `tierToken`              | Brand subtitle                      |
|-----------------------|---------------------------|--------------------------|-------------------------------------|
| **Grizz OS**          | `.operatorTier`           | `grizz`                  | powered by Grizz OS                 |
| **Companion OS**      | `.companion(memberID:)`   | `companion:<id>`         | powered by Companion OS             |
| **Guest (fallback)**  | `.guestTier`              | `guest`                  | powered by Companion OS (guest)     |
| **Responder OS**      | `.responder(role:)`       | `responder:<role>`       | powered by Responder OS             |

**Note:** In the brand hierarchy, the watch device is considered the primary *Responder* surface, handling real‑time interactions, while the phone acts mainly as a compute slab backing the watch’s operations.

Source: [[codebase/modules/Host|Principal.swift]] (in `JarvisShared`).

## Operator canon (verbatim)

> **Grizz OS** — "like me. Raw, unredacted, completely in your face. Full
> function and full tilt." Operator at home.
>
> **Companion OS** — "how you act in front of your friends and your
> family." Socialized Jarvis, scoped authority, same warmth.
>
> **Responder OS** — "1900 Grizz. The operating system when it puts on a
> uniform and realizes, oh, I got to go to work and be a good boy today."
> Jarvis clocked-in.

## Resolution sources (always server-side)

- **Tunnel registration** — `TunnelIdentityStore.validate` maps device →
  `DeviceIdentity.principal` via HMAC-proof over
  `deviceID:role:nonceISO`. See [[codebase/modules/Host]].
- **Utterance diarization** — speaker identification resolves voice →
  principal at capture time, not device time. A registered Companion
  device speaking a guest voice drops to `.guestTier` for that turn.
- **OSINT query rewrite** — every OSINT source accepts the resolved
  principal and may strip / scope results. See [[codebase/modules/OSINT]].

The `Principal` is stamped into every `TelemetryStore.append` row as
`principal = tierToken`, giving SPEC-009 evidence chains a "who was
Jarvis serving when this was emitted" witness.

## Responder sub-levels

`.responder(role:)` carries a `ResponderRole` (`emr` < `emt` < `aemt` <
`emtp`) with ordinal `certLevel` 1–4. **Responder Jarvis is advocacy +
situational awareness, never clinical execution.** Role level gates the
*depth* of protocol and documentation surfaces, never what clinical act
gets performed. Mission: empowerment, not replacement.

## Fail-closed defaults

- Unknown speaker → `.guestTier`, narrowest read-only surface.
- Unregistered device on a non-privileged role may be allowed if
  `TunnelIdentityStore.allowUnregisteredNonPrivileged` is true; the
  `voice-operator` role is never allowed unregistered.
- Biometric-bound surfaces (see [[codebase/modules/Host]] —
  `BiometricIdentityVault`, `BiometricTunnelRegistrar`) require the
  device's private identity key to be unlocked by LocalAuthentication
  before signing the registration; vault loss ⇒ no Grizz OS claim.

## Brand palette per tier

Resolved through `NavigationDesignTokens.color(in: theme, for: principal)`
(dual-theme). Responder tier EMS cert-level blues are verified in
`JarvisPaletteHexTests`. Grizz OS uses the operator palette;
Companion OS the family palette; Guest inherits Companion with a
muted surface; Responder gets the EMS blues scaled by cert level.

## Related
- [[codebase/modules/Host]] — identity stores, biometric vault, registrar
- [[codebase/modules/OSINT]] — principal-scoped query rewriting
- [[codebase/modules/Credentials]] — capability gating
- [[codebase/modules/Interface]] — palette + cockpit branding
- [[concepts/Voice-Approval-Gate]] — operator-only veto on companion asks