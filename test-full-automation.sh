#!/bin/bash

# Menu Matcher Full Automation Test
# Tests all components: App, API, Webhooks, n8n integration

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MENU_MATCHER="https://menu-matcher.lths.ai"
N8N_BASE="https://mono-mcp-server.dhhmena.com/n8n"
API_KEY="sk-IQvLbdYLZFl1Ph_FN_n9hg"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}🚀 Menu Matcher Full Automation Test${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

PASSED=0
FAILED=0

# Test function
test_endpoint() {
  local name=$1
  local url=$2
  local method=$3
  local data=$4

  echo -e "${YELLOW}[TEST] $name${NC}"

  if [ "$method" = "POST" ]; then
    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
      -H "Content-Type: application/json" \
      -d "$data")
  else
    response=$(curl -s -w "\n%{http_code}" -X GET "$url")
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    echo -e "${GREEN}✅ PASSED (HTTP $http_code)${NC}"
    echo "   Response: $(echo "$body" | head -c 100)..."
    ((PASSED++))
  else
    echo -e "${RED}❌ FAILED (HTTP $http_code)${NC}"
    echo "   Response: $body"
    ((FAILED++))
  fi
  echo ""
}

# ============================================
# 1. App & API Tests
# ============================================

echo -e "${BLUE}━━ PHASE 1: App & API Tests ━━${NC}\n"

test_endpoint \
  "App Accessibility" \
  "$MENU_MATCHER" \
  "GET"

test_endpoint \
  "Parse API (CSV)" \
  "$MENU_MATCHER/api/menu/parse" \
  "POST" \
  '{"text":"Falafel,Appetizers\nShawarma,Sandwiches\nGreek Salad,Salads"}'

test_endpoint \
  "Match API" \
  "$MENU_MATCHER/api/menu/match" \
  "POST" \
  '{"items":[{"name":"Falafel","category":"Appetizers"},{"name":"Shawarma","category":"Sandwiches"}]}'

test_endpoint \
  "Generate API" \
  "$MENU_MATCHER/api/menu/generate" \
  "POST" \
  '{"items":[{"name":"Pizza","category":"Mains"},{"name":"Salad","category":"Salads"}]}'

# ============================================
# 2. n8n Webhook Tests
# ============================================

echo -e "${BLUE}━━ PHASE 2: n8n Webhook Tests ━━${NC}\n"

test_endpoint \
  "Claude Smart Matching Webhook" \
  "$N8N_BASE/webhook/menu-matcher-match-item" \
  "POST" \
  '{
    "item_name": "Falafel Wrap",
    "category": "Appetizers",
    "candidates": ["Falafel", "Hummus", "Baba Ganoush"]
  }'

test_endpoint \
  "Smart Suggestions Webhook" \
  "$N8N_BASE/webhook/menu-matcher-smart-suggestions" \
  "POST" \
  '{
    "item_name": "Falafel",
    "images": ["img1.jpg", "img2.jpg", "img3.jpg"]
  }'

test_endpoint \
  "Library Sync Webhook" \
  "$N8N_BASE/webhook/menu-matcher-library-sync" \
  "POST" \
  '{
    "items": [
      {"id": "1", "name": "Falafel", "category": "Appetizers"}
    ],
    "timestamp": "2026-09-01T18:00:00Z"
  }'

test_endpoint \
  "Image Generation Webhook" \
  "$N8N_BASE/webhook/menu-matcher-gen-image" \
  "POST" \
  '{
    "item_name": "Grilled Chicken",
    "category": "Mains",
    "style": "professional-food-photo"
  }'

# ============================================
# Results
# ============================================

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

TOTAL=$((PASSED + FAILED))
PASS_RATE=$((PASSED * 100 / TOTAL))

echo -e "Total Tests:    $TOTAL"
echo -e "${GREEN}Passed:         $PASSED ✅${NC}"
echo -e "${RED}Failed:         $FAILED ❌${NC}"
echo -e "Pass Rate:      ${PASS_RATE}%"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}🎉 ALL TESTS PASSED! Automation is ready! 🎉${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Open: $MENU_MATCHER"
  echo "2. Go to: ⚙️ Admin tab"
  echo "3. Verify webhook URLs are populated"
  echo "4. Click: 💾 Save Settings"
  echo "5. Test: Upload menu → Match → Generate → Export"
  echo ""
else
  echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}⚠️ Some tests failed. Check details above.${NC}"
  echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Common fixes:"
  echo "1. Check n8n is running: $N8N_BASE"
  echo "2. Verify API keys are configured"
  echo "3. Check webhook URLs are correct"
  echo "4. Review n8n workflow logs for errors"
  echo ""
fi

echo "Full documentation: AUTOMATION_SETUP_COMPLETE.md"
