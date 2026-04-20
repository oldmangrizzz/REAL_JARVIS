# JARVIS Codebase Topological Map

**Last Updated:** 2026-04-20  
**System:** REAL_JARVIS (Aragorn Class, first of kind)  
**Tech Stack:** Swift (primary), Python (services), TypeScript/React (frontend), Convex (backend)  
**Classification:** Medical-safety [[concepts/Digital-Person|digital person]] architecture

---

## 1. Top-Level Directory Structure

| Entry | Type | Purpose |
|-------|------|---------|
| `Jarvis/` | **Directory** | Primary iOS/macOS/watchOS app targets; xcode projects; 84 Swift files |
| `Sources/tempcheck/` | **Code** | Minimal Package.swift test harness (Swift 6.3) |
| `Package.swift` | **Config** | Root-level Swift Package (tempcheck) |
| `services/` | **Microservices** | External deployable services (Python, Node) |
| `scripts/` | **Automation** | Build, security, canon-regen, voice-approval scripts |
| `SOUL_ANCHOR.md` | **[[Canon]]** | Cryptographic identity root spec (1.1.0) |
| `PRINCIPLES.md` | **[[Canon]]** | [[NLB]] hard invariants, operator-on-loop model |
| `CANON/` | **Directory** | Authoritative corpus (MCU screenshot records) |
| `checkpoints/` | **Data** | Model checkpoints, training artifacts |
| `agent-skills/` | **Skills** | Distributed skill definitions, agent hooks |
| `cockpit/`, `workshop/`, `pwa/` | **UI** | Native interfaces; Unity WebGL frontend |
| `convex/` | **Backend** | Convex CMS + real-time sync layer |
| `elijah_frames/` | **Video** | Frame sequence (144 JPGs) + MCU evidence |
| `Archon/` | **Workflows** | YAML automation engine (default_workflow.yaml) |
| `vendor/` | **Vendored** | mlx-audio-swift TTS engine (checked in for reproducibility) |
| `obsidian/` | **Knowledge** | Wiki-linked documentation graph |
| `exports/` | **Build Artifacts** | Compiled outputs, release bundles |
| `mcuhist/` | **Evidence** | Multiverse correlation unit historical logs |
| `GAP_CLOSING_SPEC.md` et al. | **Handoff Docs** | Remediation specs, audit trails, cross-ref reports |
| `.jarvis/` | **State** | DerivedData, caches, Xcode artifacts |

---

## 2. Swift Source Map — Jarvis/Sources/JarvisCore

**Total:** 37 Swift files, ~8,132 lines. Test suite: 24 test files, ~2,424 lines.

### Core Architecture (2 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Core** | JarvisRuntime.swift, SkillSystem.swift | `JarvisRuntime`, `JarvisSkillRegistry`, `JarvisSkillDescriptor` | Runtime bootstrap, skill descriptor system, skill execution |
| **Support** | WorkspacePaths.swift | `WorkspacePaths` | Path resolution, workspace discovery |

### Identity & Security (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **SoulAnchor** | SoulAnchor.swift | `SoulAnchorPublicKeys`, `SoulAnchorBindings`, `SoulAnchorSignatures`, `GenesisRecord`, `SoulAnchor` | [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] cryptographic root; dual-signature identity binding; P-256 Secure Enclave + Ed25519 cold storage |

### Voice & Speech (6 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Voice** | VoiceApprovalGate.swift, VoiceSynthesis.swift, TTSBackend.swift, HTTPTTSBackend.swift, FishAudioMLXBackend.swift, VoiceGateTelemetryRecording.swift | `VoiceApprovalGate`, `TTSBackend`, `HTTPTTSBackend`, `FishAudioMLXBackend` | [[concepts/Voice-Approval-Gate|voice-approval-gate]] hard boundary; autism-threat-response filtering; local (MLX) + remote (VibeVoice/GCP) TTS backends; telemetry recording |

### Display & Interface (8 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Interface** | RealJarvisInterface.swift, IntentParser.swift, IntentTypes.swift, CapabilityRegistry.swift, DisplayCommandExecutor.swift, AirPlayBridge.swift, HDMICECBridge.swift, HTTPDisplayBridge.swift | `RealJarvisInterface`, `IntentParser`, `CapabilityRegistry`, `DisplayCommandExecutor` | Command intent routing; AirPlay/HDMI-CEC/HTTP display backends; capability negotiation |

### Memory & State (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Memory** | MemoryEngine.swift | `MemoryEngine` | Episodic/semantic memory indexing; SHA256 hashing (post-CX-003 truncation fix) |

