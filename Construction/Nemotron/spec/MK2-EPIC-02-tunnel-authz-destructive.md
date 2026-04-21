# MK2-EPIC-02 — Tunnel Authorization + Destructive Guardrails

**Lane:** Nemotron (verification / red-team)
**Parent:** `MARK_II_COMPLETION_PRD.md` §4; consolidates `PRODUCTION_HARDENING_SPEC.md` SPEC-007 + SPEC-008 + audits SPEC-009/010/011
**Depends on:** MK2-EPIC-01 (need all targets green to run tunnel tests across surfaces)
**Priority:** P0
**Canon sensitivity:** MEDIUM — authorization touches voice-gate & operator-on-loop boundaries

---

## Why

`PRODUCTION_HARDENING_SPEC.md` SPEC-007 identified: **client self-asserts its role** in the tunnel handshake. A compromised client could claim `role=macHost` and receive host-only messages. SPEC-008 identified: **no two-man rule on destructive mesh actions** — a single voice command can wipe display configuration.

Mark II ships with bounded authority or it doesn't ship.

Additionally, SPEC-009 (Pheromone engine thread safety), SPEC-010 (MasterOscillator deadlock), SPEC-011 (tunnel buffer accumulation) need **verification that they are closed**; if any is still open, patch in this epic.

## Scope

### In

1. **Server-issued role tokens.**
   - `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` — on handshake, server inspects client-presented shared secret, assigns role from `CapabilityRegistry.clientIdentity(<client_pub>)`, returns a signed role token (HMAC-SHA256 with host key, 8 h TTL).
   - Client MUST present token on every subsequent frame. Absence or mismatch → server drops connection and logs `tunnel.auth.denied` telemetry.
   - Role mapping config: `WorkspacePaths.capabilityConfigURL` — add `clientRoles: [{publicKeyHex, role}]`.

2. **Destructive command guardrails.**
   - Extend `JarvisRemoteAction` (in `Shared/JarvisShared/TunnelModels.swift`) with `isDestructive: Bool` computed property: `true` for actions matching `displayWipe`, `capabilityDelete`, `voiceGateRevoke`, `memoryPurge`, `soulAnchorRotate`.
   - `DisplayCommandExecutor.execute(_:)` — if `action.isDestructive` and incoming frame lacks `X-Confirm-Hash: <sha256(action.canonical)>` header, reject with `destructive_requires_confirm` error.
   - PWA + Mac cockpit UI MUST gate destructive actions behind a "type to confirm" modal that computes the hash locally and attaches the header.

3. **Verify and fix legacy bugs:**
   - SPEC-009 Pheromone thread safety: run `ThreadSanitizer` on `PheromoneEngineTests`. If race detected, wrap mutable state in `NSLock` or convert to actor. Add regression test.
   - SPEC-010 Oscillator deadlock: audit `MasterOscillator.subscribe(_:)` and `phaseLockMonitor.record(_:)` for re-entrant lock paths. Add reproducer test from the SPEC-010 description. Fix if reproducible.
   - SPEC-011 Tunnel buffer accumulation: confirm `JarvisTunnelClient` drains its receive buffer on each frame. Add a fuzz test that sends 10k frames and asserts memory stays bounded.

4. **Telemetry:**
   - New events: `tunnel.auth.granted`, `tunnel.auth.denied`, `destructive.confirmed`, `destructive.rejected`, `legacy.spec009.patched` (and 010/011 if patched).
   - Witness-hash emission unchanged.

### Out

- Do NOT introduce mTLS (future work). Bearer-token + host-HMAC is the Mark II bar.
- Do NOT touch `VoiceApprovalGate` logic.
- Do NOT change the wire format beyond the new header and token field — downstream clients (PWA, WebXR) must keep working with a minor bump.

## Acceptance Criteria

- [ ] New test `TunnelAuthTests.swift` ≥ 6 cases: valid token pass, missing token reject, wrong-role reject, expired-token reject, role-demotion on secret rotation, signed-token tamper detection.
- [ ] New test `DestructiveGuardrailTests.swift` ≥ 4 cases: destructive without header reject, with correct header allow, with wrong-hash header reject, non-destructive unaffected.
- [ ] ThreadSanitizer run logged in `Construction/Nemotron/response/MK2-EPIC-02-tsan.log` — 0 races in PheromoneEngineTests.
- [ ] Wire bump documented in `Construction/Nemotron/response/MK2-EPIC-02-wire-v2.md`.
- [ ] PWA and Mac cockpit updated with confirm modal; smoke test at `scripts/smoke/destructive-confirm-ui.sh` opens PWA headlessly (Playwright or curl-based) and validates the modal fires.
- [ ] `xcodebuild test -scheme all` remains green; total tests ≥ `prev + 10`.

## Invariants

- PRINCIPLES §1.3 (operator-on-loop): destructive actions require confirmation; non-destructive remain in standing protocol.
- No `@unchecked Sendable` additions.
- Token signing uses existing `TunnelCrypto` primitives where possible; if not, justify the cryptographic choice in the response doc with cite to a standard.

## Threat Model (for Fury to attack)

- T1: Attacker steals client device, attempts to escalate role. → token is role-scoped and host-signed; role claim from client is ignored.
- T2: Replay: attacker captures a destructive frame and replays. → header contains action canonical hash; duplicate frames must carry a nonce tracked in a 15-min sliding window (add `Host/DestructiveNonceTracker.swift`).
- T3: Token theft: JWT-like leak. → short TTL (8h) + rotation on voice gate re-approval event.

## Artifacts

- Modified: `Host/JarvisHostTunnelServer.swift`, `MobileShared/JarvisTunnelClient.swift`, `Shared/TunnelModels.swift`, `Interface/DisplayCommandExecutor.swift`, `Interface/CapabilityRegistry.swift`, `pwa/index.html`, `Jarvis/Mac/Sources/JarvisMacCore/*`.
- New: `Host/DestructiveNonceTracker.swift`, `Tests/TunnelAuthTests.swift`, `Tests/DestructiveGuardrailTests.swift`, `scripts/smoke/destructive-confirm-ui.sh`.
- Response: `Construction/Nemotron/response/MK2-EPIC-02.md` including threat-model walkthrough.
