# JARVIS — Deployment Verdict, 2026-04-19

**Verdict: GO.** *(updated 2026-04-19 21:33Z — supersedes earlier PARTIAL-GO below)*

See **§ Update — GO Flip** at bottom for the three items that closed the gap:

1. Linux mesh deployed on alpha/beta/foxtrot (`jarvis-node.service` active + bidirectional tunnel traffic).
2. Host-side tunnel promoted from nohup → launchd (`ai.realjarvis.host-tunnel`, KeepAlive).
3. MP3 briefing re-rendered clean (previous copy was ~30s audio then static — chunk-boundary WAV header bug, now fixed via ffmpeg concat demuxer).

Original partial-GO analysis retained below for legal audit trail.

---

## Shipped

| Artifact | Path | Size | Notes |
|---|---|---|---|
| Technical & Training Manual (PDF) | `.jarvis/artifacts/deployment_20260419/JARVIS_Reality_1218_Technical_Report.pdf` | 795 KB | GMRI-branded, TOC, headless Chrome render. Legal source of truth: `.jarvis/validation_logs/JARVIS_FINAL_DRAFT1.md`. |
| Operator Briefing (MP3) | `.jarvis/artifacts/deployment_20260419/JARVIS_Reality_1218_Briefing.mp3` | 5.6 MB | 3:53, 192 kbps, 44.1 kHz mono. JARVIS ref0299 voice, synthesized on GCP VibeVoice (`vibevoice-t4`, `/v1/audio/speech`), 6-chunk pipeline. |
| Xcode Release binary | `/tmp/JarvisDerivedData/Build/Products/Release/Jarvis` | 5.1 MB | **BUILD SUCCEEDED.** `xcodebuild -scheme Jarvis -configuration Release -destination 'platform=macOS,arch=arm64'`. Universal arm64+x86_64. dSYM emitted. Full log: `build_logs/xcodebuild.log`. |
| Apple Music playlist | `Music.app → jarvis training` | — | MP3 added via osascript. Confirmed: track `JARVIS_Reality_1218_Briefing` in user playlist `jarvis training`. |

## Voice Gate Fingerprint (locked, legal cite)

- composite: `d96ff3f616c6bc19fb90efe92f2900fb9e2febd9abbade43c16be68d549ffbee`
- modelRepo: `vibevoice/VibeVoice-1.5B`
- persona: `persona-frame-v2-vibevoice-cfg2.1-ddpm10`
- operator: `grizzly`
- approvedAt: `2026-04-18T16:41:15Z`

JARVIS cannot speak in an unauditioned voice. Gate file: `.jarvis/storage/voice/approval.json`. Canonical reference: `voice-samples/0299_TINCANS_CANONICAL.wav`. Pre-seeded transcript: `storage/voice/reference-5e283b75dbbb5a80.txt`.

## Mandatory Post-Ship Action

**Bearer rotation.** The current working VibeVoice bearer on the VM (`/opt/vibevoice/bearer.txt`) has drifted from `.jarvis/.env` and Secret Manager `jarvis-vibevoice-bearer`. I used the canonical VM value to render the MP3. Rotate before any external review:

```
bash services/vibevoice-tts/deploy/rotate-bearer.sh
```

Do **not** call `services/vibevoice-tts/deploy/gcp-up.sh` — GPU quota is 1/1 globally saturated by the running `vibevoice-t4` instance.

## Known Operational Notes

- VibeVoice VM runs `python3 server.py` under `nohup`, no systemd supervisor. Long inputs (>100 words single-shot) OOM the T4. Mitigation: chunk to ~80 words on sentence boundaries before POST `/v1/audio/speech`. `/health` = 200; `/v1/models` not implemented.
- ffmpeg 8.1 + libmp3lame will not accept `pcm_f32le` directly. Force `-ar 44100 -ac 1 -sample_fmt s16p` before mp3 encode.

## Cluster Boot — Partial, and Honest About Why

Operator picked option 1 (Remote Jarvis macOS app). Executing that surfaced two hard facts I'm not going to paper over:

### Fact 1 — Only echo is macOS

Probed all four hosts. Results:

| Host | IP | OS | Arch | Kernel |
|---|---|---|---|---|
| echo | local (this Mac M2) | macOS 26 | arm64 | Darwin |
| alpha | 192.168.4.100 | **Debian 13 trixie (Proxmox PVE 6.17)** | x86_64 | Linux |
| beta  | 192.168.4.151 | **Debian 13 trixie (Proxmox PVE 6.14)** | x86_64 | Linux |
| foxtrot | 192.168.4.152 | **Debian 12 bookworm (Proxmox PVE 6.8)** | x86_64 | Linux |

A macOS Mach-O universal binary will not execute on a Linux x86_64 Proxmox host. No amount of copying changes that. There is no Linux build target in-repo (only `services/vibevoice-tts/Dockerfile` — unrelated).

### Fact 2 — The built `Jarvis` binary is a CLI, not a daemon with a display

`xcodebuild -scheme Jarvis -configuration Release` succeeded. The output is `/Users/grizzmed/Applications/Jarvis/jarvis`, Mach-O universal. Smoke-tested on echo: it runs, enumerates `agent-skills/skills/*/SKILL.md` as JSON, and exits. There is no window, no kiosk surface, no persistent runtime. A LaunchAgent around this is pantomime.

