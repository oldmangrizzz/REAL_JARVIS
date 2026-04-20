# Deployment

Where each piece of the system actually runs in production, and how it
gets there.

## Mac (operator host)
- **Runtime:** the `Jarvis` CLI / `JarvisMac` app on the operator's
  Mac (macOS 14+). This is the **operator-ON-the-loop** trust root.
- **Soul Anchor:** ratified locally via Secure Enclave (P-256) +
  cold Ed25519 root. See [[codebase/modules/SoulAnchor]].
- **Tunnel:** `ai.realjarvis.host-tunnel.plist` (launchd agent) keeps
  the tunnel node up. See [[codebase/services/jarvis-linux-node]].

## Mobile / Watch
- **Distribution:** built from `project.yml` → `Jarvis.xcodeproj` via
  XcodeGen + Xcode. Archive + TestFlight (no public App Store release
  intended at this time).
- **Runtime constraint:** mobile + watch are **voice-approval-gated
  consumers** — they cannot render audio or act on sensitive commands
  without a gate approval from the Mac.

## VibeVoice TTS service
- **Host:** GCP VM, spot instance.
- **Layout:** `services/vibevoice-tts/app.py` (FastAPI) + `synthesizer.py`.
- **Auth:** `VIBEVOICE_BEARER` env var.
- **Scale policy:** idle-unload after `VIBEVOICE_IDLE_SECONDS` (default 1800s).
- **Endpoints:** `/tts/synthesize`, `/healthz`, `/readyz`, `/stats`.
- See [[codebase/services/vibevoice-tts]].

## jarvis-linux-node
- **Hosts:** Linux box + Mac (LaunchAgent).
- **Protocol:** newline-framed TCP → `JarvisTransportPacket`
  → base64(ChaCha20-Poly1305 sealed box) → `JarvisTunnelMessage`.
- **Port:** 9443.
- **Key derivation:** SHA-256(sharedSecret).
- See [[codebase/services/jarvis-linux-node]].

## Convex backend
- **Host:** Convex cloud.
- **Schema:** `convex/schema.ts` — tables `execution_traces`,
  `stigmergic_signals`, `recursive_thoughts`.
- **Write pattern:** best-effort from Telemetry (REPAIR-021 made URL +
  auth configurable).
- See [[codebase/backend/convex]].

## PWA
- **Stack:** nginx + Unity WebGL (gzipped `.unityweb` artifacts) + WS
  proxy. `docker-compose.yml` + override for local.
- **Artifacts:** Unity `Build/` ships with `decompressionFallback`
  enabled.
- **Deploy:** `docker-compose up` on the PWA host. See
  [[codebase/frontend/pwa]].

## Cockpit
- Static / Vite-style build, served alongside PWA. See
  [[codebase/frontend/cockpit]].

## Workshop Unity (WebGL)
- **Build host:** `beta` (192.168.4.151), Unity 2022.3.62f1, headless
  via xvfb-run. `/usr/local/bin/run-unity-build.sh` wraps Unity; output
  lands in `/mnt/shared/unity-build/Build/`.
- **Shipped into:** `pwa/Build/` (committed artifact) and consumed by
  `pwa/unity-loader.js`.
- **License:** Personal, activated via Unity Hub (see
  *"unity licensing"* memory).
- See [[codebase/frontend/workshop-unity]].

## xr.grizzlymedicine.icu
- Static site; see `xr.grizzlymedicine.icu/`.

## Archon workflows
- **Where they run:** `Archon/` DAGs (`default_workflow.yaml`) are
  executed from the operator's workstation. Validation step invokes
  `xcodebuild`. See [[codebase/workflows/archon]].

## Cold-path / emergency
- **Lockdown:** `scripts/jarvis-lockdown.zsh` — halts voice pipeline
  and tunnel.
- **Cold signing:** see `scripts/jarvis_cold_sign_setup.md` and
  `scripts/secure_enclave_p256.swift`.

## Doctrine
> Deploy surfaces are **consumers**, not peers. Every remote surface
> respects [[concepts/NLB]] and the [[concepts/Voice-Approval-Gate]].
> Production = operator-ON-the-loop always.

## See also
- [[reference/ENTRY_POINTS]]
- [[reference/DEPENDENCIES]]
- [[reference/BUILD_AND_TEST]]
- [[architecture/TRUST_BOUNDARIES]]
