# pwa

**Path:** `pwa/`
**Files:**
- `index.html`, `manifest.json`, `sw.js` — PWA shell.
- `unity-loader.js` — loader for Unity WebGL artifacts.
- `Build/` — output of Unity headless build (`.unityweb` gzipped, per
  `scripts/build-unity-webgl.sh`).
- `jarvis-ws-proxy.js`, `ws-proxy/` — WebSocket proxy → tunnel bridge.
- `nginx.conf`, `nginx.local.conf` — edge.
- `docker-compose.yml`, `docker-compose.override.yml` — deployment.
- `jarvis.yml` — PWA config.
- `icons/`

## Purpose
Progressive Web App cockpit. Loads the Unity
[[codebase/frontend/workshop-unity|workshop]] WebGL build and talks to
JARVIS over a WebSocket proxy that fronts the
[[codebase/modules/Host|tunnel server]].

## Deployment
- Nginx serves the shell + Unity artifacts.
- `jarvis-ws-proxy.js` translates browser WS frames ↔ tunnel packets.
- Runs via docker-compose on the edge host.

## Invariants
- Unity build artifacts are **gzipped `.unityweb`** with
  `decompressionFallback` enabled.
- PWA **cannot** authorize voice playback — any voice output still has
  to clear the Mac's [[concepts/Voice-Approval-Gate]].

## Related
- [[codebase/frontend/workshop-unity]]
- [[codebase/modules/Host]]
- `scripts/build-unity-webgl.sh`
- [[reference/DEPLOYMENT]]
