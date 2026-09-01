#!/bin/bash

# Activate n8n workflows for Menu Matcher
# Uses n8n API to create and activate workflows

N8N_URL="https://mono-mcp-server.dhhmena.com/api/v1"
API_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMzFmN2UxMC1jNWY3LTQ0MTEtOTA0Ny1iNjAzNDkwZDFiNTkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzg2MjkwMTg2fQ.BaTxc5SKV6WuHd94AAHEv0PjHi4PKWpdVe9G7asZrIg"

echo "🚀 Activating n8n Workflows..."

# Workflow 1: Claude Smart Matching
echo -e "\n[1/4] Creating Claude Smart Matching workflow..."
curl -s -X POST "$N8N_URL/workflows" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Claude Smart Matching",
    "active": true,
    "nodes": [
      {
        "parameters": {
          "path": "menu-matcher-match-item",
          "responseMode": "onReceived",
          "httpMethod": "POST"
        },
        "id": "webhook_trigger",
        "name": "Webhook",
        "type": "n8n-nodes-base.webhook",
        "typeVersion": 1,
        "position": [250, 300]
      },
      {
        "parameters": {
          "url": "https://api.anthropic.com/v1/messages",
          "method": "POST",
          "headers": {
            "anthropic-version": "2023-06-01",
            "x-api-key": "sk-IQvLbdYLZFl1Ph_FN_n9hg"
          },
          "bodyParametersUi": "json",
          "body": "{\"model\":\"claude-opus-5\",\"max_tokens\":200,\"messages\":[{\"role\":\"user\",\"content\":\"Menu item: {{$json.item_name}}\\nCategory: {{$json.category}}\\nCandidates: {{$json.candidates}}\\n\\nRespond JSON: {\\\"selected_index\\\": <num>, \\\"confidence\\\": <0-1>}\"}]}"
        },
        "id": "claude_request",
        "name": "Call Claude",
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 3,
        "position": [450, 300]
      }
    ],
    "connections": {
      "Webhook": {
        "main": [[{"node": "Call Claude", "type": "main"}]]
      }
    }
  }' | jq -r '.data.id'

echo "✅ Workflow 1 created"

# Workflow 2: Smart Suggestions
echo -e "\n[2/4] Creating Smart Suggestions Ranker..."
curl -s -X POST "$N8N_URL/workflows" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Smart Suggestions Ranker",
    "active": true,
    "nodes": [
      {
        "parameters": {
          "path": "menu-matcher-smart-suggestions",
          "responseMode": "onReceived",
          "httpMethod": "POST"
        },
        "id": "webhook_trigger",
        "name": "Webhook",
        "type": "n8n-nodes-base.webhook",
        "typeVersion": 1,
        "position": [250, 300]
      },
      {
        "parameters": {
          "url": "https://api.anthropic.com/v1/messages",
          "method": "POST",
          "headers": {
            "anthropic-version": "2023-06-01",
            "x-api-key": "sk-IQvLbdYLZFl1Ph_FN_n9hg"
          },
          "bodyParametersUi": "json",
          "body": "{\"model\":\"claude-opus-5\",\"max_tokens\":500,\"messages\":[{\"role\":\"user\",\"content\":\"Rank images for {{$json.item_name}}. Respond JSON: {\\\"scores\\\": [{\\\"index\\\": <num>, \\\"score\\\": <0-100>}]}\"}]}"
        },
        "id": "claude_ranker",
        "name": "Rank Suggestions",
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 3,
        "position": [450, 300]
      }
    ],
    "connections": {
      "Webhook": {
        "main": [[{"node": "Rank Suggestions", "type": "main"}]]
      }
    }
  }' | jq -r '.data.id'

echo "✅ Workflow 2 created"

# Workflow 3: Library Sync
echo -e "\n[3/4] Creating Library Sync workflow..."
curl -s -X POST "$N8N_URL/workflows" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Library Sync",
    "active": true,
    "nodes": [
      {
        "parameters": {
          "path": "menu-matcher-library-sync",
          "responseMode": "onReceived",
          "httpMethod": "POST"
        },
        "id": "webhook_trigger",
        "name": "Webhook",
        "type": "n8n-nodes-base.webhook",
        "typeVersion": 1,
        "position": [250, 300]
      }
    ]
  }' | jq -r '.data.id'

echo "✅ Workflow 3 created"

# Workflow 4: Image Generation
echo -e "\n[4/4] Creating Image Generation workflow..."
curl -s -X POST "$N8N_URL/workflows" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Image Generation",
    "active": true,
    "nodes": [
      {
        "parameters": {
          "path": "menu-matcher-gen-image",
          "responseMode": "onReceived",
          "httpMethod": "POST"
        },
        "id": "webhook_trigger",
        "name": "Webhook",
        "type": "n8n-nodes-base.webhook",
        "typeVersion": 1,
        "position": [250, 300]
      }
    ]
  }' | jq -r '.data.id'

echo "✅ Workflow 4 created"

echo -e "\n════════════════════════════════════════════════════════════"
echo "✅ All n8n workflows created and activated!"
echo "════════════════════════════════════════════════════════════"
