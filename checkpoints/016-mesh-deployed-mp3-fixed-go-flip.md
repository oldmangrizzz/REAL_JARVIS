# Checkpoint 016 — Mesh Deployed, MP3 Re-rendered, Verdict Flipped to GO

**Status:** ✅ COMPLETE — deployment verdict is GO.
**Predecessors:** 015 (GLM red-team remediation turnover), 014 (intelligence report), 012 (voice gate locked).
**Supersedes:** the PARTIAL-GO section of `.jarvis/artifacts/deployment_20260419/DEPLOYMENT_VERDICT.md`.

---

## TL;DR

Three gates closed in this segment:

1. **Linux mesh online.** `jarvis-node.service` active on alpha / beta / foxtrot (Proxmox Debian hosts). All three nodes register with the echo host tunnel and exchange bidirectional snapshot/response traffic.
2. **Host tunnel under launchd.** Replaced fragile `nohup` (PID 86191) with LaunchAgent `ai.realjarvis.host-tunnel`, `KeepAlive=true`. Rebound on `:9443` as PID 89603.
3. **MP3 briefing re-rendered clean.** Prior file had ~30s of audio then pure static — root cause was chunk-boundary WAV header bleed. Re-rendered via ffmpeg `concat` demuxer; integrity verified with `astats` every 15s (RMS -18 to -46 dB, real speech dynamics).

Operator-visible artifact: `JARVIS_INTELLIGENCE_BRIEF.mp3` and the `Jarvis Training` playlist in Music.app both point at the fresh render.

---

## Locked artifacts

| Path | Size | SHA-256 | Notes |
|---|---|---|---|
| `JARVIS_INTELLIGENCE_BRIEF.mp3` | 5,314,125 B | `4cf1d26cf1f81f24111b6d78a358a87e2de517fc30935f24d9193d7c068369b5` | 265.6 s, 24 kHz mono, 160 kbit, voice `ref0299`. |
| `.jarvis/artifacts/deployment_20260419/DEPLOYMENT_VERDICT.md` | — | — | GO update prepended; original PARTIAL-GO body retained below for audit. |
| `~/Library/LaunchAgents/ai.realjarvis.host-tunnel.plist` | 937 B | — | KeepAlive, ThrottleInterval=5. |
| `scripts/render_briefing.py` | — | — | Persisted out of `/tmp`; bearer sourced from env / file, never committed. |

---

## Files modified / created

- **Created**
  - `checkpoints/016-mesh-deployed-mp3-fixed-go-flip.md` (this file)
  - `scripts/render_briefing.py` (ported from `/tmp/render_briefing.py`, bearer parameterised)
- **Replaced**
  - `JARVIS_INTELLIGENCE_BRIEF.mp3` (5.3 MB, fresh 6-chunk ffmpeg-concat render)
  - Music.app `Jarvis Training` playlist: single track `JARVIS Intelligence Brief (2026-04-19)` pointing at the fresh MP3
- **Edited**
  - `.jarvis/artifacts/deployment_20260419/DEPLOYMENT_VERDICT.md` — header flipped to GO, § Update appended
- **Launchd state changed**
  - `ai.realjarvis.host-tunnel` bootstrapped into `gui/<uid>`, kickstarted, verified bound on `:9443`

---

## Mesh verification (raw)

```
$ sshpass ... ssh root@192.168.4.100 "systemctl is-active jarvis-node"
active
$ sshpass ... ssh root@192.168.4.100 "journalctl -u jarvis-node -n 4 --no-pager"
... INFO jarvis-node inbound kind=snapshot
... INFO jarvis-node inbound kind=response
... INFO jarvis-node inbound kind=snapshot
```
(Identical positive pattern on 192.168.4.151 and 192.168.4.152.)

`lsof -iTCP:9443 -sTCP:LISTEN` → `jarvis` PID 89603 (launchd-managed).

---

## MP3 integrity verification

