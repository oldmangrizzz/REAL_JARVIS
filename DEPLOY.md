# DEPLOY.md

Deployment procedure for JARVIS production systems.

## 1. Pre-flight Checks

Verify all required infrastructure nodes are operational:

| Node | Hostname | Address | Service |
|------|----------|---------|---------|
| Alpha | alpha | 192.168.4.100 | Proxmox cluster root, Letta LXC 201, n8n LXC 119, HAOS VM 200 |
| Beta | beta | 192.168.4.151 | Loom (Docker), Foxtrot container |
| Charlie | charlie | 76.13.146.61 | Reverse proxy, ntfy, Traefik, certbot |
| Delta | delta | 187.124.28.147 | XTTS v2 TTS, Forge daemon, Ollama gateway |
| Echo | echo | 192.168.7.114 | Operator Mac, desktop bridge, CLI agent |
| Foxtrot | foxtrot | 192.168.4.152 | Display agent (container on Beta) |

**Pre-flight checklist:**
- [ ] Alpha Proxmox cluster online (verify SSH: `ssh alpha 'pveversion'`)
- [ ] Beta Docker online (verify SSH: `ssh beta 'docker ps'`)
- [ ] Charlie VPS online (verify SSH: `ssh charlie 'systemctl status traefik'`)
- [ ] Delta XTTS service online (verify HTTP: `curl https://delta.grizzlymedicine.icu:8787/health`)
- [ ] Echo desktop bridge running (verify HTTP: `curl http://127.0.0.1:8765/listen`)
- [ ] Foxtrot display container online (verify SSH via Beta: `docker exec foxtrot systemctl status mesh-display`)

## 2. Required Environment Variables

Every deployment context must define these env vars before running services:

| Variable | Source File | Default | Notes |
|----------|-------------|---------|-------|
| `JARVIS_CANON_TTS_HOST` | environment (shell), DeltaXTTSBackend.swift | `delta.grizzlymedicine.icu` | XTTS v2 host; CANONICAL, no fallback |
| `JARVIS_CANON_TTS_PORT` | environment (shell), DeltaXTTSBackend.swift | `8787` | XTTS v2 port; CANONICAL |
| `JARVIS_TTS_BEARER` | environment (shell), DeltaXTTSBackend.swift | `<ROTATE_ME>` | Bearer token for Delta XTTS auth |
| `JARVIS_DELTA_HOST` | environment (shell), services/voice_canon_validator.py | `delta.grizzlymedicine.icu` | Delta node hostname |
| `JARVIS_DELTA_ADMIN_TOKEN` | environment (shell), n8n/workflows/forge-self-heal.json | `<ROTATE_ME>` | Bearer token for Forge restart API |
| `N8N_API_KEY` | environment (shell), scripts/n8n-activate.sh | `<ROTATE_ME>` | n8n REST API key |
| `N8N_BASE_URL` | environment (shell), scripts/n8n-activate.sh | `http://192.168.4.119:5678` | n8n server URL |
| `JARVIS_DISPLAY_ALLOWED_HOSTS` | environment (shell), services/mesh-display-agent.py | `grizzlymedicine.icu,*.grizzlymedicine.icu` | Allowlist for display URLs |
| `JARVIS_LETTA_EXCLUSIVE` | environment (shell), Jarvis/Sources/JarvisCore/Memory/LettaBridge.swift | `true` | Require Letta exclusivity |
| `JARVIS_COUCHDB_PASSPHRASE` | ~/.jarvis/secrets/couchdb.passphrase (file) | N/A | Read-only from secrets file |
| `SHARED_SECRET` | environment (shell), pwa/docker-compose.yml | `<ROTATE_ME>` | PWA WebSocket shared secret |
| `JARVIS_CANON_CONNECT_TIMEOUT` | environment (shell), DeltaXTTSBackend.swift | `10000` (ms) | XTTS connect timeout |
| `JARVIS_CANON_REQUEST_TIMEOUT` | environment (shell), DeltaXTTSBackend.swift | `45000` (ms) | XTTS request timeout |

