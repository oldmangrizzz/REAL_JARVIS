#!/bin/bash
# scripts/n8n-verify.sh
# Verifies that all expected workflows are active in n8n
# Requires: N8N_BASE_URL, N8N_API_KEY environment variables

set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-}"
N8N_API_KEY="${N8N_API_KEY:-}"

if [[ -z "$N8N_BASE_URL" || -z "$N8N_API_KEY" ]]; then
    echo "ERROR: N8N_BASE_URL and N8N_API_KEY environment variables are required"
    exit 1
fi

echo "=== n8n Workflow Verification ==="
echo "Base URL: $N8N_BASE_URL"
echo ""

# Fetch all active workflows
if ! workflows=$(curl -s -X GET \
    "$N8N_BASE_URL/api/v1/workflows?filter=active" \
    -H "Authorization: Bearer $N8N_API_KEY" 2>&1); then
    echo "ERROR: Failed to fetch workflows from n8n"
    exit 1
fi

# Expected workflow names (from n8n/workflows/*.json)
declare -a EXPECTED_WORKFLOWS=(
    "jarvis-daily-briefing"
    "jarvis-forge-self-heal"
    "ha-call-service"
    "mesh-display-broadcast"
    "scene-downstairs-on"
    "scene-upstairs-on"
)

# Extract active workflow names from response
ACTIVE_WORKFLOWS=$(echo "$workflows" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sort | uniq)

echo "Expected workflows:"
for wf in "${EXPECTED_WORKFLOWS[@]}"; do
    echo "  - $wf"
done

echo ""
echo "Active workflows in n8n:"
echo "$ACTIVE_WORKFLOWS" | while read wf; do
    [[ -n "$wf" ]] && echo "  - $wf"
done

echo ""
echo "=== Verification Results ==="

# Check each expected workflow
MISSING=0
for expected in "${EXPECTED_WORKFLOWS[@]}"; do
    if echo "$ACTIVE_WORKFLOWS" | grep -q "^$expected$"; then
        echo "✓ $expected is active"
    else
        echo "✗ $expected is NOT active (missing or inactive)"
        ((MISSING++))
    fi
done

if [[ $MISSING -eq 0 ]]; then
    echo ""
    echo "All expected workflows are active!"
    exit 0
else
    echo ""
    echo "$MISSING workflow(s) missing or inactive"
    exit 1
fi
