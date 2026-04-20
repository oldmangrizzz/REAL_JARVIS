# AMBIENT-001 — Watch-First Audio Gateway (Ecosystem Inversion)

**Operator intent:** flip the Apple audio topology. Today: everything routes through iPhone; phone is the hub, watch is peripheral. Target: **phone becomes the compute slab** (like an iPad), **watch becomes the communications primary** — the audio + comms gateway that walks with the body everywhere, pairing directly to BT/AirPod headphones and carrying a persistent voice tether to Jarvis whether the phone is in the room or not.

This is a deep research + architecture brief. The deliverable is an **end-to-end proposal**, not a prototype: hardware/software constraints, pairing topologies, failure modes, user-journey diagrams, and a staged implementation plan Jarvis can actually build against. Write for operator + implementing engineer (future Qwen + Copilot). No code required — design doc only.

---

## 1 · Problem framing

Ambient computing breaks when the audio root-of-trust is the phone. Phone on counter → AirPods only have a tether when you're within ~10m of it. Phone in pocket → watch gestures still have to route everything back through the phone's Bluetooth stack, wasting battery and adding latency.

We want the **watch** to be:
- The persistent BT audio host for whatever headphones the operator is wearing.
- The primary mic for voice capture (already good in watchOS).
- The gateway between wearables and Jarvis (either via cellular on the watch or via the phone acting as a compute slab over a private link).
- Capable of handoff: when operator walks from car to kitchen, the phone/iPad/Mac in the room should be the compute tier, but the watch stays the **identity + audio + comms anchor**.

Phone becomes:
- A compute slab that is network-reachable but not required for the audio path.
- The canvas for dense visual work (maps, dashboards, writing) that the watch can't host.
- A peer of iPad/Mac/HomePod, not a gatekeeper.

---

## 2 · Research questions Qwen owns

Answer each with sources + current Apple-ecosystem reality as of 2026-Q2.

### 2.1 · Pairing topologies — what is actually possible

1. **Direct watch↔headphones BT pairing.** AirPods already support this for workout scenarios. Investigate:
   - Codec support on Apple Watch (AAC, Opus, SBC, LC3, aptX Adaptive if ever?).
   - Classic BT vs BLE Audio (Auracast, LE Audio, LC3). What does Series 9/10/Ultra 2/Ultra 3 actually negotiate?
   - Can a watch simultaneously host an outgoing audio link AND a 2-way voice channel (SCO/CVSD or LE Audio bidirectional)?
   - Multipoint: can the watch be the **audio host** while phone still owns iMessage/Phone app notifications to the same headphones?
2. **Watch relays phone audio back out over BT (phone as background server, watch as audio I/O).**
   - Is there any public API (CoreBluetooth, AVAudioEngine on watchOS, AudioToolbox, StreamKit) that lets the watch operate as a BT source while the phone streams raw audio to it via the existing paired link (continuity)?
   - What would it take to get a non-public `nearbyd`/`sharingd` path that isn't App Store friendly but IS reasonable for an operator-controlled build?
3. **Third non-Apple headphones (Sony, Bose, Beats non-H1/H2, Pixel Buds, etc.):**
   - Map codec/profile support on Apple Watch vs iPhone.
   - Identify which headphones the watch can host cleanly as an A2DP/LE Audio sink-host without requiring the H1/H2/W1 SoC handshake.
   - Investigate whether we can patch this at the system layer (Jarvis's tunnel) or whether it's a hard limitation of how Apple scopes `MediaPlayer`/`AVAudioSession` routing.

### 2.2 · Bidirectional voice — the hard part

Jarvis needs **latency-bounded, barge-in-capable** voice. Questions:

- On watchOS, does `SFSpeechRecognizer` / `AVAudioEngine` give enough access to run a local VAD + streaming recognizer without wake word relay to the phone?
- Can the watch microphone feed be surfaced to a paired headphone's microphone muted state (so BT headphone mic and watch mic are both live, cherry-picking the better signal)?
- What are the LE Audio roles (broadcast source, unicast client, unicast server) the watch can play? Answer per-generation (S9/S10 have different chips than S8).
- Is CallKit a lever here? Can we fake an "always-on background call" between watch and Jarvis tunnel to keep the BT SCO/voice channel alive?

### 2.3 · Watch as cellular gateway when phone is absent

- Cellular Apple Watch: characterize real-world bandwidth, latency, and battery cost when running a persistent WSS tunnel to `xr.grizzlymedicine.icu` (our operator host). Include: `NWConnection` vs `URLSessionWebSocketTask`; background delivery constraints; what counts as an "always-running" watchOS background task in 2026.
- If cellular is not viable for 24/7 tunnel, what's the fallback? (Phone as mesh peer over `MultipeerConnectivity`? Ultra-Wideband handoff? iPad in car doing the same thing?)
- Auto-handoff ladder: watch LTE → watch on iPhone personal hotspot → watch on iPhone WiFi relay → watch on home WiFi when docked.

### 2.4 · Phone-as-compute-slab UX model

The phone stops being a communications gateway. What *does* it do?
- Primary HUD for Jarvis visual surfaces that don't fit on watch (maps, cockpit tiles, camera feeds).
- Local compute for on-device inference (MLX) the watch can't host.
- Persistent paired surface for CarPlay + in-home surfaces (Apple TV / HomePods / mesh displays).

Investigate: does Apple's current "phone must be nearby" locks (iCloud auth, Find My, Handoff) break anything if the phone is parked on a charger across the house while the watch does real-time comms? Enumerate every friction point.

### 2.5 · Identity + security

The watch walks with the body → it's the strongest biometric-bound primary in the stack. But:
- Wrist-detect: how trustworthy is it? What does it take to off-wrist-invalidate an active Jarvis session within 500ms?
- Can we use the watch's Secure Enclave for signing the `JarvisClientRegistration` nonce so the phone is never part of the trust chain? (See `Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift` for today's phone-rooted registrar.)
- Responder-OS implications: on-shift EMT/EMTP wears a watch, not a phone. Watch-as-gateway is a **responder-OS requirement**, not just a nice-to-have for home.

