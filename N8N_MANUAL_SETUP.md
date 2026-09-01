# n8n Workflows Manual Setup Guide

## Quick Overview

You need to create 4 workflows in n8n. Each workflow has:
1. **Webhook Trigger** (listens for POST requests)
2. **Action Node** (calls Claude API, generates images, syncs library, etc.)

---

## Workflow 1: Claude Smart Matching ⭐ START HERE

**What it does:** When Menu Matcher sends an ambiguous item → Claude picks the best match → returns result

### Setup Steps:

#### 1.1 Create Webhook
```
n8n Dashboard
→ New Workflow
→ Add Node (+)
→ Search: "Webhook"
→ Configure:
   - HTTP Method: POST
   - Path: menu-matcher-match-item
   - Click Save
```

#### 1.2 Add Claude HTTP Request
```
→ Add Node (+)
→ Search: "HTTP Request"
→ Configure these tabs:
```

**[1] URL Tab:**
```
URL: https://api.anthropic.com/v1/messages
Method: POST
```

**[2] Headers Tab:**
```
Key: anthropic-version
Value: 2023-06-01

Key: x-api-key
Value: sk-IQvLbdYLZFl1Ph_FN_n9hg
```

**[3] Body Tab:**
```
Choose: JSON
Body:
{
  "model": "claude-opus-5",
  "max_tokens": 200,
  "messages": [
    {
      "role": "user",
      "content": "Menu item: {{$json.item_name}}\nCategory: {{$json.category}}\nCandidates: {{$json.candidates}}\n\nRespond JSON: {\"selected_index\": <index>, \"confidence\": <0-1>}"
    }
  ]
}
```

#### 1.3 Connect the Nodes
```
Webhook Node → Drag the blue dot → HTTP Request Node
```

#### 1.4 Activate & Deploy
```
Top Right: "Save" → "Activate"
Watch for green status
```

#### 1.5 Copy Webhook URL
```
Click "Details" (top right)
Copy the "Webhook URL" 
Example: https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item
```

#### 1.6 Test It
```bash
curl -X POST "https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item" \
  -H "Content-Type: application/json" \
  -d '{
    "item_name": "Falafel Wrap",
    "category": "Appetizers",
    "candidates": ["Falafel", "Hummus", "Tabbouleh"]
  }'
```

Expected response:
```json
{
  "content": [{"type": "text", "text": "{\"selected_index\": 0, \"confidence\": 0.95}"}]
}
```

---

## Workflow 2: Smart Suggestions Ranker

**What it does:** Ranks image suggestions by relevance (0-100 score)

### Quick Setup:

```
New Workflow → Name: "Smart Suggestions Ranker"

Add Webhook:
  Path: menu-matcher-smart-suggestions

Add HTTP Request (same as above, but different path):
  URL: https://api.anthropic.com/v1/messages
  Headers: (same API key)
  Body:
  {
    "model": "claude-opus-5",
    "max_tokens": 300,
    "messages": [{
      "role": "user",
      "content": "Item: {{$json.item_name}}\nImages: {{$json.images}}\n\nRank by relevance 0-100. Respond JSON: {\"scores\": [{\"index\": 0, \"score\": 85}, ...]}"
    }]
  }

Connect Webhook → HTTP Request
Save → Activate

Copy webhook URL for step 3 (Admin Panel)
```

---

## Workflow 3: Library Sync

**What it does:** Syncs approved images to cloud library

### Quick Setup:

```
New Workflow → Name: "Library Sync"

Add Webhook:
  Path: menu-matcher-library-sync

Add HTTP Request:
  URL: https://your-library-api.com/api/sync
  (Or leave as placeholder if you don't have a library API yet)
  Method: POST
  Headers:
    Content-Type: application/json
  Body:
  {
    "items": {{$json.items}},
    "timestamp": {{$json.timestamp}}
  }

Connect Webhook → HTTP Request
Save → Activate

Copy webhook URL
```

---

## Workflow 4: Image Generation

**What it does:** Generates placeholder images for missing items

### Quick Setup:

```
New Workflow → Name: "Image Generation"

Add Webhook:
  Path: menu-matcher-gen-image

Add HTTP Request:
  URL: https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent
  (Or use your image generation service)
  Method: POST
  Headers:
    Content-Type: application/json
    x-api-key: {YOUR_GEMINI_KEY}
  Body:
  {
    "contents": [{
      "parts": [{
        "text": "Create professional food image for {{$json.item_name}} in category {{$json.category}}"
      }]
    }]
  }

Connect Webhook → HTTP Request
Save → Activate

Copy webhook URL
```

---

## Step 3: Connect to Menu Matcher Admin Panel

