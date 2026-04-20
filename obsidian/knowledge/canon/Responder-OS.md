# Responder OS — canon

> Status: **seed page** (scope pending operator direction).
> Tier palette: blue / white / gold / black — wired in
> [[../../../Jarvis/Shared/Sources/JarvisShared/JarvisBrandPalette.swift|JarvisBrandPalette.responderOS]].

## What it is

Responder OS is the third tier in the Jarvis family of skins, alongside
[[Grizz-OS]] (operator) and [[Companion-OS]] (family). It is the
first-responder / field-integration tier — the skin Jarvis wears when the
surface it's rendering to belongs to a working medic, firefighter, officer,
or dispatch operator rather than a household occupant.

Same binary. Same soul-anchor. Same trust model. Different accent, different
capability matrix, different escalation defaults.

## Soul (operator directive, canon)

> "Responder OS is like 1900 Grizz. It's the operating system when it
> puts on a uniform and realizes, oh, I got to go to work and be a good
> boy today, because we got to keep food on the table."

Responder OS is Jarvis clocked-in. Uniform on, language clean, personality
compressed into the parts a chain of command and a liability framework
can live with. Not a different soul — the same soul in a posture that
keeps the lights on and the people served. The gold-on-blue palette is
the visual equivalent of a tucked-in shirt.

## Scope boundary

The operator directive is explicit: **we cannot build Responder Hub yet.**
Hub is the upstream coordination / dispatch surface and needs partnerships
we don't have. Everything downstream of Hub — the on-device integrations,
the per-role surfaces, the data contracts — *is* in scope as the ecosystem
gets built out.

What this means in practice for the current pass:

- ✅ Palette wired through [[JarvisBrandPalette]] so any UI surface can
  render Responder OS immediately when a `.responder` principal is bound.
- ⏸ `Principal.responder(role:)` enum case: **deferred** — waiting on
  role taxonomy from the operator (medic / fire / law / dispatch / etc.).
- ⏸ ResponderCapabilityPolicy: deferred — follows the Companion policy
  shape but with duty-oriented allow-set (scene status, lights, radio,
  presence, dispatch acknowledge) rather than household allow-set.
- ⏸ Responder Hub: blocked, out of scope until partnerships materialize.

## Visual identity

| token | hex | rationale |
| --- | --- | --- |
| canvas | `#05070C` | near-black; night-shift legibility, zero glare |
| chrome | `#F4F6FA` | sterile white; high-contrast duty UI |
| alert  | `#C8102E` | crimson — constant across all tiers by canon |
| accent | `#0B5FFF` | duty blue |
| glow   | `#F2B707` | gold — priority / focus state, not emergency |

Crimson alert is identical across Grizz OS / Companion OS / Responder OS
by design. A crimson signal means the same thing everywhere in the house
and everywhere in the field.

## Integration surfaces — cross-tier, not Responder-only

These modules already exist in the JarvisCore stack and are used today under
[[Grizz-OS]]. Responder OS doesn't introduce new subsystems; it introduces a
duty-mode **skin** and policy overlay on the same plumbing. The work to
reach 2026 standards is to bring these existing modules up to the SPEC-007
/ 008 / 009 bar (principal threading, fail-closed defaults, canon-gated
regressions) so the same code serves all three tiers cleanly.

| module (existing) | path | 2026-standards work |
| --- | --- | --- |
| Presence detection | [[../../../Jarvis/Sources/JarvisCore/Network/PresenceDetector.swift\|PresenceDetector]] | thread `Principal` through event emission; tier-aware sensitivity |
| Wi-Fi / CSI scanning | [[../../../Jarvis/Sources/JarvisCore/Network/WiFiEnvironmentScanner.swift\|WiFiEnvironmentScanner]] | fail-closed on missing entitlements; redact SSIDs below operator tier |
| Telemetry store | [[../../../Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift\|TelemetryStore]] | principal-tagged rows; evidence chain ID on every append |
| AO×4 probe | [[../../../Jarvis/Sources/JarvisCore/Telemetry/AOxFourProbe.swift\|AOxFourProbe]] | tier gating on probe emission — duty mode may need higher cadence |
| Convex sync | [[../../../Jarvis/Sources/JarvisCore/Telemetry/ConvexTelemetrySync.swift\|ConvexTelemetrySync]] | principal-scoped partitions in Convex; no cross-principal leakage |
| Presence arrival | [[../../../Jarvis/Sources/JarvisCore/Interface/PresenceEventRouter.swift\|PresenceEventRouter]] / [[../../../Jarvis/Sources/JarvisCore/Interface/GreetingOrchestrator.swift\|GreetingOrchestrator]] | greeting palette + voice persona branches on resolved principal |
| Soul-anchor | [[../../../Jarvis/Sources/JarvisCore/SoulAnchor/SoulAnchor.swift\|SoulAnchor]] | evidence-chain ID already present; add tier witness field |
| Voice approval gate | [[../../../Jarvis/Sources/JarvisCore/Voice/VoiceApprovalGate.swift\|VoiceApprovalGate]] | Responder tier needs duty-session allow-list distinct from Companion |
| Capability policy | [[../../../Jarvis/Sources/JarvisCore/Interface/CompanionCapabilityPolicy.swift\|CompanionCapabilityPolicy]] | generalize to `TierCapabilityPolicy` — one engine, three matrices |
| Tunnel server | [[../../../Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift\|JarvisHostTunnelServer]] | already principal-aware (SPEC-009); add responder tier dispatch |
| Cockpit / UI surfaces | `Jarvis/Mac`, `Jarvis/Mobile`, `Jarvis/Watch`, `Jarvis/TV` | render from [[../../../Jarvis/Shared/Sources/JarvisShared/JarvisBrandPalette.swift\|JarvisBrandPalette]]; no hardcoded hex |

Explicitly **not** in this pass:

- Responder Hub upstream API.
- Any network call to third-party dispatch systems.
- Any cross-agency data exchange.
- Net-new modules — everything above is hardening of modules that already ship.

## Related canon

- [[Grizz-OS]]
- [[Companion-OS]]
- [[../concepts/Aragorn-Class]]
- [[../architecture/TRUST_BOUNDARIES]]
- [[../research/operator-mind/Memo-deep research for equitable partnerships-responderOS|Operator memo: Responder OS equitable partnerships]]

## Open questions (for operator)

1. Role taxonomy — what are the canonical roles? (medic / fire / law /
   dispatch / instructor / other?)
2. Per-role capability matrix — does a medic get different allow-set than
   a firefighter on the same binary?
3. Duty-session boundary — does Responder OS only render while an active
   duty session is bound, or is it the persistent skin on an issued device?
4. Pairing model — does a responder device also carry a personal Grizz /
   Companion identity, or is it single-principal?
5. Evidence retention — local-only, or mirrored into the operator's
   evidence corpus?

Answers land here and propagate into `Principal.responder(...)` and
`ResponderCapabilityPolicy` in a dedicated follow-up commit.
