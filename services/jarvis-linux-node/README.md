# jarvis-linux-node

Satellite mesh node for REAL_JARVIS.

Every host in the mesh runs this daemon (CANON §5.1). It connects to the
Swift `JarvisHostTunnelServer` on echo (port 9443), registers itself with a
stable machine ID + role, and emits a heartbeat every 30s.

**Wire compatibility is exact** — same ChaCha20-Poly1305 envelope, same
`JarvisTransportPacket` framing, same `JarvisTunnelMessage` payloads as the
Swift/Apple side.

## Files
- `jarvis_node.py` — the daemon (Python 3 asyncio, single file)
- `jarvis-node.service` — systemd unit
- `install.sh` — idempotent installer

## Deploy (per host)
```bash
export JARVIS_HOST_ADDR=192.168.7.114
export JARVIS_TUNNEL_SECRET="$(cat echo:/Users/grizzmed/REAL_JARVIS/.jarvis/storage/tunnel/secret)"
export JARVIS_NODE_ROLE=node-alpha
sudo -E bash install.sh
```

## Operate
```bash
systemctl status jarvis-node
journalctl -u jarvis-node -f
```

## Rotate secret
1. Rewrite `.jarvis/storage/tunnel/secret` on echo, restart host tunnel.
2. `scp` new secret, re-run `install.sh` with new `JARVIS_TUNNEL_SECRET`.