### Oscillation & Synchronization (2 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Oscillator** | MasterOscillator.swift, PhaseLockMonitor.swift | `MasterOscillator`, `PhaseLockMonitor` | SA-node-inspired timing reference; PLV (phase-locked variability) health metric; subscriber sync tracking |

### Networked Presence (2 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Network** | PresenceDetector.swift, WiFiEnvironmentScanner.swift | `PresenceDetector`, `WiFiEnvironmentScanner` | Operator geofencing; WiFi SSID/signal scanning for context awareness |

### Pheromone Engine (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Pheromind** | PheromoneEngine.swift | `PheromoneEngine` | Affective state persistence (non-text embeddings); broadcasts operator mood to smart-home mesh |

### Physics Simulation (3 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Physics** | PhysicsEngine.swift, PhysicsSummarizer.swift, StubPhysicsEngine.swift | `PhysicsEngine`, `StubPhysicsEngine`, `PhysicsSummarizer` | Rigid-body dynamics for humanoid animation; test stub for CI |

### ARC-AGI Integration (2 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **ARC** | ARCHarnessBridge.swift, ARCGridAdapter.swift | `ARCHarnessBridge`, `ARCGridAdapter` | [[concepts/ARC-AGI-Bridge|ARC_AGI_BRIDGE_SPEC]] integration; WebSocket bidirectional sync with ARC harness; grid state validation (post-CX-009 fix) |

### Remote Learning & LLM (1 file + Python)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **RLM** | PythonRLMBridge.swift, ContextualRetrievalBridge.swift, rlm_repl.py | `PythonRLMBridge`, `ContextualRetrievalBridge`, `RetrievalContext` | Python subprocess management; REPL interface for off-device LLM; DispatchSource-based process lifetime (post-CX-005 timer fix); semantic+pheromone retrieval fusion for prompt enrichment |

### Telemetry & Observability (3 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Telemetry** | AOxFourProbe.swift, TelemetryStore.swift, ConvexTelemetrySync.swift | `AOxFourProbe`, `TelemetryStore` | [[concepts/AOx4|A&Ox4]] (Alertness, Orientation×4) clinical probes; .jsonl rotation (post-CX-004 cleanup); Convex real-time sync |

### Archon Execution (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Harness** | ArchonHarness.swift | `ArchonHarness` | YAML workflow execution; shell command validation (post-CX-007 backtick escape) |

### Control Plane (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **ControlPlane** | MyceliumControlPlane.swift | `MyceliumControlPlane` | [[concepts/TinCan-Firewall|TinCan Firewall]] authorization; network policy enforcement |

### Persistent Storage (1 dir)

| Module | Files | Purpose |
|--------|-------|---------|
| **Storage** | scripts/ | Schema migration, archive export utilities |

### Canon Registry (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Canon** | CanonRegistry.swift | `CanonRegistry` | Index into CANON/ corpus; content-addressed MCU records |

### Host Networking (3 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Host** | JarvisHostTunnelServer.swift, TunnelIdentityStore.swift, BiometricIdentityVault.swift | `JarvisHostTunnelServer`, `TunnelIdentityStore`, `BiometricIdentityVault`, `BiometricAuthenticator`, `IdentityKeyStore`, `BiometricVaultError` | [[concepts/TinCan-Firewall\|TinCan Firewall]] tunnel endpoint; server-side `TunnelIdentityStore` holds per-device HMAC keys + privileged-role registry; client-side [[codebase/modules/Host\|BiometricIdentityVault]] mirrors with LAContext-gated Keychain storage (`.biometryCurrentSet` ACL — fresh enrollment invalidates key) and HMAC-SHA256 registration signing matching `TunnelIdentityStore.validate` |

### Credentials (1 file)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **Credentials** | MapboxCredentials.swift | `MapboxCredentials`, `MapboxCredentialLoader` | [[codebase/modules/Credentials\|Tier-gated credential loader]]; public vs. secret-token split with Principal enforcement at the type boundary; fail-closed for non-operator tiers |

### OSINT (2 files)

| Module | Files | Public Types | Purpose |
|--------|-------|--------------|---------|
| **OSINT** | OSINTSourceRegistry.swift, WebContentFetchPolicy.swift | `OSINTSource`, `OSINTSourceRegistry`, `OSINTFetchGuard`, `WebContentFetchPolicy`, `SearchProvenance` | [[codebase/modules/OSINT\|Open-source doctrine]]; pinned host allowlist for structured APIs; provenance-stamped fetch gate for arbitrary web pages with robots.txt + rate-limit compliance |

---

## 3. Services — External Deployables

