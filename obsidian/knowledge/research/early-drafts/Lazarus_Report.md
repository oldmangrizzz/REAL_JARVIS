# Lazarus Glass Recovery Report
**Date:** 2026-03-14T18:39Z
**Target:** Proxmox Host (192.168.7.232) — 5K iMac Internal Panel (eDP-1)

## Diagnosis

### Root Cause
SDDM was launching `workshop-kiosk.desktop` through the **Wayland session wrapper** (`/etc/sddm/wayland-session`) because the `.desktop` file was symlinked into `/usr/share/wayland-sessions/`. No Wayland compositor exists on the host → `sddm-helper` exited immediately with code 1 → black screen.

### Evidence
- `card1-eDP-1`: **connected** (GPU healthy, amdgpu Polaris10, 4GB VRAM)
- SDDM log: `Starting: "/etc/sddm/wayland-session /usr/local/bin/workshop-kiosk.sh"` → `sddm-helper exited with 1`
- Xorg log: `AIGLX: Suspending AIGLX clients for VT switch` (X server started but session never held)

## Recovery Actions

1. **Removed** `/usr/share/wayland-sessions/workshop-kiosk.desktop` (symlink)
2. **Updated** `/usr/local/bin/workshop-kiosk.sh`:
   - Added `--no-sandbox` (required for root)
   - Added `xrandr --output eDP-1` resolution force
   - Added `xset s noblank`, `--disable-features=TranslateUI`, `--autoplay-policy=no-user-gesture-required`
3. **Cleared** stale `.Xauthority` files
4. **Restarted** SDDM → now launches via `/etc/sddm/Xsession` (X11 path)

## Post-Recovery Status

| Component | Status |
|-----------|--------|
| GPU (amdgpu Polaris10) | ✅ 4GB VRAM, fb0 primary |
| Panel (eDP-1) | ✅ Connected, 3840x2160@60Hz |
| SDDM | ✅ Active, session started |
| Chromium Kiosk | ✅ PID 8751, rendering http://192.168.7.233:5173 |
| GPU Process | ✅ ozone-platform=x11, gpu-rasterization enabled |
| Workshop Frontend (LXC 101:5173) | ✅ Serving |

**THE GLASS IS AWAKE.**
