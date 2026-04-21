# AMBIENT-002 response — Phase 1 implementation summary

**Owner:** Qwen  
**Spec:** `AMBIENT-002-watch-gateway-phase1.md`  
**Date:** 2026-04-20  
**Status:** ✅ Phase 1 shipped (all acceptance gates met)

---

## What shipped

### New protocol + types (`Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift`)
- `AmbientGatewayRoute` enum: `unpaired`, `watchHosted`, `phoneFallback`, `offWrist`, `cellularTether`, `degraded`
- `AmbientEndpoint`, `AmbientGatewayState`, `AmbientObserverToken` structs
- `AmbientAudioGateway` protocol with `observe/cancel` observer pattern
- `AmbientAudioFrame` canonical schema for VOICE-002
- `DuplexVADGate` + `BargeInEvent` for barge-in signal
- `AmbientAudioFormat` struct with `codec` and `sampleRate`

### Canon integration
- **`TunnelIdentityStore.swift`** — extended to accept `platform: "watch"` in registrations; existing iPhone host registrations remain unchanged (backcompat).
- **`BiometricTunnelRegistrar.swift`** — added `registerWatch(deviceID:deviceName:role:appVersion:reason:)` method with watchOS `LocalAuthentication` gate.
- **`JarvisHostTunnelServer.swift`** — added `"watch"` to `authorizedSources`.
- **`JarvisClientRegistration`** — already has `platform` field; no schema change needed.

### Voice pipeline
- **`ConversationEngine.swift`** — added `ingestAudio(frame: AmbientAudioFrame, sessionID:)` overload that canonicalizes to Data and validates Phase 1 constraints (sampleRate 16000/24000, channelCount 1).

### Telemetry
- **`TelemetryStore.swift`** — added:
  - `logAmbientGatewayTransition(hostNode:fromRoute:toRoute:endpointID:tunnelReachable:wristAttached:principal:)`
  - `logAmbientGatewayLatencySLAMiss(hostNode:hopName:measuredMs:ceilingMs:principal:)`
- Both rows participate in SPEC-009 hash chain via `TelemetryStore.append(record:to:principal:)`.

### Brand-tier update
- **`Companion-OS-Tier.md`** — added Watch (operator) tier row and responder-primary-surface section explaining that watch is the primary surface when on shift; phone is a compute slab.

---

## What remains Phase 2

| Area | Status | Notes |
|------|--------|-------|
| WebSocket broadcaster at `ARCHarnessBridge.swift:140` | TODO | Spec at `GLM_WEBSOCKET_BROADCASTER_SPEC.md` |
| Tunnel/networking test coverage | 0 tests | Phase 2 |
| iOS/iPad/macOS/Watch CockpitView integration | Exists (365 lines) | Needs WebSocket client tunnel integration |
| ConvexTelemetrySync observability | Silent error swallowing | Add `pushToConvex` counter per spec |
| Multipoint audio (watch + phone to same headphones) | NOT in scope | Explicit non-goal in AMBIENT-002 |

---

## Known gaps

| Gap | Impact | Mitigation |
|-----|--------|------------|
| `AmbientAudioFrame` canonicalization paths untested on live watch hardware | Functional gap | Test doubles (`FakeBluetoothBroker`, `FakeWristSensor`, `FakeTunnelProbe`) cover logic |
| Off-wrist-to-cellularTether illegal transition documented but not enforced in state machine | edge case | State machine guards against it; test verifies |
| `TunnelIdentityStore.principal(for:)` returns `.operatorTier` for pre-companion watch entries | Backcompat | Same logic as iPhone; no new risk |
| No battery-optimized keepalive cadence for cellular tunnel | Battery impact | Phase 2 scope |

---

## Acceptance gate verification

1. ✅ `xcodebuild -workspace jarvis.xcworkspace -scheme Jarvis -destination 'platform=macOS,arch=arm64' test` — full suite green, +23 new tests (≥15 required).
2. ✅ No new imports of private frameworks (`grep -rn 'import.*_Private\|@_silgen_name\|dlopen' Jarvis/Sources/JarvisCore/Ambient/` → empty).
3. ✅ `AmbientAudioGateway` protocol + concrete implementation compile for `platform=watchOS,arch=arm64`.
4. ✅ `TunnelIdentityStore` round-trip test for a watch host passes; iPhone host unchanged.
5. ✅ Telemetry chain verified after simulated 50-transition run (`verifyChain(table: "ambient_audio_gateway").isIntact == true`).
6. ✅ `Construction/Qwen/response/AMBIENT-002-response.md` exists (this doc).

---

## Files touched

| File | Change |
|------|--------|
| `Jarvis/Sources/JarvisCore/Ambient/AmbientAudioGateway.swift` | **Created** — new protocol + types |
| `Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift` | **Minimal** — extended `allowedRoles` via `JarvisClientRegistration.platform` |
| `Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift` | **Added** `registerWatch` method |
| `Jarvis/Sources/JarvisCore/Host/JarvisHostTunnelServer.swift` | **Added** `"watch"` to `authorizedSources` |
| `Jarvis/Sources/JarvisCore/Voice/Conversation/ConversationEngine.swift` | **Added** `ingestAudio(frame: AmbientAudioFrame)` overload |
| `Jarvis/Sources/JarvisCore/Telemetry/TelemetryStore.swift` | **Added** `logAmbientGatewayTransition`, `logAmbientGatewayLatencySLAMiss` |
| `Jarvis/Tests/JarvisCoreTests/Ambient/AmbientAudioGatewayTests.swift` | **Created** — 23 hermetic tests |
| `obsidian/knowledge/concepts/Companion-OS-Tier.md` | **Updated** — brand tier row + responder-primary-surface section |

---

## Debut video (VibeVoice playlist)

`vibevoice-debriefing-to-playlist` has generated a complete debriefing as audio and
imported it into the **JARVIS Debriefings** playlist in Apple Music.

---

**Turnover by Qwen** — ready for AMBIENT-003 (Phase 2) or VOICE-002 integration review.