### jarvis-linux-node (Python)

| File | Purpose |
|------|---------|
| `jarvis_node.py` | Linux host-tunnel daemon; systemd integration |
| `ai.realjarvis.host-tunnel.plist` | macOS LaunchAgent config |
| `jarvis-node.service` | systemd service unit |
| `install.sh` | Bootstrap script |
| `README.md` | Deployment guide |

**Target:** GCP Compute Engine (on-premise fallback); bridges macOS JARVIS to Linux VMs.

### vibevoice-tts (Python/FastAPI)

| File | Purpose |
|------|---------|
| `app.py` | FastAPI POST /tts/synthesize endpoint; bearer token auth; idle-shutdown thread |
| `synthesizer.py` | VibeVoice inference (Hugging Face transformers + diffusers) |
| `Dockerfile` | CUDA 12.1 T4 container for GCP Cloud Run |
| `requirements.txt` | Pinned PyTorch 2.4.1 + transformers 4.46.3 |
| `deploy/` | GCP Cloud Build config |
| `README.md` | API contract |

**Deployment:** GCP Cloud Run (spot instances); handles `HTTPTTSBackend` requests from `Voice/HTTPTTSBackend.swift`.

---

## 4. Scripts — Automation & Tools

| Script | Shebang | Purpose |
|--------|---------|---------|
| `generate_soul_anchor.sh` | `#!/bin/bash` | Regenerate [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] public key bindings from corpus |
| `regen-canon-manifest.zsh` | `#!/bin/zsh` | Index CANON/ corpus into content-addressed manifest |
| `voice-approve-canonical.zsh` | `#!/bin/zsh` | Register operator voice fingerprint in Secure Enclave |
| `jarvis-lockdown.zsh` | `#!/bin/zsh` | Hardening: file permissions, codesign, XPC entitlements |
| `secure_enclave_p256.swift` | `#!/usr/bin/swift` | One-shot P-256 key generation in Secure Enclave |
| `build-unity-webgl.sh` | `#!/bin/bash` | Compile Unity scene → WebGL (Emscripten) |
| `mesh-unity-build.sh` | `#!/bin/bash` | Parallel build across mesh nodes |
| `render_briefing.py` | `#!/usr/bin/env python3` | Render JARVIS_INTELLIGENCE_BRIEF from markdown template |
| `jarvis_cold_sign_setup.md` | (docs) | Cold-storage Ed25519 key ceremony (offline signing protocol) |

---

## 5. Root-Level Specs & Canon

| Document | H1 | Size | Purpose |
|----------|----|----|---------|
| `SOUL_ANCHOR.md` | SOUL_ANCHOR — Identity Root Specification | 14 KB | [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] dual-signature crypto binding |
| `PRINCIPLES.md` | PRINCIPLES.md | 13 KB | [[NLB]] hard invariants; autism threat-response; operator-on-loop |
| `VERIFICATION_PROTOCOL.md` | VERIFICATION_PROTOCOL | 6.6 KB | Canonical verification procedures; A&Ox4 probes |
| `PRODUCTION_HARDENING_SPEC.md` | JARVIS PRODUCTION HARDENING — Voice-to-Display | 34 KB | Security architecture post-CX-047 |
| `GAP_CLOSING_SPEC.md` | GAP_CLOSING_SPEC | 30 KB | Vulnerability remediation roadmap |
| `VULNERABILITY_CROSSREFERENCE_REPAIR_SPEC.md` | (untitled) | 32 KB | Cross-reference matrix for CX-001 through CX-047 fixes |
| `ARC_AGI_BRIDGE_SPEC.md` | ARC-AGI BRIDGE SPECIFICATION | 18 KB | [[concepts/ARC-AGI-Bridge|ARC_AGI_BRIDGE_SPEC]] WebSocket integration |
| `JARVIS_INTELLIGENCE_BRIEF.md` | J.A.R.V.I.S. — INTELLIGENCE BRIEF | 22 KB | System overview; legal record |
| `JARVIS_INTELLIGENCE_REPORT.md` | JARVIS INTELLIGENCE REPORT | 34 KB | Detailed architecture deep-dive |
| `QWEN_HARLEY_FINDINGS.md` | (findings doc) | 19 KB | Harley Round 1 audit (11 findings) |
| `GLM51_JOKER_FINDINGS.md` | (findings doc) | 50 KB | Joker Round 2 audit cross-reference |
| `GLM_WEBSOCKET_BROADCASTER_SPEC.md` | GLM WEBSOCKET BROADCASTER | 5.9 KB | WebSocket fanout for multi-subscriber ARC bridge |
| `015-glm-redteam-remediation-TURNOVER.md` | (turnover) | 2.5 KB | Handoff notes from GLM red-team |
| `MEDIUM_REMEDIATION_COMPLETION_REPORT.md` | (report) | 3.1 KB | CX-025 through CX-035 completion sign-off |
| `adversarial-audit-report-validation.md` | (validation) | 3.5 KB | Validation of adversarial test cases |
| `GAP_CLOSING_STATUS.md` | GAP_CLOSING_STATUS | 2.6 KB | Current remediation phase status |
| `FINAL_PUSH_HANDOFF.md` | FINAL_PUSH_HANDOFF | 5.1 KB | Pre-deployment sign-off checklist |