See the `env.example` file at repo root for complete template.

## 3. Deployment Order

Deploy nodes in order from infrastructure to application layer:

### 3.1 Alpha (Proxmox infrastructure)

Proxmox cluster is the foundation. LXCs and VMs depend on it.

```bash
# On operator machine, verify cluster health:
ssh alpha 'pveversion && pvecm status'

# If rebooting needed:
ssh alpha 'sudo shutdown -r now'

# Wait ~2 min for reboot, then verify:
ssh alpha 'pveversion'
```

**Expected output:** Proxmox version > 8.0, QUORUM OK

### 3.2 Alpha → Letta LXC 201

Letta is the long-term memory backend for JARVIS.

```bash
# On Alpha:
ssh alpha 'sudo qm start 201'
sleep 30

# Verify Letta is running:
ssh alpha 'curl http://192.168.4.121:8080/docs'

# Check logs:
ssh alpha 'lxc-attach -n 201 -- systemctl status letta'
```

**Expected:** HTTP 200 at LXC 201's Letta API endpoint

### 3.3 Alpha → n8n LXC 119

n8n is Jarvis's workflow execution layer.

```bash
# On Alpha:
ssh alpha 'sudo qm start 119'
sleep 30

# Verify n8n is running:
ssh alpha 'curl http://192.168.4.119:5678'

# Import and activate workflows (once n8n is up):
export N8N_BASE_URL='http://192.168.4.119:5678'
export N8N_API_KEY='<from-operator>'
bash scripts/n8n-activate.sh
bash scripts/n8n-verify.sh
```

**Expected:** HTTP 200 at n8n, all workflows active per `n8n-verify.sh`

### 3.4 Alpha → HAOS VM 200

Home Assistant provides smart home integration.

```bash
# On Alpha:
ssh alpha 'sudo qm start 200'
sleep 60

# Verify HAOS is running:
ssh alpha 'curl http://192.168.7.199:8123'

# Create Home Assistant long-lived token (operator action):
# 1. Open HA UI at http://192.168.7.199:8123
# 2. Profile icon (bottom left) → Long-Lived Access Tokens
# 3. Create one, save value to ha-token.txt (operator should store securely)
```

**Expected:** HA login page at 192.168.7.199:8123

### 3.5 Beta (Loom container host)

Beta hosts Docker and Foxtrot display container.

```bash
# Verify Beta is reachable:
ssh beta 'docker ps'

# If Docker not running:
ssh beta 'sudo systemctl start docker'

# Verify Foxtrot display container:
ssh beta 'docker ps | grep foxtrot'

# If not running, start it:
ssh beta 'docker-compose -f /opt/loom/docker-compose.yml up -d foxtrot'
```

**Expected:** Docker running, Foxtrot container present

### 3.6 Charlie (Reverse proxy + DNS)

Charlie is the public internet-facing reverse proxy.

```bash
# Verify Charlie is reachable:
ssh charlie 'systemctl status traefik'

# Check certificate status:
ssh charlie 'certbot certificates'

# All domains (*.grizzlymedicine.icu) should have active certs expiring >7 days

# Verify routing to backends:
curl https://forge.grizzlymedicine.icu/healthz
curl https://tts.grizzlymedicine.icu/health
curl https://n8n.grizzlymedicine.icu
```

**Expected:** Traefik running, certs valid, proxies responding

### 3.7 Delta (TTS + Forge core)

Delta is the XTTS v2 voice backend and Forge dark factory.

```bash
# Verify Delta XTTS is running:
curl https://delta.grizzlymedicine.icu:8787/health

# Verify Forge daemon is running:
ssh delta 'sudo systemctl status jarvis-forge.service'

# Check Forge logs:
ssh delta 'tail -50 /opt/swarm-forge/logs/forge.log'

# If Forge is down, start it:
ssh delta 'sudo systemctl start jarvis-forge.service'

# Verify Ollama gateway:
ssh delta 'curl http://localhost:11434/api/tags'
```

