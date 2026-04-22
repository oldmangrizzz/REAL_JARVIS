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

## Watch (operator) — the wrist surface

**Source:** AMBIENT-002-FIX-01, landed 2026-04-22.

The Apple Watch is a first-class **operator surface**, not a new tier.
It is a hardware-bound extension of `.operatorTier`: utterances captured
on the watch still resolve to `grizz` for SPEC-009 witness and capability
gating. The watch does not get its own `Principal` case.

What the watch *does* get is its own **role + authentication policy +
ambient-gateway routing identity**, so host security can tell "this
registration came from Grizz's wrist" apart from "this came from Grizz's
mac".

| Surface        | Role string              | Auth policy                                   | Allowed unregistered? |
|----------------|--------------------------|-----------------------------------------------|-----------------------|
| Mac / cockpit  | `voice-operator`         | `.deviceOwnerAuthenticationWithBiometrics`    | No                    |
| Apple Watch    | `watch`                  | `.deviceOwnerAuthentication` (wrist+passcode) | No                    |
| Mobile cockpit | `mobile-cockpit`         | `.deviceOwnerAuthenticationWithBiometrics`    | No                    |

Key host-plane invariants (all enforced by tests in
`JarvisCoreTests/Host/`):

- `"watch"` is in `JarvisHostTunnelServer.authorizedSources` alongside
  `voice-operator`, `mobile-cockpit`, `obsidian-command-bar`, `terminal`.
- `"watch"` is in `TunnelIdentityStore.privilegedRoles`, so an unsigned
  bootstrap registration from a watch is rejected the same way an
  unsigned `voice-operator` bootstrap is. There is no silent
  "unregistered watch → guest" fallback — watch ⇒ operator-bound or
  rejected.
- `BiometricTunnelRegistrar.registerWatch(deviceID:keyID:)` runs the
  wrist-attested auth path before signing, then hands the signed
  registration to `TunnelIdentityStore.register`. Same vault, same HMAC
  chain, different LA policy.

### Responder as the watch's primary surface

When `.responder(role:)` is active — i.e., Jarvis has clocked in to EMS
duty — the watch becomes the **primary I/O surface**, not the mac.
Ambient-audio gateway route transitions (`onWrist`, `offWrist`,
`pairedPhone`, `unpairedDegraded`, `responderOverride`) are telemetered
on the `ambient_audio_gateway` SPEC-009 chain so the post-call witness
can answer:

1. *Was the wrist surface attached when the responder utterance was
   captured?*  — from `route == .onWrist` rows.
2. *Did the gateway fall back to phone-paired audio mid-call?*  — from
   `transition: onWrist → pairedPhone` rows with a `latencySLAMiss` row
   nearby.
3. *Did the operator invoke the cockpit emergency override?*  — from
   `route == .responderOverride` rows; operator-only, not a role
   elevation for the responder themselves.

The responder primary surface choice is a **UX / routing decision**, not
a trust elevation: tier gating still flows through the normal
`Principal` resolution. The watch in responder mode is still bound to
`.operatorTier` or `.responder(role:)` as diarized; nothing on the watch
grants a role it did not already have.