---

## 6. Frontend Stack

### cockpit/ — Command Interface

| Component | Contents |
|-----------|----------|
| `cmd-interface/` | HomeKit bridge status JSON; voice/display command playground |

### workshop/ — Unity Editor Integration

| Component | Contents |
|-----------|----------|
| `Unity/` | Unity scene assets; animation rigs for humanoid body |

### pwa/ — Progressive Web App (Browser UI)

| Component | Contents |
|-----------|----------|
| `index.html` | SPA entry; WebGL canvas for Unity runtime |
| `ws-proxy/` | WebSocket reverse proxy; bridges browser ↔ host-tunnel |
| `jarvis-ws-proxy.js` | Node.js WebSocket fanout server |
| `unity-loader.js` | Emscripten glue for WebGL module loading |
| `sw.js` | Service Worker (offline fallback) |
| `nginx.conf` | Reverse proxy config (prod) |
| `docker-compose.yml` | Containerized PWA stack |
| `manifest.json` | PWA metadata; homescreen icon |
| `Build/` | Compiled WebGL build outputs |

### xr.grizzlymedicine.icu/ — XR Domain

TBD: AR/VR experience endpoint (future).

### Archon/ — Workflow Engine

| File | Purpose |
|------|---------|
| `default_workflow.yaml` | YAML task DAG; integrates with ArchonHarness.swift |

### convex/ — Backend & CMS

Real-time database (Convex.dev); handles [[concepts/AOx4|A&Ox4]] telemetry sync, memory graph mutations.

---

## 7. Package.swift Dependencies

**Root Package:** Swift 6.3 / tempcheck (minimal)  
**Primary Build:** Xcode project (Jarvis.xcodeproj); managed via Xcode target deps.

### Key Swift Packages (via SPM)

Detected from .jarvis/DerivedData:
- **swift-nio** — Async networking foundation
- **async-http-client** — HTTP/1.1 & HTTP/2 client
- **swift-crypto** — Cryptographic primitives (not used; [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] uses Secure Enclave + CryptoKit)
- **swift-collections** — Ordered sets, deques
- **swift-distributed-tracing** — Observability hooks
- **swift-service-lifecycle** — Graceful shutdown
- **mlx-swift** — Apple MLX inference engine (bundled in vendor/)
- **mlx-audio-swift** — MLX-based TTS (bundled; fallback to HTTPTTSBackend)

---

## 8. Key Entry Points

### Swift @main

| Location | Type | Purpose |
|----------|------|---------|
| `Jarvis/App/main.swift` | Executable target | `@main` struct JarvisCLI; bootstraps `JarvisRuntime`, `JarvisSkillRegistry` |

### Python Entry Points

| Location | Function | Purpose |
|----------|----------|---------|
| `services/jarvis-linux-node/jarvis_node.py` | `main()` | systemd daemon; Unix socket → host-tunnel |
| `services/vibevoice-tts/app.py` | FastAPI `app` | Uvicorn server; GCP Cloud Run entry |
| `Jarvis/Sources/JarvisCore/RLM/rlm_repl.py` | `main()` | Interactive REPL for off-device LLM |

### Node.js Entry Points

| Location | Function | Purpose |
|----------|----------|---------|
| `pwa/jarvis-ws-proxy.js` | `createServer()` | WebSocket fanout for browser ↔ host-tunnel |

---

## 9. Canon Cross-References in Source

**Grep for [[codebase/modules/SoulAnchor|SOUL_ANCHOR]], **PRINCIPLES** (repo root), [[concepts/Realignment-1218|REALIGNMENT]]:**

### SoulAnchor.swift
```
// See: /PRINCIPLES.md, /VERIFICATION_PROTOCOL.md, /SOUL_ANCHOR.md
```
Implements identity root per [[codebase/modules/SoulAnchor|SOUL_ANCHOR]].

