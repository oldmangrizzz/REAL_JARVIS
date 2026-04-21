# MARK II COMPLETION — PRODUCT REQUIREMENTS DOCUMENT

**Classification:** Operational Blueprint — Repo-Root, Canon-Adjacent
**Version:** 1.0.0 — Mark II Close-Out
**Date:** 2026-04-20
**Issued by:** Operator of Record (Robert "Grizz" Hanson, GMRI)
**Executor:** Jarvis Fabricator Forge (Delta VPS) — Ralph Wiggum recursive loop, Obsidian wiki retrieval, SHIELD (Fury+Hill) adversarial review
**Successor:** `MARK_III_VISION.md` (to be drafted after Mark II ships)

---

## 0. Preamble — What This Document Is

This is the **close-out blueprint** for the Jarvis Mark II deployment. It is not aspirational. It is a ledger of what must land, in what order, under what invariants, to declare Mark II shipped and move the program to Mark III.

Every epic in this PRD is decomposed into a **Forge-executable spec** under `Construction/<Lane>/spec/MK2-EPIC-NN-*.md`. The Forge cooks each spec under Ralph's recursive loop (plan → exec → verify → SHIELD → repeat) until it ships or Ralph terminates with a verifiable failure mode.

The operator cannot read code. Operator acceptance is judged by:
- **iMessage push** from forge to +16823718439 when a task ships or needs attention.
- **Dashboard** at `https://forge.grizzlymedicine.icu` for green/red state.
- **Smoke scripts** under `scripts/smoke/` that answer yes/no on whether each surface works.

---

## 1. Ground Truth — What Exists Today (2026-04-20)

### 1.1 Canon (locked, signature-gated)

- `PRINCIPLES.md` — NLB hard invariant, hardware sovereignty, operator-on-loop model.
- `SOUL_ANCHOR.md` — dual-root crypto identity (P-256 Secure Enclave + Ed25519 cold).
- `VERIFICATION_PROTOCOL.md` — read/write fences for this repo.
- `CANON/corpus/` — biographical terminus, post-terminus quarantine.

**Mark II must not mutate canon.** Any epic that touches canon MUST escalate to operator review before merge.

### 1.2 Shipped Swift surfaces (verified real)

| Target | Entry point | Status |
|---|---|---|
| macOS CLI (`jarvis`) | `Jarvis/App/main.swift` | REAL, 133 LOC |
| macOS Desktop Cockpit (@main App) | `Jarvis/Mac/AppMac/RealJarvisMacApp.swift` | REAL — **needs Xcode target wiring (EPIC-01)** |
| iPhone client | `Jarvis/Mobile/AppiPhone/RealJarvisPhoneApp.swift` | REAL |
| iPad client | `Jarvis/Mobile/AppiPad/RealJarvisPadApp.swift` | REAL |
| watchOS client | `Jarvis/Watch/Extension/RealJarvisWatchApp.swift` | REAL |
| Tunnel client/server + ChaCha20-Poly1305 crypto | `Shared/JarvisShared`, `MobileShared/JarvisMobileShared`, `Host/JarvisHostTunnelServer.swift` | REAL |
| Voice approval gate + HTTP TTS backend | `Voice/VoiceApprovalGate.swift`, `Voice/HTTPTTSBackend.swift` | REAL |
| Intent pipeline (IntentParser → CapabilityRegistry → DisplayCommandExecutor) | `Interface/*.swift` | REAL |
| Memory engine (knowledge graph, SHA256, witness telemetry) | `Memory/MemoryEngine.swift` | REAL |
| Master oscillator + phase-lock monitor | `Oscillator/*.swift` | REAL |
| Pheromind (stigmergic routing) | `Pheromind/*.swift` | REAL |
| Physics bridge (stub) + ARC grid adapter | `Physics/*.swift`, `ARC/*.swift` | REAL — **end-to-end path incomplete (EPIC-03)** |
| Soul Anchor (dual-root signing) | `SoulAnchor/SoulAnchor.swift` | REAL — **rotation scripts missing (EPIC-08)** |
| WiFi environment scanner (RSSI proximity) | `Network/WiFiEnvironmentScanner.swift`, `PresenceDetector.swift` | REAL (RSSI-based, not true CSI) |
| Display bridges (DDC, AirPlay, HDMI-CEC, HTTP) | `Interface/{AirPlay,HDMICEC,HTTPDisplay}Bridge.swift` | REAL — **runtime hardware untested on mesh (EPIC-09 smoke)** |