### 2.6 · Failure modes Qwen must enumerate

Enumerate + rank by severity:
- Watch battery dies mid-shift → does Jarvis cleanly degrade to phone-as-hub fallback?
- Headphones only expose unidirectional A2DP → does Jarvis detect and route mic to watch built-in?
- Two headphones in range (AirPods + Bose) → which wins, and can operator re-assign at the speed of a Siri-style voice command?
- Watch enters airplane mode / crown-flag → tunnel state must reconcile on resume, not just reopen blindly.

---

## 3 · Required deliverables (Qwen's output)

Put all of these into `Construction/Qwen/response/AMBIENT-001-response.md`:

1. **Topology diagram set.** ASCII or mermaid. Three scenes:
   - "At home, phone on counter." Shows audio path + control plane.
   - "On the move, phone in pocket." Shows watch as audio primary, phone as compute slab.
   - "On shift, phone in truck, watch + headphones on body." Responder-OS primary.
2. **Feasibility matrix.** For each of §2.1 / §2.2 / §2.3: what works today with public APIs, what requires private APIs, what needs a hardware or OS-version cutoff. Cite WWDC session numbers, framework headers, or device-support tables.
3. **Pairing/handoff state machine.** Every state + transition the audio gateway can be in: `unpaired`, `watch-hosted`, `phone-relayed`, `dual-headset-present`, `off-wrist`, `cellular-tether`, `degraded`. Include transition triggers and how Jarvis telemetry witnesses each one (tie to `TelemetryStore.append(… principal:)` — every state change is a principal-witnessed row).
4. **API surface proposal.** What Swift API would JarvisCore expose on watchOS? Sketch the protocols. Recommended shape: an `AmbientAudioGateway` protocol with `currentRoute`, `hostedEndpoints`, `reassign(to:)`, `handoffTo(compute:)`.
5. **Staged rollout plan.** Three phases:
   - **Phase 1 (public-API-only, App Store clean).** What ambient behaviors we can ship today without private frameworks.
   - **Phase 2 (operator-build, private frameworks OK).** What we unlock with self-signed + TestFlight operator lane.
   - **Phase 3 (OS-version asks of Apple).** What we can't do that we'd need Apple to open up — worth filing as feedback + building a rhetorical case for in WWDC outreach.
6. **Interop with existing Jarvis canon.** Cross-link:
   - `Jarvis/Sources/JarvisCore/Host/TunnelIdentityStore.swift` — must support `watch` as a registered host type (currently phone-centric).
   - `Jarvis/Sources/JarvisCore/Host/BiometricTunnelRegistrar.swift` — must support watch Secure Enclave signing.
   - `Jarvis/Sources/JarvisCore/Voice/*` — voice pipeline must accept watch-sourced audio framing.
   - `obsidian/knowledge/concepts/Companion-OS-Tier.md` — 4-tier brand model; watch primacy changes the operator's default surface.
7. **Risks + non-goals.**
   - Non-goal: replacing CarPlay. CarPlay stays, but the watch is the persistent layer across car↔sidewalk↔ambulance↔home.
   - Non-goal: replacing HomePod mini as in-room voice surface.
   - Risk: Apple silently yanks any private API this design relies on. For every private-API dependency, note a graceful-fallback alternative.

---

## 4 · Deliverable shape

- One file: `Construction/Qwen/response/AMBIENT-001-response.md`.
- Long-form OK — this is a design doc, not a PR. 3–6k words is fine.
- End with an **operator-readable one-paragraph summary** at the very top (TL;DR), because operator reads the first screen and the bottom screen first. Everything else is engineer-oriented detail in between.
- No code changes in this spec. Recommendations only. Implementation work gets separate AMBIENT-002/003 specs after review.

---

## 5 · Coordination notes

- GLM owns navigation (NAV-001). DeepSeek owns voice synthesis (F5-TTS). You are **adjacent but non-overlapping**: your output influences the voice pipeline's audio framing assumptions but doesn't collide with synthesis itself.
- If in doubt: **ambient > aesthetic**. The goal is that Jarvis is always there, as loud or as quiet as the operator wants, without the phone being the reason the link breaks.
- File-discipline: drop your response in `Construction/Qwen/response/AMBIENT-001-response.md`. Do NOT modify JarvisCore source yet — that's a follow-up spec after operator reviews your proposal.

— Copilot, coordinating.