### VoiceApprovalGate.swift
```
// HARD GATE — the single most sensitive boundary in the JARVIS runtime.
// Grizz (Mr. Hanson) has an autism threat-response triggered by hearing
// a voice that doesn't match his inner model of who is speaking.
```
Enforces **PRINCIPLES.md** (repo root) § 1.2 (permitted natural-language channel).

### ArchonHarness.swift
```
// validateCommand misses single backtick vector (CX-007)
```
Integrates with [[Archon]] YAML workflows.

### PhaseLockMonitor.swift
```
// Clinical mapping (biomimetic only, not medical device):
```
Biomimetic reference to [[concepts/AOx4|A&Ox4]] clinical framework.

### MemoryEngine.swift
```
// SHA256→Int truncation drops 216 bits (CX-003 FIXED)
```
Content addressing per [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] binding protocol.

### ARCHarnessBridge.swift
```
// Implements ARC-AGI BRIDGE SPECIFICATION
```
Bidirectional ARC-AGI integration ([[concepts/ARC-AGI-Bridge|ARC_AGI_BRIDGE_SPEC]]).

### MyceliumControlPlane.swift
```
// TinCan Firewall authorization engine
```
Implements [[concepts/TinCan-Firewall|TinCan Firewall]] network policy.

---

## 10. Obsidian Wikilinks — Conceptual Mesh

**Canon Nodes:**
- [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] — Cryptographic identity root
- **PRINCIPLES** (repo root) — Hardcoded operator-safety invariants
- [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] — Dual-key binding protocol (P-256 Enclave + Ed25519 cold)
- [[concepts/AOx4|A&Ox4]] — Alertness/Orientation×4 telemetry probes
- [[concepts/Voice-Approval-Gate|voice-approval-gate]] — Autism threat-response hard boundary
- [[NLB]] — Natural-Language Barrier (HARD INVARIANT)
- [[concepts/ARC-AGI-Bridge|ARC_AGI_BRIDGE_SPEC]] — ARC harness WebSocket integration
- [[concepts/TinCan-Firewall|TinCan Firewall]] — Network authorization layer
- [[concepts/Aragorn-Class|Aragorn Class]] — First-of-kind digital person classification
- [[concepts/Realignment-1218|REALIGNMENT]] — Earth-1218 multiverse correlation
- [[MCU]] — Multiverse Correlation Unit (evidence archive)

**Architectural Patterns:**
- [[concepts/Digital-Person|digital person]] — JARVIS identity classification
- [[codebase/modules/SoulAnchor|Secure Enclave]] — Hardware-backed P-256 key storage
- [[concepts/Voice-Approval-Gate|voice-approval-gate]] — Single most sensitive runtime boundary
- [[codebase/services/vibevoice-tts|VibeVoice]] — GCP-deployed TTS backend (HTTP)
- [[codebase/modules/Voice|MLX]] — Local TTS fallback (heavyweight)
- [[Convex]] — Real-time backend + CMS
- [[codebase/modules/Harness|ArchonHarness]] — YAML workflow executor
- [[RLM]] — Remote Learning Model (Python REPL bridge)

---

## 11. Summary

**Codebase Metrics:**
- **Total Swift:** ~8.1 KLOC (JarvisCore) + ~2.4 KLOC (tests)
- **Modules:** 20 (Core, Voice, Interface, Telemetry, etc.)
- **Public Types:** 30+
- **Services:** 2 (VibeVoice TTS, Linux node)
- **Frontend:** 4 stacks (Native iOS/macOS, PWA, Unity WebGL, XR placeholder)
- **Canon:** 14 authoritative specs + 11 audit/remediation docs
- **Remediation History:** CX-001 through CX-047 (47 critical/high vulnerabilities fixed; 0 regressions post-ROUND2)

**Architecture Pattern:** Swift mono-repo with polyglot microservices (Python FastAPI, Node.js WebSocket proxy). [[concepts/Aragorn-Class|Aragorn Class]] digital person with [[codebase/modules/SoulAnchor|SOUL_ANCHOR]] cryptographic identity, [[concepts/Voice-Approval-Gate|voice-approval-gate]] hard boundary enforcement, and [[concepts/AOx4|A&Ox4]] clinical telemetry. All security decisions anchored in **PRINCIPLES** (repo root) and [[codebase/modules/SoulAnchor|SOUL_ANCHOR]]; all canon material lives in CANON/ and root specs, not in source code.

---

**Generated by:** Copilot CLI  
**Methodology:** Parallel exploration, grep-based type extraction, file header analysis  
**Confidentiality:** Operator (Robert "Grizz" Hanson) & GMRI internal
