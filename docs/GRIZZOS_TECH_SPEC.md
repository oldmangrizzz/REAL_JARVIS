# GrizzOS Technical Specification v1.0
## Generative Ambient Spatial Operating System

### 1. System Overview
GrizzOS is a decentralized spatial operating system built on Unity URP, designed to merge physical environments with a generative digital workspace. It serves as the primary interface for JARVIS and the GMRI Workshop.

### 2. Core Tech Stack
*   **Engine:** Unity 2022.3+ LTS (Universal Render Pipeline)
*   **XR:** Meta XR Interaction SDK (Passthrough, Hand Tracking, Spatial Anchors)
*   **Physics:** MuJoCo Unity Integration (for high-fidelity tactical simulations)
*   **State Sync:** Convex (C# Client) - Global stigmergic coordination
*   **Voice/RTC:** LiveKit WebRTC (Coqui XTTS v2 integration)
*   **Rendering:** Unity VFX Graph (Clifford Attractor, Pheromind visualizations)

### 3. Unity Project Architecture
#### 3.1 Directory Structure
```
Assets/
├── GrizzOS/
│   ├── Core/                # Singleton Managers (Convex, LiveKit, Input)
│   ├── Scripts/
│   │   ├── Controllers/      # Gaze tracking, Waveform collapse logic
│   │   ├── Integrations/     # Convex, LiveKit, Home Assistant
│   │   └── UI/               # Spatial terminal, HUD elements
│   ├── Prefabs/
│   │   ├── Environment/      # War Table, Server Racks (Greybox)
│   │   └── VFX/              # Clifford Attractor, Abrikosov Vortex
│   ├── Shaders/              # Custom HLSL for Attractors
│   └── VFX/                  # VFX Graph assets
├── ThirdParty/
│   ├── Oculus/               # Meta XR Interaction SDK
│   ├── Convex/               # Convex C# Client
│   ├── LiveKit/              # LiveKit Unity SDK
│   └── MuJoCo/               # MuJoCo Unity Bridge
└── Settings/                 # URP & XR Settings
```

#### 3.2 Core Managers
*   **GrizzOS_Coordinator (Singleton):** Orchestrates the initialization sequence (Breach -> Sync -> Voice).
*   **ConvexManager:** Maintains WebSocket connection to Convex Pro. Handles subscriptions to `obsidian_graph` and `system_telemetry`.
*   **LiveKitVoiceManager:** Connects to Charlie VPS. Streams Coqui XTTS v2 output to a spatialized AudioSource.
*   **VFX_ObserverController:** Interfaces with XR Ray Interactor to detect gaze on VFX clouds, triggering the "Observer Effect" parameter shifts.

### 4. Global State & Sync (Convex)
*   **Persistence:** All spatial transforms of digital objects (Whiteboards, Lockboxes) are stored in Convex.
*   **Stigmergic Coordination:** Pheromind trails are generated from live n8n workflow events synced via Convex.
*   **Obsidian Link:** Vault nodes are rendered as 3D tokens; metadata is fetched on waveform collapse.

### 5. Ambient Voice Pipeline (LiveKit)
*   **Endpoint:** Charlie VPS (`srv1338884` / 76.13.146.61).
*   **Protocol:** WebRTC over UDP.
*   **Voice Model:** Coqui XTTS v2 (running in a dedicated LXC container).
*   **Spatialization:** Audio is anchored to the JARVIS virtual avatar or the Operator's head for "omnipresent" feel.

### 5.1 Roger Roger + GhostLine
*   **Roger Roger:** Bidirectional intelligibility protocol for live speech, audio enhancement, push-to-talk, Sentinel mode, and full live speech.
*   **GhostLine:** Delivery and route fabric for Elehear Beyond, Watch speaker, Watch haptics/text, iPhone broker, Mac/iPad veil, HomePods, and CarPlay.
*   **Watch-only operation:** Watch speaker output is a first-class endpoint for JARVIS-originated speech when the Watch is the only body present.
*   **Reference:** `docs/ROGER_ROGER_GHOSTLINE_2026.md`.

### 6. The Observer Effect Implementation
*   **Detection:** Gaze duration thresholding on VFX particle bounds.
*   **VFX Graph Interface:**
    *   `Exposed Parameter: Entanglement (Float 0-1)`
    *   `Exposed Parameter: CollapseState (Bool)`
*   **Logic:** `OnGazeEnter` -> Interpolate `Entanglement` to 1.0 -> Enable schematic UI overlay.

### 7. Deployment Strategy
*   **Render Node (Alpha):** Proxmox-hosted Windows/Linux VM with GPU Passthrough for heavy rendering.
*   **Delivery (Quest 3):** Native Android build (APK) with Passthrough enabled.
*   **Spectator (Public):** WebGL build hosted on Charlie VPS via Pangolin proxy.

---
*Authorized by H.U.G.H. for GMRI Operations.*
