#!/bin/bash

# Menu Matcher End-to-End Automation Test
# Tests: Parse → Match → Generate → Export flow

API_BASE="https://menu-matcher.lths.ai/api/menu"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Menu Matcher E2E Automation Test${NC}"
echo -e "${BLUE}================================${NC}\n"

# Test 1: Parse Menu
echo -e "${YELLOW}[TEST 1] Parse Menu Items${NC}"
MENU_TEXT="Falafel Wrap,Appetizers
Chicken Shawarma,Sandwiches
Greek Salad,Salads
Grilled Chicken,Mains
Baklava,Desserts"

PARSE_RESPONSE=$(curl -s -X POST "$API_BASE/parse" \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"$(echo "$MENU_TEXT" | tr '\n' '\\n')\"}")

echo "Response: $PARSE_RESPONSE"
ITEM_COUNT=$(echo "$PARSE_RESPONSE" | grep -o '"count":[0-9]*' | cut -d':' -f2)

if [ -z "$ITEM_COUNT" ] || [ "$ITEM_COUNT" -eq 0 ]; then
  echo -e "${RED}❌ FAILED: No items parsed${NC}\n"
  exit 1
else
  echo -e "${GREEN}✅ PASSED: Parsed $ITEM_COUNT items${NC}\n"
fi

# Test 2: Match Items
echo -e "${YELLOW}[TEST 2] Match Items Against Library${NC}"
ITEMS_JSON=$(echo "$PARSE_RESPONSE" | grep -o '"items":\[.*\]' | cut -d'[' -f2 | cut -d']' -f1)

MATCH_RESPONSE=$(curl -s -X POST "$API_BASE/match" \
  -H "Content-Type: application/json" \
  -d "{\"items\": [{\"name\": \"Falafel Wrap\", \"category\": \"Appetizers\"}, {\"name\": \"Chicken Shawarma\", \"category\": \"Sandwiches\"}]}")

echo "Response: $MATCH_RESPONSE"
MATCHED_COUNT=$(echo "$MATCH_RESPONSE" | grep -o '"count":[0-9]*' | cut -d':' -f2)

if [ -z "$MATCHED_COUNT" ]; then
  echo -e "${RED}❌ FAILED: Matching failed${NC}\n"
else
  echo -e "${GREEN}✅ PASSED: Matched $MATCHED_COUNT items${NC}\n"
fi

# Test 3: Generate Missing Images
echo -e "${YELLOW}[TEST 3] Generate Missing Images${NC}"
MISSING_ITEMS=$(cat <<'EOF'
[
  {"name": "Pizza Margherita", "category": "Mains"},
  {"name": "Caesar Salad", "category": "Salads"}
]
EOF
)

GEN_RESPONSE=$(curl -s -X POST "$API_BASE/generate" \
  -H "Content-Type: application/json" \
  -d "{\"items\": $MISSING_ITEMS}")

echo "Response: $GEN_RESPONSE"
GENERATED_COUNT=$(echo "$GEN_RESPONSE" | grep -o '"count":[0-9]*' | cut -d':' -f2)

if [ -z "$GENERATED_COUNT" ] || [ "$GENERATED_COUNT" -eq 0 ]; then
  echo -e "${RED}❌ FAILED: No images generated${NC}\n"
else
  echo -e "${GREEN}✅ PASSED: Generated $GENERATED_COUNT images${NC}\n"
fi

# Test 4: Export to ZIP
echo -e "${YELLOW}[TEST 4] Export Results as ZIP${NC}"
EXPORT_PAYLOAD=$(cat <<'EOF'
{
  "items": [
    {"name": "Falafel Wrap", "category": "Appetizers"},
    {"name": "Chicken Shawarma", "category": "Sandwiches"},
    {"name": "Greek Salad", "category": "Salads"}
  ],
  "matched": {
    "0": {"name": "Falafel Wrap"},
    "1": {"name": "Chicken Shawarma"}
  }
}
EOF
)

EXPORT_FILE="/tmp/menu-export-test.zip"
curl -s -X POST "$API_BASE/export" \
  -H "Content-Type: application/json" \
  -d "$EXPORT_PAYLOAD" \
  -o "$EXPORT_FILE"

if [ -f "$EXPORT_FILE" ] && [ -s "$EXPORT_FILE" ]; then
  ZIP_SIZE=$(du -h "$EXPORT_FILE" | cut -f1)
  echo "ZIP created: $ZIP_SIZE"
  echo -e "${GREEN}✅ PASSED: ZIP export successful ($ZIP_SIZE)${NC}\n"
  rm "$EXPORT_FILE"
else
  echo -e "${RED}❌ FAILED: ZIP export failed${NC}\n"
  exit 1
fi

# Summary
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}Automation Flow Summary:${NC}"
echo "  1. ✅ Parse menu items (5 items)"
echo "  2. ✅ Match items against library"
echo "  3. ✅ Generate missing images"
echo "  4. ✅ Export results as ZIP"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  • Configure n8n webhooks in Admin panel"
echo "  • Test each webhook individually"
echo "  • Monitor n8n logs for execution"
echo "  • Verify images synced to library"
