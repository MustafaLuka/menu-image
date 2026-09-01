# n8n Webhook Configuration for Menu Matcher

## Status: Ready to Deploy

Once the 4 workflows are created in n8n, they will generate these webhook URLs:

### Workflow Webhook URLs

```json
{
  "claudeSmartMatching": "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item",
  "smartSuggestionsRanker": "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-smart-suggestions",
  "librarySync": "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-library-sync",
  "imageGeneration": "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-gen-image"
}
```

---

## Setup Steps

### Step 1: Import Workflows to n8n

1. **Open n8n:** https://mono-mcp-server.dhhmena.com
2. **Go to:** Settings → Workflows → Import
3. **Copy the JSON from:** `n8n-workflows-ready-import.json`
4. **Paste** into the import dialog
5. **Click Import** - This should import all 4 workflows
6. **Verify:** All 4 workflows appear in the list

### Step 2: Activate All Workflows

For each of the 4 workflows:
1. Click the workflow name
2. Click **Active** toggle (top right) → Turn it ON (green)
3. Click **Save**

Verify all show green "Active" status.

### Step 3: Copy Webhook URLs

For each workflow:
1. Click the workflow
2. Click **Details** (top right corner)
3. Copy the **Webhook URL**
4. Paste into a text file

Expected URLs (use these exactly):
```
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-smart-suggestions
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-library-sync
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-gen-image
```

### Step 4: Configure Menu Matcher Admin Panel

1. **Open:** https://menu-matcher.lths.ai
2. **Go to:** ⚙️ Admin tab
3. **Paste webhook URLs:**

```
🧠 Claude Smart Matching Webhook:
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item

🤖 Smart Suggestions Ranker Webhook:
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-smart-suggestions

🔄 Library Sync Webhook:
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-library-sync

📤 Image Generation Webhook:
https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-gen-image
```

4. **Click:** Save Settings ✅

### Step 5: Test Each Webhook

Test the first one to verify connectivity:

```bash
curl -X POST "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item" \
  -H "Content-Type: application/json" \
  -d '{
    "item_name": "Falafel Wrap",
    "category": "Appetizers",
    "candidates": ["Falafel", "Hummus", "Tabbouleh"]
  }'
```

Expected response (from Claude):
```json
{
  "content": [{
    "type": "text",
    "text": "{\"selected_index\": 0, \"confidence\": 0.95}"
  }]
}
```

---

## Automation Payload Reference

### What Menu Matcher sends to each webhook:

#### Claude Smart Matching
```json
POST /webhook/menu-matcher-match-item
{
  "item_name": "Falafel Wrap",
  "category": "Appetizers",
  "candidates": ["Falafel", "Hummus", "Tabbouleh"],
  "callback_url": "https://menu-matcher.lths.ai/api/callback"
}
```

#### Smart Suggestions Ranker
```json
POST /webhook/menu-matcher-smart-suggestions
{
  "item_name": "Falafel",
  "images": [
    "https://example.com/falafel1.jpg",
    "https://example.com/falafel2.jpg"
  ],
  "callback_url": "https://menu-matcher.lths.ai/api/callback"
}
```

#### Library Sync
```json
POST /webhook/menu-matcher-library-sync
{
  "items": [
    {
      "id": "falafel-001",
      "name": "Falafel",
      "category": "Appetizers",
      "image": "data:image/svg+xml;base64,...",
      "confidence": 0.95
    }
  ],
  "timestamp": "2026-01-15T10:30:00Z"
}
```

#### Image Generation
```json
POST /webhook/menu-matcher-gen-image
{
  "item_name": "Grilled Chicken",
  "category": "Mains",
  "style": "professional-food-photo",
  "callback_url": "https://menu-matcher.lths.ai/api/callback"
}
```

---

## Testing the Full End-to-End Flow

Once configured:

1. **Upload Menu** (📤 Upload tab)
   ```
   Falafel Wrap,Appetizers
   Chicken Shawarma,Sandwiches
   Greek Salad,Salads
   ```

