#!/usr/bin/env bash
# jarvis-linux-node installer — idempotent, runs on alpha/beta/foxtrot.
#
# Inputs:
#   STAGE_DIR  — directory this script was unpacked into (default: script dir)
#
# Environment (written to /etc/jarvis/node.env on target):
#   JARVIS_HOST_ADDR       — echo LAN IP (required)
#   JARVIS_HOST_PORT       — 9443
#   JARVIS_TUNNEL_SECRET   — shared secret matching echo's .jarvis/storage/tunnel/secret
#   JARVIS_NODE_ROLE       — e.g. node-alpha, node-beta, node-foxtrot
set -euo pipefail

STAGE_DIR="${STAGE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

: "${JARVIS_HOST_ADDR:?JARVIS_HOST_ADDR required}"
: "${JARVIS_TUNNEL_SECRET:?JARVIS_TUNNEL_SECRET required}"
JARVIS_HOST_PORT="${JARVIS_HOST_PORT:-9443}"
JARVIS_NODE_ROLE="${JARVIS_NODE_ROLE:-node-$(hostname -s)}"

echo "[jarvis-node] target host=${JARVIS_HOST_ADDR}:${JARVIS_HOST_PORT} role=${JARVIS_NODE_ROLE}"

# Deps — python3-cryptography covers ChaCha20Poly1305.
if ! python3 -c 'import cryptography' >/dev/null 2>&1; then
  echo "[jarvis-node] installing python3-cryptography"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends python3 python3-cryptography
fi

install -d -m 0755 /opt/jarvis-node
install -d -m 0755 /var/log/jarvis /var/lib/jarvis
install -d -m 0700 /etc/jarvis

install -m 0755 "${STAGE_DIR}/jarvis_node.py"   /opt/jarvis-node/jarvis_node.py
install -m 0644 "${STAGE_DIR}/README.md"        /opt/jarvis-node/README.md 2>/dev/null || true

# Write /etc/jarvis/node.env atomically (mode 600 — contains secret).
umask 077
cat > /etc/jarvis/node.env.tmp <<EOF
JARVIS_HOST_ADDR=${JARVIS_HOST_ADDR}
JARVIS_HOST_PORT=${JARVIS_HOST_PORT}
JARVIS_TUNNEL_SECRET=${JARVIS_TUNNEL_SECRET}
JARVIS_NODE_ROLE=${JARVIS_NODE_ROLE}
JARVIS_LOG_LEVEL=INFO
EOF
chmod 0600 /etc/jarvis/node.env.tmp
mv /etc/jarvis/node.env.tmp /etc/jarvis/node.env

install -m 0644 "${STAGE_DIR}/jarvis-node.service" /etc/systemd/system/jarvis-node.service

systemctl daemon-reload
systemctl enable jarvis-node.service >/dev/null
systemctl restart jarvis-node.service

sleep 2
systemctl --no-pager --full status jarvis-node.service | head -20 || true
echo "[jarvis-node] installed."
