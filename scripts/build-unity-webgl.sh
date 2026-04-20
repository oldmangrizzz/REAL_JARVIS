#!/usr/bin/env bash
# build-unity-webgl.sh — headless Unity batch build for JARVIS workshop.
# Writes Build/{jarvis-workshop.{loader.js,data,framework.js,wasm}} into pwa/Build/.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/workshop/Unity"
OUT="$REPO/pwa/Build"
UNITY_VERSION="$(awk '/m_EditorVersion:/ {print $2}' "$PROJECT/ProjectSettings/ProjectVersion.txt")"
UNITY_BIN="/Applications/Unity/Hub/Editor/${UNITY_VERSION}/Unity.app/Contents/MacOS/Unity"

if [[ ! -x "$UNITY_BIN" ]]; then
  echo "Unity $UNITY_VERSION not installed at $UNITY_BIN" >&2
  echo "Install via Unity Hub, then re-run this script." >&2
  exit 2
fi

mkdir -p "$OUT"
"$UNITY_BIN" -batchmode -nographics -quit \
  -projectPath "$PROJECT" \
  -executeMethod GMRI.Build.BuildWebGL \
  -buildTarget WebGL \
  -logFile - \
  -customBuildPath "$OUT"

echo "Built → $OUT"
ls -la "$OUT"