**Expected:** XTTS returns HTTP 200, Forge service running, Ollama gateway online

### 3.8 Echo (Operator desktop bridge)

Echo is the operator's Mac running the desktop control bridge.

```bash
# On Echo (operator's machine):
sudo launchctl start com.grizz.jarvis.echo-bridge
sleep 2

# Verify bridge is running:
curl http://127.0.0.1:8765/listen

# Test voice input (requires microphone):
curl -X POST http://127.0.0.1:8765/listen
```

**Expected:** Bridge responds to HTTP requests, voice input works

### 3.9 Foxtrot (Display agent)

Foxtrot displays JARVIS output on a screen.

```bash
# Verify via Beta:
ssh beta 'docker exec foxtrot curl http://localhost:8080/status'

# If display agent is stuck, restart:
ssh beta 'docker restart foxtrot'
```

**Expected:** Display agent HTTP endpoint responds

## 4. Convex Deploy

Convex is the backend-as-a-service for JARVIS.

```bash
# Ensure convex.json exists at repo root:
cat convex.json

# Expected fields (stub if missing):
# {
#   "team": "<OPERATOR-TEAM-ID>",
#   "project": "jarvis-forge-e5b07",
#   "prodUrl": "TBD",
#   "devUrl": "TBD"
# }

# Deploy to Convex:
npx convex deploy

# To rollback to a previous deployment:
# 1. Find previous version: npx convex deployments
# 2. Revert: npx convex deployments promote <version>
```

**Expected:** Convex deployment succeeds, functions deployed

## 5. n8n Workflow Activation

Workflows are activated in section 3.3. If re-running:

```bash
export N8N_BASE_URL='http://192.168.4.119:5678'
export N8N_API_KEY='<from-operator>'
bash scripts/n8n-activate.sh
bash scripts/n8n-verify.sh
```

## 6. Voice Canon Verification

JARVIS must speak with the canonical voice. Manual verification:

```bash
# Trigger a test utterance:
# (Example: via Echo bridge or Forge CLI)

# Check that audio output uses XTTS v2 from Delta:
tail -10 ~/.jarvis/alignment_tax/voice_canon_failures.log

# Should be empty (no failures). If there are entries, canon gate rejected TTS.

# Verify PRINCIPLES.md voice canon lock:
grep -A5 "CANON LAW.*VOICE" PRINCIPLES.md

# Must state: XTTS v2, Delta:8787, no fallbacks, silent on failure
```

**Expected:** No canon gate failures logged, voice output audibly matches reference

## 7. Soul Anchor Verification

PRINCIPLES.md, SOUL_ANCHOR.md, and VERIFICATION_PROTOCOL.md must be dual-signed.

```bash
# Verify signatures exist:
ls -la PRINCIPLES.md.p256.sig PRINCIPLES.md.ed25519.sig
ls -la SOUL_ANCHOR.md.p256.sig SOUL_ANCHOR.md.ed25519.sig
ls -la VERIFICATION_PROTOCOL.md.p256.sig VERIFICATION_PROTOCOL.md.ed25519.sig

# Verify signatures:
bash scripts/verify_dual_sig.sh PRINCIPLES.md
bash scripts/verify_dual_sig.sh SOUL_ANCHOR.md
bash scripts/verify_dual_sig.sh VERIFICATION_PROTOCOL.md

# All should exit 0
```

**Expected:** All files signed, both signatures verify, exit code 0

## 8. Post-Deploy Smoke Tests

Run these HTTP checks to verify all public endpoints are responsive:

### TTS (Voice)

```bash
# XTTS health check:
curl -I https://delta.grizzlymedicine.icu:8787/health
# Expected: HTTP 200
```

### PWA (Web Interface)

```bash
# PWA UI:
curl -I https://pwa.grizzlymedicine.icu/
# Expected: HTTP 200 or 307 (redirect)
```

### Forge Dashboard

