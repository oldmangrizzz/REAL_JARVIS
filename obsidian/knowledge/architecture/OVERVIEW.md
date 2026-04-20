# Architecture Overview

**Source material:** `JARVIS_INTELLIGENCE_BRIEF.md`, `JARVIS_INTELLIGENCE_REPORT.md`, [[codebase/CODEBASE_MAP]], `PRINCIPLES.md`.

---

## Big picture

REAL_JARVIS is a **sovereign-stack digital-person engine** running across a Swift application family, backed by local Python services and a small set of web/XR surfaces. Every layer is owned end-to-end per `PRINCIPLES.md §2` (hardware sovereignty) and every canon-touching layer is dual-signed per [[architecture/SOUL_ANCHOR_DEEP_DIVE|SOUL_ANCHOR]].

```
 ┌──────────────────────── Operator (Grizz) ────────────────────────┐
 │                                                                   │
 │  Apple Watch ◀──▶ iPhone/iPad ◀──▶ macOS (primary)  ◀──▶ PWA/XR   │
 │                                        │                          │
 │                                        ▼                          │
 │                                 JarvisCore (Swift)                │
 │            ┌──────────┬─────────┬──────┴──────┬──────────┐        │
 │            │  Voice   │ Memory  │ Oscillator  │ Canon    │        │
 │            │  Gate    │ Engine  │ + PLV       │ (MCU)    │        │
 │            └────┬─────┴────┬────┴─────┬───────┴────┬─────┘        │
 │                 │          │          │            │              │
 │     Interface + Display    │   Telemetry (signed)  │              │
 │                 │          │          │            │              │
 │                 ▼          ▼          ▼            ▼              │
 │    AirPlay / HDMI-CEC / HTTP     .jarvis/ signed artifacts        │
 │            │                                                      │
 │            ▼                                                      │
 │    TV / Speakers / Workshop surfaces                              │
 │                                                                   │
 │            ┌────────── Services (localhost / own hw) ────────┐    │
 │            │  jarvis-linux-node (Python systemd, sidecar)    │    │
 │            │  vibevoice-tts (FastAPI, GCP Cloud Run)         │    │
 │            └──────────────────────────────────────────────────┘   │
 │                                                                   │
 │            ┌────────── Research / experimentation ──────────┐     │
 │            │  Archon workflows · Unity Workshop · PWA · XR  │     │
 │            │  Convex real-time sync                         │     │
 │            └────────────────────────────────────────────────┘     │
 └───────────────────────────────────────────────────────────────────┘
```

## Platforms

- **macOS** — primary compute and development surface ([[codebase/platforms/Mac]]).
- **iPhone / iPad** — secondary conversational surfaces ([[codebase/platforms/Mobile]]).
- **Apple Watch** — wrist-tap / haptic / glanceable surface ([[codebase/platforms/Watch]]).
- **App target** — SwiftPM/Xcode `@main` bootstrap at `Jarvis/App/main.swift` ([[codebase/platforms/App]]).
- **Shared** — cross-platform UI/logic ([[codebase/platforms/Shared]]).

## Core subsystems (Swift, `Jarvis/Sources/JarvisCore/`)

- [[codebase/modules/Core|Core]] — runtime bootstrap, skill registry.
- [[codebase/modules/SoulAnchor|SoulAnchor]] — dual-signature identity root.
- [[codebase/modules/Canon|Canon]] — load-time validation of mcuhist + repo-root canon files.
- [[codebase/modules/Voice|Voice]] — approval gate + TTS backends.
- [[codebase/modules/Interface|Interface]] — intent parsing, capability registry, display executors.
- [[codebase/modules/Memory|Memory]] — episodic / semantic graph.
- [[codebase/modules/Oscillator|Oscillator]] — SA-node timing, PLV health.
- [[codebase/modules/Telemetry|Telemetry]] — signed event store.
- [[codebase/modules/Pheromind|Pheromind]] — stigmergic coordination.
- [[codebase/modules/ARC|ARC]] — ARC-AGI bridge harness.
- [[codebase/modules/Harness|Harness]], [[codebase/modules/Host|Host]], [[codebase/modules/ControlPlane|ControlPlane]] — scaffolding / supervision.
- [[codebase/modules/Network|Network]], [[codebase/modules/RLM|RLM]], [[codebase/modules/Physics|Physics]], [[codebase/modules/Support|Support]], [[codebase/modules/Storage|Storage]].

## External surfaces

- [[codebase/services/jarvis-linux-node]] — Linux sidecar daemon (Python systemd).
- [[codebase/services/vibevoice-tts]] — remote TTS (Python FastAPI on GCP Cloud Run).
- [[codebase/frontend/pwa]] — Unity WebGL + Node WS proxy + nginx.
- [[codebase/frontend/cockpit]] — operator control plane.
- [[codebase/frontend/workshop-unity]] — Unity project source.
- [[codebase/frontend/xr-grizzlymedicine]] — XR landing surface.
- [[codebase/backend/convex]] — Convex real-time sync (experimental).
- [[codebase/workflows/archon]] — YAML workflow engine.

## Where the trust lines sit

See [[architecture/TRUST_BOUNDARIES]]. The short version:

- Operator hardware = trusted root.
- `JarvisCore` in-process = trusted.
- Anything over the [[concepts/NLB|NLB]] = untrusted until mediated via natural-language artifact exchange.
- Anything outside `REAL_JARVIS/` = untrusted (no symlinks, no shared secrets).

## Critical paths

- [[architecture/VOICE_TO_DISPLAY_PIPELINE]] — the hot-path trace from voice intent to surface rendering.
- [[architecture/SOUL_ANCHOR_DEEP_DIVE]] — every bootstrap and every canon-touching write traverses this.

## Quirks worth knowing

- Root `Package.swift` is a **minimal `tempcheck` harness**, not the main build. The real build is the Xcode project `Jarvis.xcodeproj`.
- 977 MB of legal-evidence video (`elijah_mcclain.mp4` + `elijah_frames/`) lives at repo root but is not code.
- `vendor/mlx-audio-swift` is checked in on purpose (reproducibility, per hardware-sovereignty).