Once all 4 workflows are created and activated:

1. **Open:** https://menu-matcher.lths.ai
2. **Go to:** ⚙️ Admin tab
3. **Paste each webhook URL:**
   ```
   🧠 Claude Smart Matching:
   https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-match-item
   
   🤖 Smart Suggestions:
   https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-smart-suggestions
   
   🔄 Library Sync:
   https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-library-sync
   
   📤 Image Generation:
   https://mono-mcp-server.dhhmena.com/webhook/menu-matcher-gen-image
   ```
4. **Click:** Save Settings ✅

---

## Step 4: Test End-to-End

### Test 1: Upload a Menu
```
URL: https://menu-matcher.lths.ai
Tab: 📤 Upload
Paste:
  Falafel Wrap,Appetizers
  Chicken Shawarma,Sandwiches
  Greek Salad,Salads

Click: Next: Matching →
```

### Test 2: Trigger Claude Matching
```
Tab: 🍽️ Match
Click: 🔍 Match Now

Watch n8n dashboard:
→ Workflows → Claude Smart Matching → Executions
→ Should show green checkmark

If red error: Click execution → View logs
```

### Test 3: Generate Missing Images
```
Click: 🎨 Generate Missing

Watch n8n:
→ Image Generation workflow → Executions
→ Should show green
```

### Test 4: Export Results
```
Tab: 📦 Export
Click: ⬇️ Download ZIP

Verify:
✓ File size > 10KB
✓ Contains menu.xlsx
✓ Contains manifest.json
```

---

## Troubleshooting

### Webhook returns 404
**Fix:**
1. Go to workflow → Click "Details"
2. Copy the exact webhook URL
3. Paste into Menu Matcher Admin exactly
4. Make sure workflow status is "Active" (green)

### HTTP Request returns 401/403
**Fix:**
1. Check API key is correct: `sk-IQvLbdYLZFl1Ph_FN_n9hg`
2. Check header names match exactly
3. Go to n8n → Workflows → Executions → Click failed one → View logs

### Webhook doesn't trigger
**Fix:**
1. Test webhook directly with curl command (see Workflow 1.6 above)
2. If curl works but app doesn't, verify URL in Admin panel is exact match
3. Check Menu Matcher API is calling the webhook (open browser DevTools → Network)

---

## API Reference: What Menu Matcher Sends to Webhooks

### Claude Smart Matching Webhook
```json
{
  "item_name": "Falafel Wrap",
  "category": "Appetizers",
  "candidates": ["Falafel", "Hummus", "Tabbouleh"],
  "callback_url": "https://menu-matcher.lths.ai/api/callback"
}
```

### Smart Suggestions Webhook
```json
{
  "item_name": "Falafel",
  "images": ["img1.jpg", "img2.jpg", "img3.jpg"],
  "callback_url": "https://menu-matcher.lths.ai/api/callback"
}
```

### Library Sync Webhook
```json
{
  "items": [
    {"id": "falafel-1", "name": "Falafel", "image": "...base64...", "category": "Appetizers"}
  ],
  "timestamp": "2026-01-15T10:30:00Z"
}
```

### Image Generation Webhook
```json
{
  "item_name": "Falafel Wrap",
  "category": "Appetizers",
  "style": "professional-food-photo"
}
```

---

## Success Checklist

- [ ] Workflow 1: Claude Smart Matching created & activated
- [ ] Workflow 2: Smart Suggestions created & activated
- [ ] Workflow 3: Library Sync created & activated
- [ ] Workflow 4: Image Generation created & activated
- [ ] All 4 webhook URLs copied to Menu Matcher Admin panel
- [ ] Menu Matcher Admin panel saved
- [ ] Test: Upload menu successfully
- [ ] Test: Click "Match Now" triggers Claude webhook
- [ ] Test: n8n shows green executions
- [ ] Test: Export ZIP downloads successfully

---

## Next: What to Do If Stuck

1. **Check n8n Execution Logs:**
   - Click workflow → Executions tab
   - Click the red failed execution
   - Read the error message

2. **Test Webhook Manually:**
   ```bash
   curl -X POST "your-webhook-url" \
     -H "Content-Type: application/json" \
     -d '{"test": "data"}'
   ```

3. **Check Menu Matcher Console:**
   - Open Menu Matcher in browser
   - Press F12 → Console tab
   - Look for error messages

4. **Verify Credentials:**
   - Anthropic key: `sk-IQvLbdYLZFl1Ph_FN_n9hg` ✓
   - n8n URL: `https://mono-mcp-server.dhhmena.com` ✓

---

**Last Updated:** 2026-01-15
**Status:** Ready for manual setup
