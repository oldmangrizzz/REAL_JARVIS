# n8n — Jarvis Workflow Engine

## Location
- **Host**: Alpha (192.168.4.100), LXC CTID **119**, hostname `n8n`
- **LAN IP**: 192.168.4.119/22 (bridge vmbr0)
- **NetBird pivot**: 100.98.134.89 (alpha) :5678 → DNAT → 192.168.4.119:5678
- **Public URL**: https://n8n.grizzlymedicine.icu (Traefik/Charlie, Let's Encrypt)
- **Runtime**: Docker `n8nio/n8n:latest`, compose file at `/root/compose.yml` in LXC
- **Data volume**: `/var/lib/n8n` on host LXC, mounted to `/home/node/.n8n`

## Resources
- 2 vCPU, 2048 MB RAM, 512 MB swap, 8 GB rootfs on `workshop` ZFS pool
- Unprivileged, nesting enabled (required for Docker-in-LXC)

## Auth
- Basic auth ACTIVE. Credentials + encryption key in `~/.copilot/session-state/73fc96b2-c7f7-4b54-9242-4a8085c6a866/files/n8n.env` (chmod 600).
- Keys: `n8n_root_pw` (LXC root), `n8n_encryption_key`, `n8n_basic_auth_user`, `n8n_basic_auth_password`.

## Reverse Proxy
- Config: `/opt/pangolin/config/traefik/n8n.yml` on Charlie (76.13.146.61)
- Route: `n8n.grizzlymedicine.icu` → `http://100.98.134.89:5678`
- TLS via Let's Encrypt (certResolver: letsencrypt)

## NAT / Transport
On Alpha (persisted via `iptables-persistent`):
```
iptables -t nat -A PREROUTING -i wt0 -p tcp --dport 5678 -j DNAT --to-destination 192.168.4.119:5678
iptables -t nat -A POSTROUTING -p tcp -d 192.168.4.119 --dport 5678 -j MASQUERADE
```
ip_forward enabled via `/etc/sysctl.d/99-n8n-forward.conf`.

## Ops Commands
```bash
# Container health
ssh root@192.168.4.100 "pct exec 119 -- docker ps"
ssh root@192.168.4.100 "pct exec 119 -- docker logs n8n --tail 50"

# Restart
ssh root@192.168.4.100 "pct exec 119 -- docker compose -f /root/compose.yml restart"

# Upgrade
ssh root@192.168.4.100 "pct exec 119 -- bash -c 'cd /root && docker compose pull && docker compose up -d'"

# Backup data volume
ssh root@192.168.4.100 "pct exec 119 -- tar czf /tmp/n8n-backup-\$(date +%F).tgz -C /var/lib/n8n ."
```

## Health Check
- Internal: `curl -I http://192.168.4.119:5678/` → 200
- External: `curl -I https://n8n.grizzlymedicine.icu/` → 200

## Phase Integration
- Phase 3 uses n8n to bridge Jarvis ⇄ Home Assistant (webhooks both directions)
- Phase 5 uses n8n workflows for voice-intent → service-call routing
- Phase 6 uses n8n for self-healing monitors and forge orchestration
