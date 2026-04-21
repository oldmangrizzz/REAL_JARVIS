# AMBIENT‑002: Phase 1 Watch‑First Audio Gateway – Turnover Note  

**Author:** Qwen (Audio Team)  
**Date:** 2026‑04‑21  

---  

## 1. Overview  

This document records what has been shipped for **Phase 1 – Watch‑First Audio Gateway**, enumerates the gaps that will be addressed in **Phase 2**, and lists the known issues that remain in the current codebase. The primary goal of Phase 1 was to expose a clean, testable API for ambient audio capture on watchOS, integrate it with the existing tunnel‑identity and biometric registration flows, and lay the groundwork for telemetry and hermetic testing.  

---  

## 2. Shipped Items  

| Component | Description | Location |
|-----------|-------------|----------|
| **AmbientAudioGateway API** | New public Swift protocol (`AmbientAudioGateway`) plus a concrete `AmbientAudioGatewayImpl` that abstracts microphone access, permission handling, and audio buffering. | `Sources/AmbientAudioGateway/AmbientAudioGateway.swift` |
| **watchOS Concrete Implementation** | `WatchAmbientAudioGateway` implements `AmbientAudioGateway` using `AVAudioEngine` on watchOS, with low‑latency settings tuned for the Apple Watch hardware. | `Sources/WatchAmbientAudioGateway/WatchAmbientAudioGateway.swift` |
| **Tunnel Identity Integration** | Audio gateway now registers its session ID with the `TunnelIdentityProvider` so that downstream services can correlate audio streams with the correct tunnel. | `Sources/TunnelIdentity/TunnelIdentityProvider.swift` (updated) |
| **Biometric Registrar Hook** | After a successful audio capture start, the gateway notifies `BiometricRegistrar` to begin a “voice‑print” enrollment flow if the user has opted‑in. | `Sources/BiometricRegistrar/BiometricRegistrar.swift` (updated) |
| **Voice Pipeline Connection** | The captured PCM frames are streamed into the existing `VoiceProcessingPipeline` via a new `AudioFrameSink`. The pipeline now supports watch‑originated frames without modification. | `Sources/VoicePipeline/AudioFrameSink.swift` |
| **Telemetry** | Added `AmbientAudioTelemetry` that records start/stop timestamps, sample‑rate, buffer underruns, and error codes. Telemetry events are emitted through the shared `TelemetryReporter`. | `Sources/Telemetry/AmbientAudioTelemetry.swift` |
| **Documentation** | - API reference generated with Jazzy (`docs/AmbientAudioGateway/`). <br>- Integration guide (`docs/Guides/WatchAudioGateway.md`). <br>- Architecture diagram (`docs/Diagrams/AudioGateway.svg`). | `docs/` |
| **Hermetic Tests** | - Unit tests for `AmbientAudioGatewayImpl` (mocked `AVAudioEngine`). <br>- End‑to‑end test harness (`WatchAudioGatewayTests`) that runs on the watchOS simulator with deterministic audio fixtures. <br>- CI integration (Xcode Cloud) with flaky‑test detection. | `Tests/AmbientAudioGatewayTests/` |
| **Sample App** | Minimal watchOS app (`AmbientAudioDemo`) that demonstrates start/stop, permission UI, and live waveform rendering. | `Examples/AmbientAudioDemo/` |

---  

## 3. Phase 2 Gaps  

| Gap | Rationale / Expected Work |
|-----|---------------------------|
| **iOS Audio Gateway** | Phase 1 is watch‑first only. A parallel `IOSAmbientAudioGateway` will be needed to share the same API surface on iPhone/iPad. |
| **Background Audio Support** | Current implementation stops when the watch app goes to the background. Phase 2 will add `AVAudioSessionCategoryPlayAndRecord` with background mode entitlement. |
| **Multi‑Stream / Channel Mixing** | Only a single mono stream is exposed. Future work includes supporting stereo capture and mixing multiple microphone inputs (e.g., external accessories). |
| **Advanced Noise Suppression** | Integration with Apple’s `VoiceProcessingIO` and third‑party NN‑based denoisers is pending. |
| **UI Integration** | The demo app shows a raw waveform; Phase 2 will provide a reusable SwiftUI component (`AmbientAudioVisualizer`). |
| **Dynamic Sample‑Rate Negotiation** | Currently fixed at 16 kHz. Phase 2 will negotiate based on network bandwidth and device capability. |
| **Telemetry Enrichment** | Add per‑frame SNR, battery impact metrics, and user‑privacy consent flags. |
| **Full End‑to‑End Encryption** | Wire‑level encryption of audio frames to the backend is not yet in place. |
| **Accessibility & Localization** | Voice‑over strings and localized permission dialogs need to be added. |
| **Performance Benchmarks** | Formal latency and CPU‑usage benchmarks on all watch generations are still missing. |

---  

## 4. Known Issues  

1. **Latency on Older Watch Models** – On Series 3 the end‑to‑end latency can exceed 120 ms due to hardware‑level audio buffer size. Mitigation: recommend using Series 4+ for latency‑critical use cases.  
2. **Biometric Registrar Race Condition** – In rare cases the registrar receives a “start” callback before the audio session is fully active, causing a failed voice‑print enrollment. A guard flag has been added, but the race can still surface under heavy system load.  
3. **Telemetry Gaps** – When the audio engine fails to start, the `errorCode` field is populated, but the `sessionId` is omitted, making correlation difficult. This will be fixed in Phase 2.  
4. **Test Flakiness on CI** – The hermetic end‑to‑end test occasionally times out on the watchOS simulator when the host machine is under CPU pressure. Added a retry wrapper, but the underlying issue remains.  
5. **Permission Prompt Timing** – The permission dialog may appear after the first `startCapture()` call, causing a brief “no audio” period. The API now returns a `Future` that resolves once permission is granted, but callers must handle the interim state.  
6. **Memory Footprint** – The audio buffer retains up to 2 seconds of PCM data for telemetry; on low‑memory watches this can trigger a memory warning. Future work will make the buffer size configurable.  

---  

## 5. Next Steps  

1. **Sprint Planning** – Prioritize iOS gateway and background audio support for the next sprint.  
2. **Bug Triage** – Assign owners to the known issues above; create JIRA tickets for each.  
3. **Documentation Review** – Conduct a peer review of the new docs and update the public API reference.  
4. **Performance Testing** – Add benchmark targets for latency and CPU usage across watch generations.  

---  

*End of Turnover Note*