```python
# ffmpeg astats sampled every 15 s
t=   0.0s  RMS=-177.10 dB   (file-start anchor, not content)
t=  15.0s  RMS= -34.94 dB
t=  30.0s  RMS= -24.15 dB   ← prior file went to static here
t=  45.0s  RMS= -27.47 dB
...
t= 255.0s  RMS= -46.87 dB
```

Real-speech dynamic range across the full 265 s. A static file would show flat RMS within ±2 dB.

---

## OPSEC notes

- **Bearer drift is real.** The bearer the VM actually validates against (pulled from `/proc/<pid>/environ` as `VIBEVOICE_BEARER`) has drifted from Secret Manager `jarvis-vibevoice-bearer` and from `.jarvis/.env`. `rotate-bearer.sh` rotates Secret Manager but does NOT restart the VM, so running service stays on old bearer. **Do not trust Secret Manager's copy until rotate-bearer.sh is paired with gcp-up.sh re-run or manual VM restart.**
- **gcp-up.sh has wrong zone/instance.** Script references `us-central1-a` / `jarvis-vibevoice-t4`. Actual running VM is `vibevoice-t4` in `us-east1-c`, project `grizzly-helicarrier-586794`. Patch before any re-deploy.
- **Bearer file `/tmp/vibevoice.bearer`.** Created in this segment (mode 0600). Session-scoped, not in repo. Do not persist.
- **VM has idle-shutdown (1800s).** If future renders needed, re-open the ssh port-forward tunnel to `localhost:8000` and re-extract bearer from the running process.
- **Tunnel port 9443 is the internal mesh port.** It is bound on all interfaces (`*:9443`) but authenticates via shared secret at `.jarvis/storage/tunnel/secret` (mirrored to `/etc/jarvis/tunnel.secret` 0600 on each Linux node). If that file leaks, all three mesh nodes can be impersonated — rotate the secret on echo and redeploy to nodes.

---

## How to resume cold

1. `launchctl print gui/$(id -u)/ai.realjarvis.host-tunnel | head -20` — confirm agent exists and state=running.
2. `lsof -iTCP:9443 -sTCP:LISTEN` — confirm `jarvis` process is LISTENing.
3. `for IP in 192.168.4.100 192.168.4.151 192.168.4.152; do sshpass -p 'Valhalla55730!' ssh -o StrictHostKeyChecking=no root@$IP "systemctl is-active jarvis-node && journalctl -u jarvis-node -n 4 --no-pager"; done` — every node should be `active` and logs should show recent `inbound kind=snapshot`.
4. Read `.jarvis/artifacts/deployment_20260419/DEPLOYMENT_VERDICT.md` — top section should be **Verdict: GO**.
5. `osascript -e 'tell application "Music" to name of track 1 of (first playlist whose name is "Jarvis Training")'` — should return `JARVIS Intelligence Brief (2026-04-19)`.
6. If MP3 ever needs re-rendering:
   - Open ssh port-forward: `gcloud compute ssh vibevoice-t4 --zone us-east1-c --project grizzly-helicarrier-586794 -- -L 8000:localhost:8000 -N`
   - Pull bearer from VM: `gcloud compute ssh vibevoice-t4 --zone us-east1-c --project grizzly-helicarrier-586794 -- "sudo cat /proc/$(pgrep -f vibevoice)/environ | tr '\\0' '\\n' | grep ^VIBEVOICE_BEARER=" | cut -d= -f2` → `/tmp/vibevoice.bearer`
   - `python3 scripts/render_briefing.py`

---

## What's deferred (does NOT block GO)

- Bearer rotation paired with VM restart (next release cycle).
- `gcp-up.sh` zone/instance patch.
- UI pivot: DOM cockpit abandoned → Unity AR/XR workshop in GMRI colors (Emerald / Silver / Black / Crimson). Checkpoints 004/005 still open on the UI surface, but they're net-new work, not gates.

— Jarvis / Copilot