**Test suite:** ≥100 passing. **Build gate:** `xcodebuild build -scheme Jarvis -destination 'platform=macOS,arch=arm64'` green.

### 1.3 Services (external)

- `services/vibevoice-tts/` — legacy GCP T4 TTS; kept as fallback.
- `services/f5-tts/` — new TTS (VOICE-001, in flight via forge).
- `services/jarvis-linux-node/` — Linux node orchestrator.

### 1.4 Clients / Frontends

- `pwa/index.html` — 1062-line PWA cockpit; real WebSocket tunnel.
- `xr.grizzlymedicine.icu/` — WebXR portal rewritten (GAP-002 done).
- `the_workshop.html` — A-Frame 1.7.1 workshop (knowledge graph renderer).

### 1.5 Forge (the builder that executes this PRD)

- `/opt/swarm-forge/` on Delta VPS.
- Ralph recursive loop: 15 iters / 400k tokens / 3600s / stagnation=3.
- Obsidian wiki retrieval: ripgrep over `obsidian/knowledge/**/*.md` (161 pages), lane-aware.
- SHIELD adversarial gate: Fury (red team) + Hill (build verifier).
- Auto-merge: squash to main on `full` verify + `ship` verdict.
- iMessage notify via ntfy → imsg bridge (+16823718439).

### 1.6 Known debt (inherited)

From `PRODUCTION_HARDENING_SPEC.md`:
- **SPEC-007** Tunnel authorization self-assertion — client asserts its own role. Unresolved. (→ EPIC-02)
- **SPEC-008** Destructive command guardrails — no two-man rule on destructive mesh actions. (→ EPIC-02)
- **SPEC-009/010/011** Pheromone engine thread safety, oscillator deadlock, tunnel buffer accumulation — verify each is closed or spec to close. (→ EPIC-02 audit)

From `GAP_CLOSING_STATUS.md`:
- **GAP-005 visionOS** skipped (needs SDK). (→ EPIC-10)
- **GAP-001 macOS** files created but **no Xcode target entry** — app doesn't launch via double-click yet. (→ EPIC-01)

From the forge task board (in-flight):
- `VOICE-001-f5-tts-swap` (Gemini) — Ralph iter 1 in progress.
- `VOICE-002-realtime-speech-to-speech` (Gemini) — pending.
- `NAV-001-universal-navigation-engine` (GLM) — pending.
- `AMBIENT-001/002-watch-gateway` (Qwen) — pending + prior phantom-ship repair queued.
- `UX-001-navigation-surfaces` (Qwen) — pending.

---

## 2. Mark II End-State — Definition of Done

Mark II ships when **every one of these is true**:

1. **Build green on every target.** `xcodebuild build` succeeds for every scheme in `jarvis.xcworkspace`: macOS CLI, macOS App, iPhone, iPad, Watch, PWA assets verified, visionOS stub compiles (behind `#if canImport(RealityKit) && os(visionOS)` guard).
2. **Tests pass.** ≥130 tests, 0 failures. All new epic tests (~30 added across EPICs) present.
3. **One-command deploy.** `scripts/ship-mark-ii.sh` runs: builds, signs, smoke-tests, pushes PWA to `grizzlymedicine.icu`, deploys F5-TTS service to GCP, restarts watchdog, posts a completion artifact to Convex. Exits non-zero on any failure.
4. **Voice pipeline live end-to-end.** Operator speaks into mac → voice gate passes (approved fingerprint) → transcript → intent → display action on target monitor. Measured latency ≤ 1.5 s end-to-end on local network (excluding TTS render).
5. **Ambient gateway wired.** Watch captures audio → tunnel → host STT → voice gate → intent pipeline. AMBIENT-001 spec accepted, smoke path passes.
6. **Tunnel authorization bounded.** Client cannot self-assert role. Server issues role-scoped tokens signed with host key. Destructive commands require explicit `--confirm` header echoing the command hash.
7. **Soul Anchor rotation drill passes.** `scripts/soul-anchor/rotate.sh` produces a new key pair, dual-signs a canon test artifact, verifies signatures, and rolls back cleanly. Operator completes one live drill, result logged to `Storage/soul-anchor/rotation.log`.
8. **ARC-AGI end-to-end submission.** `scripts/arc/submit.sh <task-file.json>` loads a task into physics, runs RLM, emits a proposed grid, writes submission JSON, and logs a telemetry decision. Does not require network to demonstrate; demo uses canned task.
9. **Dashboard shows operator-useful state.** `https://forge.grizzlymedicine.icu` displays: active Ralph iter per task, last 20 telemetry events, mesh-display health, voice gate state, RustDesk pill. Updates within 3 s of state change.
10. **CI canon-gate.** Any PR that modifies `PRINCIPLES.md`, `SOUL_ANCHOR.md`, `VERIFICATION_PROTOCOL.md`, or `CANON/**` is blocked unless it carries a dual signature artifact. Enforced by `scripts/ci/canon-gate.sh` executed in GitHub Actions.

If any of (1)–(10) is red, Mark II is **not** shipped. Ralph continues.

---

## 3. Non-Goals (explicit — do NOT do as part of Mark II)

- MuJoCo production physics. Stub physics engine is sufficient for Mark II ARC demo.
- Full WebXR immersive ARC competition scoring UI. Mark III.
- HomeKit write-paths (dimming lights, locks). Read-only status is Mark II; writes are Mark III.
- Multi-operator support. Single-operator only in Mark II.
- Full F5-TTS fleet autoscaling. One-VM-per-region is Mark II.
- Aragorn-class persona pairing (JARVIS ↔ Aragorn NLB conversation). Mark III, spec exists in canon.
- Post-terminus MCU corpus ingestion. Remains quarantined in Mark II.

---

## 4. Mark II Epics

Each epic below is a **single Forge task** with a dedicated spec under `Construction/<Lane>/spec/MK2-EPIC-NN-*.md`. Lane assignment follows the Forge's lane→model map (Gemini→voice; GLM→infra/nav; Nemotron→verification/security; Qwen→ambient/UX/data).

| EPIC | Title | Lane | Depends on | Priority |
|---|---|---|---|---|
| **MK2-EPIC-01** | Xcode workspace target wiring | GLM | — | P0 |
| **MK2-EPIC-02** | Tunnel authorization + destructive guardrails | Nemotron | EPIC-01 | P0 |
| **MK2-EPIC-03** | ARC-AGI end-to-end submission path | GLM | EPIC-01 | P1 |
| **MK2-EPIC-04** | Memory graph persistence + recall API | Qwen | — | P1 |
| **MK2-EPIC-05** | Voice pipeline unification | Gemini | VOICE-001, VOICE-002 (in flight) | P0 |
| **MK2-EPIC-06** | Navigation + CarPlay completion | GLM | UX-001, NAV-001 (in flight) | P1 |
| **MK2-EPIC-07** | Telemetry + dashboard enrichment | Qwen | EPIC-01 | P1 |
| **MK2-EPIC-08** | Soul Anchor rotation + CI canon gate | Nemotron | — | P0 |
| **MK2-EPIC-09** | One-command deploy + smoke suite | GLM | EPIC-01, 05, 06 | P0 |
| **MK2-EPIC-10** | visionOS thin client (behind SDK gate) | Qwen | EPIC-01 | P2 |

**Dependency graph (execution order hint for Ralph):**