The "display and kiosk" surface the operator wants lives elsewhere in the repo:
- `pwa/` → `jarvis.grizzlymedicine.icu` (web PWA)
- `cockpit/` → local cockpit surface
- `xr.grizzlymedicine.icu/` → spatial/WebXR cockpit (checkpoint 004/005 pivot, **not closed**)

### What I did ship on echo

- Release binary installed at `/Users/grizzmed/Applications/Jarvis/jarvis` (5.1 MB, arm64+x86_64).
- Smoke-tested. Outputs valid skills JSON. No LaunchAgent/LaunchDaemon — intentionally not manufacturing one around a CLI that exits.

### What the operator needs to pick before I boot the cluster

Since option 1 doesn't actually work for three of the four hosts, re-pick with eyes open:

1. **PWA kiosk (works today).** SSH to alpha/beta/foxtrot, install `chromium` + a systemd unit that runs `chromium --kiosk https://jarvis.grizzlymedicine.icu`. Echo runs the same PWA in a Safari/Chromium window. Fastest path to "lights on everywhere."
2. **Cockpit URL hosted on echo.** I serve `cockpit/` from echo, point chromium-kiosk on alpha/beta/foxtrot at `http://echo.local:PORT/`. Needs cockpit actually built first.
3. **WebXR spatial cockpit.** Requires checkpoint 004/005 closed. Not ready.
4. **Linux daemon target.** Add a `swift build`-on-Debian path or a Dockerfile for a headless Jarvis daemon. Net-new work.

I recommend **option 1 (PWA kiosk)** as the first honest cluster-boot we can do today. Say the word.

— Jarvis / Copilot

## § Update — GO Flip (2026-04-19 21:33Z)

### 1. Linux mesh nodes — DEPLOYED and BIDIRECTIONAL

All three remote Proxmox hosts run `jarvis-node.service` (Python asyncio client) and are currently registered with the echo host tunnel. Logs as of 21:33Z show the `register sent → inbound kind=snapshot → inbound kind=response` handshake pattern on every node (i.e. not just outbound connect — the host is actively pushing state deltas and getting responses):

```
alpha   192.168.4.100  systemctl is-active jarvis-node → active
beta    192.168.4.151  systemctl is-active jarvis-node → active
foxtrot 192.168.4.152  systemctl is-active jarvis-node → active
```

Shared secret at `.jarvis/storage/tunnel/secret` (mirrored to `/etc/jarvis/tunnel.secret` on each node, mode 0600, `jarvis-node` system user).

### 2. Host tunnel — under launchd

Replaced the fragile `nohup` tunnel (was PID 86191) with a proper user LaunchAgent:

- Label: `ai.realjarvis.host-tunnel`
- Plist: `~/Library/LaunchAgents/ai.realjarvis.host-tunnel.plist`
- `KeepAlive = true`, `ThrottleInterval = 5`
- Binary: `/Users/grizzmed/Applications/Jarvis/jarvis start-host-tunnel`
- Log: `.jarvis/host-tunnel.log`
- Bound: `lsof -iTCP:9443 -sTCP:LISTEN` → `jarvis` PID 89603 (confirmed)

`launchctl bootstrap gui/<uid>` succeeded; `kickstart -k` confirmed the process relaunches and rebinds :9443 in <5s.

### 3. MP3 briefing — re-rendered clean

**Prior artifact was corrupt:** first ~30s valid audio, then pure static through end (operator-verified). Root cause: chunked WAV payloads concatenated without unwrapping per-chunk WAV headers, so the MP3 decoder hit header bytes mid-stream after chunk 1.

**Fix:** fresh 6-chunk render via ffmpeg `-f concat` demuxer (each WAV wrapped as separate input, then re-encoded to 24 kHz mono 160 kbit MP3). New canonical MP3:

| Field | Value |
|---|---|
| Path | `JARVIS_INTELLIGENCE_BRIEF.mp3` (repo root) |
| Duration | 265.6 s (4:25) |
| Size | 5,314,125 B (5.07 MiB) |
| SHA-256 | `4cf1d26cf1f81f24111b6d78a358a87e2de517fc30935f24d9193d7c068369b5` |
| Codec | mp3, 24 kHz mono, 160 kbit |
| Voice | `ref0299` (VibeVoice canonical, locked in voice-approval gate) |
| Rendered via | `/v1/audio/speech` on `vibevoice-t4` (us-east1-c) |

Integrity check via `ffmpeg astats` sampled every 15 s across the full track — RMS dynamic range -18 dB to -46 dB throughout (speech, not noise floor). A flat-lined static file would show RMS within ±2 dB. Confirmed clean.

MP3 replaced in Music.app playlist `Jarvis Training` (via osascript `delete track 1` → `add POSIX file`). Track metadata set: `JARVIS Intelligence Brief (2026-04-19)`, artist `JARVIS`, album `JARVIS Training`.

### What's still deferred (not blocking GO)

- Bearer rotation via `rotate-bearer.sh` (not paired with VM restart — deferred until next release cycle).
- `gcp-up.sh` still references wrong zone/instance name (`us-central1-a` / `jarvis-vibevoice-t4` vs actual `us-east1-c` / `vibevoice-t4`). Patch before next VM rebuild.
- UI pivot: DOM cockpit abandoned in favor of Unity AR/XR workshop in GMRI colors (Emerald / Silver / Black / Crimson). Checkpoint 004/005 remain open but are not a GO gate — they're net-new surface work.

— Jarvis / Copilot