2. **Trigger Matching** (🍽️ Match tab)
   - Click "🔍 Match Now"
   - Watch n8n → Workflows → Claude Smart Matching → Executions
   - Should show green checkmark

3. **Generate Images** (🍽️ Match tab)
   - Click "🎨 Generate Missing"
   - Watch n8n → Image Generation → Executions
   - Should complete successfully

4. **Export Results** (📦 Export tab)
   - Click "⬇️ Download ZIP"
   - File should be > 10KB
   - Contains menu.xlsx + manifest.json

5. **Monitor Logs**
   - n8n Dashboard → Each workflow → Executions tab
   - All should show green (success)
   - No error messages

---

## Troubleshooting

### n8n Webhooks Return 404
**Cause:** Workflow not activated or webhook path mismatch
**Fix:**
1. Go to workflow → Check "Active" is ON (green)
2. Go to Details → Verify webhook path matches exactly
3. Save workflow again
4. Test webhook URL with curl

### Claude API Returns 401
**Cause:** API key is wrong or expired
**Fix:**
1. Go to workflow → Edit HTTP Request node
2. Check x-api-key header: `sk-IQvLbdYLZFl1Ph_FN_n9hg`
3. Go to n8n → Settings → Check if Anthropic credential exists
4. Delete and recreate the HTTP node with correct key

### Menu Matcher Can't Reach Webhook
**Cause:** Webhook URL incorrect in Admin panel
**Fix:**
1. Open Menu Matcher → ⚙️ Admin
2. Re-paste webhook URLs from n8n
3. Make sure they start with `https://mono-mcp-server.dhhmena.com/webhook/`
4. Click Save Settings
5. Check browser DevTools → Network → See actual webhook call

### Workflow Never Executes
**Cause:** Webhook not being called from Menu Matcher
**Fix:**
1. Open Menu Matcher in browser
2. Press F12 → Console tab
3. Click "Match Now" or "Generate"
4. Check Network tab → Look for POST requests
5. Verify the webhook URL is being called
6. Check n8n Dashboard → Webhooks tab → See if it's receiving hits

---

## Success Checklist

- [ ] n8n accessible at https://mono-mcp-server.dhhmena.com
- [ ] 4 workflows imported successfully
- [ ] All 4 workflows show "Active" (green)
- [ ] Webhook URLs copied and pasted to Menu Matcher Admin
- [ ] Menu Matcher Admin panel saved
- [ ] Test curl command returns JSON response
- [ ] Upload menu to Menu Matcher
- [ ] Click "Match Now" triggers Claude webhook
- [ ] n8n shows execution in logs (green)
- [ ] Export ZIP downloads successfully
- [ ] Full automation flow works end-to-end

---

## Quick Command to Test All Webhooks

```bash
#!/bin/bash

N8N="https://mono-mcp-server.dhhmena.com/webhook"

echo "Testing all 4 webhooks..."

echo -e "\n[1] Claude Smart Matching"
curl -s -X POST "$N8N/menu-matcher-match-item" \
  -H "Content-Type: application/json" \
  -d '{"item_name":"Falafel","category":"Appetizers","candidates":["Falafel","Hummus"]}'

echo -e "\n[2] Smart Suggestions Ranker"
curl -s -X POST "$N8N/menu-matcher-smart-suggestions" \
  -H "Content-Type: application/json" \
  -d '{"item_name":"Falafel","images":["img1.jpg","img2.jpg"]}'

echo -e "\n[3] Library Sync"
curl -s -X POST "$N8N/menu-matcher-library-sync" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"id":"1","name":"Test"}],"timestamp":"2026-01-15T10:30:00Z"}'

echo -e "\n[4] Image Generation"
curl -s -X POST "$N8N/menu-matcher-gen-image" \
  -H "Content-Type: application/json" \
  -d '{"item_name":"Chicken","category":"Mains","style":"professional"}'

echo -e "\n✅ All webhooks tested"
```

---

**Ready to go!** Once you have access to n8n and import the workflows, you'll have full automation. All webhooks are prepared and the Menu Matcher app is ready to receive them.