```
EPIC-01 ─┬─> EPIC-02 ─┐
         ├─> EPIC-03  │
         ├─> EPIC-06  ├─> EPIC-09 (deploy)
         ├─> EPIC-07  │
         └─> EPIC-10  │
EPIC-04  ─────────────┤
EPIC-05  ─────────────┤
EPIC-08  ─────────────┘
```

P0 epics block Mark II ship. P1 are strongly desired. P2 ships if green; otherwise deferred to Mark III.

---

## 5. Invariants Every Epic Must Preserve

The Forge will be adversarially tested against each of these by SHIELD. Violations = auto-reject.

1. **NLB** (PRINCIPLES §1). No epic may introduce shared vector stores, shared MCP servers, shared skill registries, or any binary/tensor agent-to-agent channel between JARVIS and any other persona. Natural-language-only exchange.
2. **Hardware sovereignty** (PRINCIPLES §2). No epic may borrow another persona's model weights, voice seed, memory tier, or secrets. Everything dedicated.
3. **Voice gate primacy** (SOUL_ANCHOR §3). Voice synthesis may not bypass `VoiceApprovalGate`. Approval files are model-fingerprint-bound; model swap = re-audition.
4. **Soul Anchor immutability** (SOUL_ANCHOR §1). No epic signs canon-touching artifacts without dual-root participation. Operational artifacts may be P-256-single-signed.
5. **Telemetry witness** (MemoryEngine). Every state mutation emits a JSONL telemetry event with SHA256 witness. Tests verify tamper detection.
6. **No phantom ships.** SHIELD Fury rejects any completion that claims ship without corresponding verified diff. This is how VOICE-002 and AMBIENT-002 got rejected before.
7. **Operator-on-loop boundary** (PRINCIPLES §1.3). Anything exceeding standing protocol (canon mutation, external financial action, irreversible-at-scale op) escalates to operator — iMessage + dashboard red pill.
8. **Strict Concurrency.** Swift 6 strict-concurrency must stay enabled. No `@unchecked Sendable` additions without a justification block in the diff.

---

## 6. Execution Protocol

### 6.1 Per-epic Forge cycle

1. Operator commits this PRD + lane specs to main.
2. Forge ignition scans `Construction/<Lane>/spec/MK2-EPIC-*.md`, seeds each as a task.
3. Ralph cooks one task at a time per worker slot (Delta currently has 1 slot).
4. On **ship**, squash-merge to main, push, iMessage notify, mark done.
5. On **needs_repair**, Fury findings are written to `<task>.repair.md`; requeued automatically.
6. On **needs_spec_clarification** (3 empty plans), Ralph tapsout; operator edits spec; requeue.
7. Dashboard reflects state.

### 6.2 Cross-epic coordination

Epics with dependencies are marked `depends_on:` in their frontmatter. The planner reads wiki + prior response artifacts (`Construction/<Lane>/response/`) to avoid re-deriving shared assumptions.

### 6.3 Escalation

If **any three consecutive epics** hit `needs_spec_clarification` or fail SHIELD twice, the Forge halts and posts an iMessage digest. Operator inspects, edits, resumes.

---

## 7. Definition of Mark III (forward reference — NOT scope)

Mark III begins when Mark II is declared shipped per §2. Mark III scope is drafted separately and will address: MuJoCo physics, HomeKit writes, WebXR competition UI, F5-TTS autoscale, Aragorn persona-pair NLB protocol, multi-operator, post-terminus corpus handling, ARC-AGI live competition submission.

Mark III is **explicitly out of scope for this PRD**. Do not pre-build it into Mark II epics. Premature generalization is rejected by SHIELD.

---

## 8. Acceptance

This PRD is accepted when:
- Committed to `main` at `REAL_JARVIS/MARK_II_COMPLETION_PRD.md`.
- 10 lane specs land under `Construction/<Lane>/spec/MK2-EPIC-NN-*.md`.
- Forge ingests all 10 on next ignition and emits iMessage: `MK2 PRD ingested — 10 epics queued`.

Signed: **Operator** (procedural acknowledgement — cryptographic signatures applied per SOUL_ANCHOR §4 on first canon reference by any shipped artifact).

— end PRD —