```bash
# Forge dashboard:
curl -I https://forge.grizzlymedicine.icu/
# Expected: HTTP 200
```

### n8n UI

```bash
# n8n interface:
curl -I https://n8n.grizzlymedicine.icu/
# Expected: HTTP 200 or 302 (redirect to login)
```

### Convex Functions

```bash
# Convex is deployed via npx convex deploy (section 4).
# Verify via Convex Dashboard: https://dashboard.convex.dev/

# Or test a function (example):
curl -X POST https://convex-prod-url/api/function \
  -H "Authorization: Bearer <convex-token>"
# Expected: HTTP 200 with function result
```

## 9. Rollback

Rollback per-node as needed:

### Swift Services (Jarvis)

```bash
# Rollback to previous build:
git log --oneline | head -5
git reset --hard <previous-commit>
swift build --package-path Jarvis -c release

# Restart service (on Echo or deployment host):
sudo launchctl stop com.grizz.jarvis.runtime
sudo launchctl start com.grizz.jarvis.runtime
```

### Convex

```bash
# List previous deployments:
npx convex deployments

# Promote a previous version to prod:
npx convex deployments promote <version-id>
```

### systemd Services (Delta, Foxtrot)

```bash
# Revert a systemd unit to previous version:
sudo systemctl revert jarvis-forge.service
sudo systemctl daemon-reload
sudo systemctl start jarvis-forge.service

# Or manually rollback with git + service restart:
ssh delta 'cd /opt/swarm-forge && git reset --hard <previous-commit>'
ssh delta 'sudo systemctl restart jarvis-forge.service'
```

### Docker Services (Beta Foxtrot)

```bash
# Rollback image tag:
ssh beta 'docker-compose -f /opt/loom/docker-compose.yml \
  config | grep foxtrot-image'

# Edit docker-compose.yml to point to previous image tag:
ssh beta 'sed -i "s|foxtrot:latest|foxtrot:previous|" /opt/loom/docker-compose.yml'
ssh beta 'docker-compose -f /opt/loom/docker-compose.yml up -d foxtrot'
```

### Letta, n8n (Proxmox LXCs)

```bash
# Snapshot current state (on Alpha):
ssh alpha 'sudo lxc-snapshot -n 201 -n letta-pre-deploy'
ssh alpha 'sudo lxc-snapshot -n 119 -n n8n-pre-deploy'

# To rollback:
ssh alpha 'sudo lxc-restore -n 201 -s letta-pre-deploy'
ssh alpha 'sudo qm start 201'
```

## 10. Sign-Off Checklist

Deployment is complete when all items are verified:

**Infrastructure:**
- [ ] All six nodes (Alpha, Beta, Charlie, Delta, Echo, Foxtrot) online and responsive
- [ ] Pre-flight checklist (section 1) complete
- [ ] All environment variables (section 2) set and validated
- [ ] No credentials from environment variables are expired or revoked

**Services:**
- [ ] Alpha Proxmox, Letta (LXC 201), n8n (LXC 119), HAOS (VM 200) running
- [ ] Beta Docker and Foxtrot container running
- [ ] Charlie Traefik and certs valid
- [ ] Delta XTTS and Forge online
- [ ] Echo desktop bridge responsive
- [ ] n8n workflows imported and active (section 3.3)
- [ ] Convex deployed (section 4)

**Verification:**
- [ ] Post-deploy smoke tests pass (section 8)
- [ ] Voice canon verification passes (section 6)
- [ ] Soul anchor signatures verified (section 7)
- [ ] No errors in `.jarvis/alignment_tax/` logs
- [ ] No failed canon gate events logged

**Reference:**
- See `VERIFICATION_PROTOCOL.md` §3 for detailed phase report format
- See `SOUL_ANCHOR.md` §7 for dual-signature requirements
- See `PRINCIPLES.md` §CANON LAW for voice enforcement rules

---

**Document Status:** TBD fields require operator input. See `OPERATOR_ACTIONS.md` for required actions.
