#!/usr/bin/env bash
set -euo pipefail

ROOT="${JARVIS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PY="${JARVIS_MEMORY_BRIDGE_PYTHON:-$HOME/.jarvis/cognee-venv/bin/python}"
BRIDGE_DIR="$HOME/.claude/vendor/cognee-integrations/integrations/claude-code/scripts"
CONFIG="$HOME/.claude/letta-runtime/bridge.json"
SECRET_FILE="${JARVIS_MEMORY_SECRET_FILE:-$HOME/.copilot/session-state/73fc96b2-c7f7-4b54-9242-4a8085c6a866/files/jarvis-memory.secret}"
RECALL_URL="${JARVIS_MEMORY_RECALL_URL:-http://100.98.95.75:9470/recall}"

ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; }

printf 'Jarvis memory doctor\n'
printf 'repo: %s\n\n' "$ROOT"

if [[ -x "$PY" ]]; then
  ok "bridge Python: $PY"
  if "$PY" - <<'PY' >/dev/null 2>&1
import cognee
PY
  then
    ok "Cognee import works"
  else
    fail "Cognee import failed in bridge Python"
  fi
else
  fail "bridge Python missing or not executable: $PY"
fi

if [[ -f "$CONFIG" ]]; then
  ok "Letta bridge config exists"
  "$PY" - <<'PY' "$CONFIG" 2>/dev/null || true
import json, sys
cfg = json.load(open(sys.argv[1]))
print(f"INFO Letta base_url: {cfg.get('base_url', '<missing>')}")
print(f"INFO Letta agent_id: {cfg.get('agent_id', '<missing>')}")
PY
else
  fail "Letta bridge config missing: $CONFIG"
fi

if "$PY" - <<'PY' "$CONFIG" >/tmp/jarvis-memory-doctor-letta.out 2>/dev/null
import json, sys, urllib.request
cfg = json.load(open(sys.argv[1]))
base = cfg["base_url"].rstrip("/")
for path in ("/health", "/v1/health", "/v1/agents"):
    try:
        with urllib.request.urlopen(base + path, timeout=3) as resp:
            print(path, resp.status)
            raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(1)
PY
then
  ok "Letta API reachable"
else
  warn "Letta API not reachable at configured base_url"
fi

if [[ -f "$SECRET_FILE" ]]; then
  ok "remote Cognee recall secret file exists"
else
  warn "remote Cognee recall secret file missing"
fi

if [[ -f "$SECRET_FILE" ]] && "$PY" - <<'PY' "$SECRET_FILE" "$RECALL_URL" >/tmp/jarvis-memory-doctor-recall.out 2>/dev/null
import json, sys, urllib.request
token = open(sys.argv[1], encoding="utf-8").read().strip()
req = urllib.request.Request(
    sys.argv[2],
    data=json.dumps({"query": "REAL_JARVIS memory bridge Cognee Letta context"}).encode("utf-8"),
    method="POST",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=20) as resp:
    data = json.loads(resp.read().decode("utf-8"))
hits = len(data.get("GRAPH_COMPLETION", [])) + len(data.get("CHUNKS", []))
print(hits)
raise SystemExit(0 if hits else 1)
PY
then
  ok "remote Cognee recall returns hits"
else
  warn "remote Cognee recall did not return hits"
fi

if [[ -f "$BRIDGE_DIR/bridge-context-lookup.py" ]]; then
  payload='{"prompt":"REAL_JARVIS memory bridge Cognee Letta context"}'
  if printf '%s' "$payload" | "$PY" "$BRIDGE_DIR/bridge-context-lookup.py" >/tmp/jarvis-memory-doctor-context.out 2>/tmp/jarvis-memory-doctor-context.err; then
    if grep -q 'Cognee graph/session memory' /tmp/jarvis-memory-doctor-context.out; then
      ok "prompt-time bridge injects Cognee context"
    elif grep -q 'additionalContext' /tmp/jarvis-memory-doctor-context.out; then
      warn "prompt-time bridge injects context, but no Cognee section"
    else
      warn "prompt-time bridge ran but returned no additional context"
    fi
  else
    fail "prompt-time bridge failed"
  fi
else
  fail "prompt-time bridge script missing"
fi
