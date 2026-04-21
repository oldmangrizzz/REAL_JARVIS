# Operator Pairing Guide — Phase 2 Residual Tasks

**Purpose:** These integrations require you (the operator) to physically interact with a device or
enter credentials. Jarvis cannot pair them alone.

**Do these when you have 15 min of calm time. Not urgent — none of them block the grind.**

HA URL: **http://192.168.7.199:8123**
Log in with the credentials stored in session files (HA_USER / HA_PASS in ha.env).

---

## Order (easiest → hardest)

### 1. Room-labeling the Wiz bulbs (5 min, no pairing needed)
The 9 Wiz bulbs are paired, but Jarvis doesn't know which one is in which room.

Go to **Settings → Devices & Services → WiZ**. For each bulb:
- Click the bulb entry
- Rename it to what it is (e.g. "Living Room Floor Lamp", "Kitchen Overhead")
- Set the Area to **Downstairs** or **Upstairs** (create the areas if they don't exist)

If you don't know which is which: use Jarvis's "blink test" — ask him to toggle each entity one at a
time. Whichever bulb blinks, that's the one.

### 2. eero Pro 6 — cloud pairing (2 min)
Settings → Devices & Services → **Add Integration** → type `eero` → Continue.
It will ask for your eero/Amazon email. You'll get a 6-digit code via email or SMS. Enter it. Done.

### 3. Apple TVs (5 min per TV)
Settings → Devices & Services — you'll see two "Apple TV" cards under **Discovered**.
- Click **Configure** on `living room apple tv`.
- HA will show a PIN. Read the PIN from the Apple TV screen and type it into HA.
- Skip `Mom & Dad's AppleTV` unless you want HA to control it too.

### 4. HomePod minis (5 min)
For each HomePod in **Discovered**, click **Configure**. Same PIN flow as Apple TV. If a HomePod is
missing, open the Home app on iPhone and confirm it's still there; power-cycle if necessary.

### 5. Fire TV (10 min)
Settings → Devices & Services → **Add Integration** → `Android TV Remote` (not ADB).
Enter the Fire TV's IP (find it in Fire TV Settings → Network → See status).
The Fire TV will display a 4-digit pairing code — enter it into HA.

### 6. Nanoleaf panels (5 min per controller, only if powered)
If the Nanoleaf controller is powered and on the network:
Settings → Devices & Services → **Add Integration** → `Nanoleaf` → enter controller IP.
Then **hold the power button on the Nanoleaf controller for 5 seconds** (lights flash) WHILE HA is
waiting. That grants HA permission.

If Nanoleaf is powered off, no action — Jarvis will re-scan when you power it on.

### 7. Echo Shows (15 min — requires HACS)
This is the only integration that requires a custom install. Jarvis will install HACS itself in the
next work block, then come back and ask for your Amazon account password when it's time. No action
from you until then.

---

## What Jarvis does NOT need you for
- n8n workflows (already running on Alpha LXC 119)
- Swift ConversationEngine TODOs (pure code work)
- Forge orchestration (already running on Delta)
- Voice canon (Coqui XTTS already locked)
- All 9 Wiz bulbs already paired

Reply `done` to Jarvis after each numbered step and he'll verify and move on.
