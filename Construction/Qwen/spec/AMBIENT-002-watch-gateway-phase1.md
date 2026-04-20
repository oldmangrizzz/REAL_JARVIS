# AMBIENT-002 — Watch-First Audio Gateway, Phase 1 Implementation

**Predecessor:** `AMBIENT-001-watch-as-audio-gateway.md` (research spec) →
`Construction/Qwen/response/AMBIENT-001-response.md` (Qwen's research output).

**This spec is implementation, not research.** Write code, write tests, wire
canon. Everything in here is Phase 1 only — public APIs, App Store clean,
no private frameworks. Phase 2 and Phase 3 scope is explicitly forbidden
until a separate AMBIENT-003 spec lifts the gate.

**Owner:** Qwen.  **Lane:** watchOS audio gateway + ambient spatial framing.
Adjacent non-overlapping lanes: Gemini (voice synthesis / F5-TTS), GLM
(navigation / NAV-001), Copilot (orthogonal test coverage + spec logic).

---

## 1 · Goals

Build the minimum viable watch-as-audio-gateway that validates the
corrected topology Qwen confirmed in AMBIENT-001:

1. Headphones pair **directly** to the watch. Watch initiates the BT
   connection. Phone is not in the audio path.
2. Watch captures voice via built-in mic → SFSpeechRecognizer → tunnel to
   Jarvis host.
3. Session is watch-identity rooted. Off-wrist freezes it within ~300ms.
4. Cellular tunnel when phone is absent; WiFi/phone-mesh fallback when
   phone is in range.
5. Every state transition of the gateway is witnessed in telemetry under
   a new `ambient_audio_gateway` table that participates in the SPEC-009
   hash chain.

**Non-goals (explicit, do NOT chase):**

- Multipoint audio (watch + phone to same headphones simultaneously).
- LE Audio / LC3 / Auracast broadcast source.
- H1/H2 mic passthrough from AirPods to watch mic fusion.
- Watch-relayed phone audio (phone streaming into watch that re-broadcasts).
- Replacing CarPlay. CarPlay stays — watch is the persistent layer
  across car↔sidewalk↔ambulance↔home.
- Replacing HomePod mini as in-room voice surface.
- Any private framework. If you reach for `nearbyd`, `sharingd`,
  `MediaRemote`, `BluetoothManager.framework`, or any SPI header — stop
  and escalate. Phase 2 territory.

---

## 2 · Deliverable shape

All of the following, delivered in one pass so review is atomic:

1. **New protocol + types** in `Jarvis/Sources/JarvisCore/Ambient/`
   (create the directory). See §3.
2. **watchOS implementation** of the protocol.
3. **Canon integration edits** to `TunnelIdentityStore.swift`,
   `BiometricTunnelRegistrar.swift`, and the voice pipeline entry point.
   See §4.
4. **Telemetry witness wiring** — new `ambient_audio_gateway` table,
   every state transition emits a principal-witnessed row. See §5.
5. **Test suite** — hermetic, no live BT required. See §6.
6. **Docs update** — brand-tier model reflects watch-primacy for
   responder-OS. See §7.
7. **Turnover note** at `Construction/Qwen/response/AMBIENT-002-response.md`
   with a "what shipped / what's still Phase 2 / known gaps" summary the
   operator can read top-to-bottom in 60 seconds.

---

## 3 · API surface (new)

Create `Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift`.
Lock this final shape — the sketch from AMBIENT-001 §4 was provisional.

```swift
public enum AmbientGatewayRoute: String, Codable, Sendable {
    case unpaired              // no BT peer
    case watchHosted           // watch owns BT link to headphones (target state)
    case phoneFallback         // phone mediates because watch can't host this headphone
    case offWrist              // wrist-detect lost, session frozen
    case cellularTether        // watch has tunnel, phone absent
    case degraded              // tunnel down, local buffering
}

public struct AmbientEndpoint: Codable, Sendable, Equatable {
    public let deviceID: String           // BT identifier, opaque
    public let displayName: String        // "AirPods Pro", "Bose QC 45"
    public let supportsA2DP: Bool
    public let supportsHandsFreeMic: Bool // usually false for generic BT
}

public struct AmbientGatewayState: Codable, Sendable, Equatable {
    public let route: AmbientGatewayRoute
    public let activeEndpoint: AmbientEndpoint?
    public let availableEndpoints: [AmbientEndpoint]
    public let wristAttached: Bool
    public let tunnelReachable: Bool
    public let updatedAt: Date
}

public protocol AmbientAudioGateway: AnyObject, Sendable {
    var currentState: AmbientGatewayState { get }
    func reassign(to endpointID: String) throws
    func refreshEndpoints() async
    func observe(_ handler: @escaping @Sendable (AmbientGatewayState) -> Void) -> AmbientObserverToken
    func cancel(_ token: AmbientObserverToken)
}

public struct AmbientObserverToken: Hashable, Sendable { /* opaque UUID */ }
```

**Rules:**
- All types `Sendable`. No class-bound mutable state leaks across
  concurrency domains.
- `currentState` is a snapshot; observers get push updates. No polling.
- `reassign` throws `JarvisError.invalidInput` for unknown endpoint IDs
  and `JarvisError.processFailure` for BT framework errors.
- Observer handler invoked on a detached actor — never the main queue —
  so responder-OS UI code can't accidentally block the gateway.

---

## 4 · Canon integration

### 4.1 · `TunnelIdentityStore.swift`

Currently phone-centric host type. Extend:

- Add `watch` to whatever enum tracks host kind (check the file for the
  current identifier — don't invent one, match the existing style).
- `TunnelHost.watch(deviceID:)` case carries the Secure-Enclave-attested
  watch identifier.
- Registration payload for a watch host must include the Qwen-signed
  proof from `JarvisTunnelCrypto.signRegistration` with `role: "watch"`.
- Existing phone registrations must continue to verify. Back-compat is
  mandatory — don't break the iPhone tunnel.

### 4.2 · `BiometricTunnelRegistrar.swift`

- New branch: `registerWatch(deviceID:sealedProof:)`.
- Watch Secure Enclave path: use `LocalAuthentication` on watchOS 10+ to
  gate the signing (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`).
  Do NOT reach into SEP directly; Apple-public `CryptoKit`
  `SecureEnclave.P256.Signing.PrivateKey` is sufficient.
- Phone-rooted registrar stays untouched for operator's iPhone path.

### 4.3 · Voice pipeline

Do **not** modify synthesis (that's Gemini's lane) or recognition model
selection (also Gemini). Only:

- Accept a new audio framing source type `AmbientAudioFrame` with fields
  `{sampleRate, pcmData, captureTimestamp, routeHint: AmbientGatewayRoute}`.
- The existing ingest point in `Voice/` gains an overload accepting
  `AmbientAudioFrame` that canonicalizes to the current internal frame
  type. No behavior change for non-ambient callers.

### 4.4 · Brand-tier doc

`obsidian/knowledge/concepts/Companion-OS-Tier.md` — add a short section:
"Responder-OS primary surface is the watch when the operator is on shift.
The phone is a compute slab, not a gateway. This is a canon
update, not a preference." Cross-link AMBIENT-001 response + this spec.

---

## 5 · Telemetry + SPEC-009 chain

New table: `ambient_audio_gateway`.

Every `AmbientGatewayState` transition appends one row:

```json
{
  "timestamp": "…",
  "principal": "responder|grizz|guest|companion",
  "event": "route_change|endpoint_change|wrist_change|tunnel_change",
  "fromRoute": "watchHosted",
  "toRoute": "offWrist",
  "endpointID": "…",
  "tunnelReachable": false,
  "prevRowHash": "…",
  "rowHash": "…"
}
```

Rules:

- Writes go through `TelemetryStore.append(record:to:principal:)` so the
  SPEC-009 hash chain is preserved automatically.
- Principal binding is whatever tier owns the active Jarvis session.
  Off-wrist transitions use the frozen session's last-known principal.
- Do NOT add a new telemetry API. Reuse `append`. If you find yourself
  writing a new JSONL writer, stop.

---

## 6 · Tests (non-negotiable)

All hermetic. No live BT, no sleep-based assertions, no network. Use a
`FakeBluetoothBroker` + `FakeWristSensor` + `FakeTunnelProbe` injected
into the gateway constructor. The protocol stays the same; only the
watchOS concrete type wires the real implementations.

Required coverage:

1. **State machine transitions** — every legal pair in the 6-route enum.
   At minimum:
   - `unpaired → watchHosted` on endpoint discovery + successful pair.
   - `watchHosted → offWrist` on wrist-detect false, within one tick.
   - `offWrist → watchHosted` on wrist-reattach + biometric pass.
   - `watchHosted → phoneFallback` when endpoint reports
     `supportsA2DP=false` but phone advertises it.
   - `watchHosted → degraded` when tunnel probe fails.
   - `degraded → watchHosted` on tunnel recovery.
2. **Illegal transition rejected** — direct `offWrist → cellularTether`
   without re-auth should throw or no-op, whichever the state machine
   doc picks. Pick one, document it, test it.
3. **Telemetry row per transition** — read back from the
   `ambient_audio_gateway` jsonl, assert one row per transition, assert
   `verifyChain(table:)` reports intact after a 20-transition burst.
4. **Principal binding** — responder-tier session records `"responder"`
   in row; guest-tier session records `"guest"`; off-wrist freeze
   preserves the last-known principal.
5. **Observer contract** — `observe` fires once per transition, never
   fires for no-op re-sets (same state twice in a row), and survives a
   1000-transition fuzz without retain cycles (use `weak var` in the
   test harness to assert deallocation).
6. **Reassign errors** — unknown endpoint → `.invalidInput`; broker
   error → `.processFailure`.
7. **Concurrency** — 200 concurrent `refreshEndpoints()` calls produce a
   single coherent `currentState`; no data race under TSan.

Test file: `Jarvis/Tests/JarvisCoreTests/Ambient/AmbientAudioGatewayTests.swift`.
Create the `Ambient/` subdirectory. Use `makeTestWorkspace()` helper for
paths. `@testable import JarvisCore`.

Target: **≥ 15 tests**, all green. Full suite must stay green.

---

## 7 · Acceptance gate — "Phase 1 done" means

A reviewer running through the following must answer yes to all:

1. `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination
   'platform=macOS,arch=arm64' test` — full suite green, +≥15 new tests.
2. No new imports of private frameworks. Check with:
   `grep -rn 'import.*_Private\|@_silgen_name\|dlopen' Jarvis/Sources/JarvisCore/Ambient/`
   must be empty.
3. `AmbientAudioGateway` protocol + one concrete watchOS implementation
   compile for `platform=watchOS,arch=arm64`.
4. `TunnelIdentityStore` round-trip test for a watch host passes, and
   the existing iPhone host round-trip is unchanged.
5. Telemetry chain verified after a simulated 50-transition run —
   `verifyChain(table: "ambient_audio_gateway").isIntact == true`.
6. `Construction/Qwen/response/AMBIENT-002-response.md` exists and names
   every file touched + every deferred item (so the next spec,
   AMBIENT-003, has a clean baseline).

---

## 8 · Risks + escalation

| Risk | Severity | Phase 1 mitigation |
|------|----------|--------------------|
| Some BT headphones refuse to pair to watch without phone priming | Med | Detect, surface `.phoneFallback`, don't crash |
| SFSpeechRecognizer latency > 1500ms on watch hardware | Med | Accept as Phase 1 constraint; Gemini's voice lane owns the latency ask |
| Secure Enclave key material leaks across watch re-pair | High | Re-provision on pair; telemetry row with `event:"identity_reset"` |
| Off-wrist timing flaky (>500ms) on older hardware | Low | Target S9+; document S8 degraded behavior, don't block ship |
| Cellular tunnel drains battery | Med | Phase 1 does not implement adaptive keepalive; it runs the existing tunnel cadence. Battery work is Phase 2 |

**Escalation path:** if any Phase 1 task requires a private API to
ship, STOP. Write a note in the response doc under "Phase 2 escalations"
and move on. Do not ship private-framework code in the Phase 1 branch.

---

## 9 · Coordination notes

- **Gemini** owns voice synthesis and recognition. Do not touch
  `Voice/TTSBackend*`, `F5*`, or any synthesis/recognizer backend.
  Only ingest a new frame type and canonicalize it.
- **GLM** owns navigation (NAV-001). Untouched by this spec.
- **Copilot** owns orthogonal test coverage + spec review. Ping Copilot
  if a canon edit in §4 needs a logic pass before shipping.
- **Operator (Grizz)** signs off on §6 test count + §7 acceptance gate
  before merge.

File-discipline: one PR, one direction. Don't mix AMBIENT work with
navigation or voice-synthesis changes. If the branch grows a NAV or TTS
edit, split it.

— Copilot, coordinating. Operator-approved 2026-04-20.
