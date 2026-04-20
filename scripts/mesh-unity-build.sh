#!/usr/bin/env bash
# Builds Unity WebGL on the mesh (beta host) using project scaffold from echo.
# Storage layout (on alpha, NFS-exported, mounted by beta at /mnt/shared):
#   /workshop/shared/unity-dl/         <- Unity editor + WebGL module tarballs
#   /workshop/shared/unity/            <- extracted editor (runs from here)
#   /workshop/shared/workshop-unity/   <- project (rsynced from echo:workshop/Unity)
#   /workshop/shared/unity-build/      <- WebGL output (rsynced back to echo:pwa/Build)
set -euo pipefail

ALPHA_IP="${ALPHA_IP:-192.168.4.100}"
BETA_IP="${BETA_IP:-192.168.4.151}"
PASS="${MESH_SSH_PASS:-Valhalla55730!}"
REPO="${REPO:-/Users/grizzmed/REAL_JARVIS}"

ssh_alpha() { sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no root@"$ALPHA_IP" "$@"; }
ssh_beta()  { sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no root@"$BETA_IP"  "$@"; }

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "== 1/7 wait for alpha downloads =="
while :; do
  LINES=$(ssh_alpha "wc -l < /workshop/shared/unity-dl/dl.log 2>/dev/null || echo 0")
  [[ "$LINES" -ge 2 ]] && break
  ssh_alpha "ls -l /workshop/shared/unity-dl/*.tar.xz 2>/dev/null | awk '{print \$5, \$9}'"
  sleep 30
done
log "downloads complete"

log "== 2/7 extract Unity on alpha NFS =="
ssh_alpha 'cd /workshop/shared/unity-dl && \
  mkdir -p /workshop/shared/unity/2022.3.62f1 && \
  tar -xJf Unity-2022.3.62f1.tar.xz -C /workshop/shared/unity/2022.3.62f1 && \
  tar -xJf UnitySetup-WebGL-Support.tar.xz -C /workshop/shared/unity/2022.3.62f1 && \
  ls /workshop/shared/unity/2022.3.62f1/'

log "== 3/7 rsync project echo→alpha via beta NFS =="
# echo pushes to beta, which writes through NFS to alpha's /workshop/shared
sshpass -p "$PASS" rsync -az --delete \
  "$REPO/workshop/Unity/" \
  root@"$BETA_IP":/mnt/shared/workshop-unity/

log "== 4/7 ensure beta has build deps =="
ssh_beta 'apt-get -qq update >/dev/null 2>&1 && apt-get install -y --no-install-recommends xvfb libgbm1 libpulse0 libnss3 libxss1 libxtst6 2>&1 | tail -3 || true'

log "== 5/7 run headless WebGL build on beta =="
ssh_beta "mkdir -p /mnt/shared/unity-build /mnt/shared/unity-logs && \
  UNITY=/mnt/shared/unity/2022.3.62f1/Editor/Unity && \
  [[ -x \$UNITY ]] || { echo 'unity binary missing at '\$UNITY; exit 2; } && \
  cd /mnt/shared/workshop-unity && \
  JARVIS_BUILD_OUT=/mnt/shared/unity-build xvfb-run -a \$UNITY \
    -batchmode -nographics -quit \
    -projectPath /mnt/shared/workshop-unity \
    -executeMethod JarvisBuild.BuildWebGL \
    -buildTarget WebGL \
    -buildOutput /mnt/shared/unity-build \
    -logFile /mnt/shared/unity-logs/build.log \
  || { echo '=== tail build.log ==='; tail -200 /mnt/shared/unity-logs/build.log; exit 3; }"

log "== 6/7 rsync WebGL output beta→echo =="
mkdir -p "$REPO/pwa/Build"
# Unity writes <out>/Build/<productName>.* + <out>/index.html + <out>/TemplateData/
# The PWA loader already expects Build/ relative to pwa/, so pull the inner Build dir.
sshpass -p "$PASS" rsync -az --delete \
  root@"$BETA_IP":/mnt/shared/unity-build/Build/ \
  "$REPO/pwa/Build/"

log "== 7/7 done. ls pwa/Build =="
ls -la "$REPO/pwa/Build/"
