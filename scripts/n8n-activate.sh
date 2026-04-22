#!/bin/bash
# scripts/n8n-activate.sh
# Imports and activates all workflows from n8n/workflows/ directory
# Requires: N8N_BASE_URL, N8N_API_KEY environment variables

set -euo pipefail

N8N_BASE_URL="${N8N_BASE_URL:-}"
N8N_API_KEY="${N8N_API_KEY:-}"

if [[ -z "$N8N_BASE_URL" || -z "$N8N_API_KEY" ]]; then
    echo "ERROR: N8N_BASE_URL and N8N_API_KEY environment variables are required"
    exit 1
fi

WORKFLOWS_DIR="n8n/workflows"
if [[ ! -d "$WORKFLOWS_DIR" ]]; then
    echo "ERROR: Directory $WORKFLOWS_DIR not found"
    exit 1
fi

IMPORT_COUNT=0
ACTIVATE_COUNT=0
FAILED=0

echo "=== n8n Workflow Activation ==="
echo "Base URL: $N8N_BASE_URL"
echo ""

for workflow_file in "$WORKFLOWS_DIR"/*.json; do
    [[ ! -f "$workflow_file" ]] && continue
    
    workflow_name=$(basename "$workflow_file" .json)
    echo -n "Processing $workflow_name..."
    
    # Import the workflow
    if ! response=$(curl -s -X POST \
        "$N8N_BASE_URL/api/v1/workflows" \
        -H "Authorization: Bearer $N8N_API_KEY" \
        -H "Content-Type: application/json" \
        -d @"$workflow_file" 2>&1); then
        echo " FAILED (import request error)"
        ((FAILED++))
        continue
    fi
    
    # Extract workflow ID from response
    workflow_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$workflow_id" ]]; then
        echo " FAILED (could not extract workflow ID from response)"
        ((FAILED++))
        continue
    fi
    
    ((IMPORT_COUNT++))
    echo -n " imported (ID: $workflow_id),"
    
    # Activate the workflow
    if ! activate_response=$(curl -s -X PATCH \
        "$N8N_BASE_URL/api/v1/workflows/$workflow_id" \
        -H "Authorization: Bearer $N8N_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"active":true}' 2>&1); then
        echo " activation FAILED"
        ((FAILED++))
        continue
    fi
    
    ((ACTIVATE_COUNT++))
    echo " activated ✓"
done

echo ""
echo "=== Summary ==="
echo "Imported: $IMPORT_COUNT"
echo "Activated: $ACTIVATE_COUNT"
echo "Failed: $FAILED"

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo "All workflows imported and activated successfully."
    exit 0
else
    echo ""
    echo "Some workflows failed to import or activate."
    exit 1
fi
