# workshop-unity

**Path:** `workshop/Unity/`
**Dirs:** `Assets/`, `Packages/`, `ProjectSettings/`

## Purpose
Unity project implementing the **3D Workshop** — the spatial cockpit
where JARVIS and the operator meet in Earth-1218 visualization space
(GMRI / Stark Tower-inspired environment). Built headless to WebGL and
loaded by [[codebase/frontend/pwa|the PWA]].

## Build
- Script: `scripts/build-unity-webgl.sh` (local) + `scripts/mesh-unity-build.sh`.
- Beta remote headless: `/usr/local/bin/run-unity-build.sh` on
  `192.168.4.151` (xvfb-run wrapping Unity 2022.3.62f1 batchmode).
- Editor entry point: `Assets/Editor/JarvisBuild.cs`.
- Output: `.unityweb` gzipped → `pwa/Build/`.

## Notes
- Unity on Linux as root requires `--no-sandbox` as electron flag
  *before* subcommands.
- License activation uses bundled
  `UnityLicensingClient_V1/Unity.Licensing.Client` with the Hub bearer
  token decrypted from encryptedTokens.json via keychain + Electron
  safeStorage.

## Related
- [[codebase/frontend/pwa]]
- [[concepts/Realignment-1218]]
