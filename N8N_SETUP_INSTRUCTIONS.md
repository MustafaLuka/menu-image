# n8n Automation Setup — Menu Matcher 2.0

Complete guide to importing and configuring n8n workflows for Menu Matcher automation.

---

## 📋 Workflows to Create

1. **Claude Smart Matching** — Match ambiguous items using Claude Opus
2. **Smart Suggestions Ranker** — Re-rank suggestions with AI scoring
3. **Library Sync** — Batch sync approved images to cloud
4. **Image Generation** — Generate images for missing items

---

## 🚀 Quick Setup (5 minutes)

### 1. Access Your n8n Instance
```
URL: https://mono-mcp-server.dhhmena.com/n8n/projects/3SGU8EYe7UAl3gUn/workflows
```

### 2. Import Workflows
Each workflow below can be imported as JSON:
- Copy the JSON from `n8n-workflows-complete.json`
- In n8n: **+ Create** → **Import from JSON**
- Paste each workflow and click Import

### 3. Configure Credentials

#### a) Anthropic API (for Claude)
```
In n8n:
1. Settings → Credentials → Create new
2. Type: HTTP Bearer Auth
3. Name: Anthropic API
4. Credentials:
   - Header: Authorization
   - Value: Bearer sk-ant-YOUR-KEY-HERE
5. Save & test
```

#### b) Gemini API (for Image Generation)
```
In n8n:
1. Settings → Credentials → Create new
2. Type: HTTP Bearer Auth
3. Name: Gemini API
4. Set environment variable: GEMINI_API_KEY=YOUR-KEY
5. Or configure in workflow: 
   - Node "call_gemini" → Authentication
   - Use API key from secrets
```

#### c) Library API (if syncing to backend)
```
Update in workflow "Library Sync":
1. Node "sync_to_db" → URL field
2. Replace: https://your-library-api.com/api/sync
3. With your actual library endpoint
```

---

## 📝 Workflow Details

### **1. Claude Smart Matching**

**Trigger:** Webhook `menu-matcher-match-item`

**Input:**
```json
{
  "item_id": "item-123",
  "item_name": "Chicken Shawarma",
  "category": "Sandwiches",
  "candidates": [
    {"name": "Chicken Shawarma", "lang": "en"},
    {"name": "شاورما دجاج", "lang": "ar"},
    {"name": "Beef Kofta", "lang": "en"}
  ],
  "callback_url": "https://menu-matcher.lths.ai/api/match-result"
}
```

**Output:**
```json
{
  "status": "matched|needs_review",
  "item_id": "item-123",
  "selected_image": {...},
  "confidence": 0.95,
  "matched_by": "claude_opus"
}
```

**Setup Steps:**
1. Create new workflow
2. Add webhook node:
   - Method: POST
   - Path: `menu-matcher-match-item`
3. Add "parse_input" Set node (extract from webhook)
4. Add "call_claude" HTTP Request:
   - URL: `https://api.anthropic.com/v1/messages`
   - Headers: `anthropic-version: 2023-06-01`
   - Body: Send to Claude with menu item + candidates
5. Add "parse_response" Code node (parse JSON response)
6. Add "check_confidence" IF node:
   - Condition: confidence >= 0.7
7. If high confidence: send "matched" response
8. If low confidence: send "needs_review" response
9. **Activate & copy webhook URL**

---

### **2. Smart Suggestions Ranker**

**Trigger:** Webhook `menu-matcher-smart-suggestions`

**Input:**
```json
{
  "item_id": "item-123",
  "item_name": "Falafel Wrap",
  "category": "Appetizers",
  "description": "Crispy falafel with tahini sauce",
  "suggestions": [
    {"name": "Falafel Wrap", "language": "en"},
    {"name": "Falafel Plate", "language": "en"},
    {"name": "Hummus", "language": "en"}
  ],
  "callback_url": "https://menu-matcher.lths.ai/api/suggestions-ranked"
}
```

**Output:**
```json
{
  "status": "suggestions_ranked",
  "item_id": "item-123",
  "ranked_suggestions": [
    {"index": 0, "name": "Falafel Wrap", "score": 95, "reason": "Perfect match"},
    {"index": 1, "name": "Falafel Plate", "score": 80, "reason": "Same item, different serve"}
  ],
  "top_recommendation_index": 0,
  "verification_method": "claude_ranking"
}
```

**Setup Steps:**
1. Similar to Claude Smart Matching
2. Use model `claude-opus-5`
3. Prompt: Score each suggestion 0-100 for fit
4. Parse response with ranking scores
5. Return sorted results

---

### **3. Library Sync**

**Trigger:** Webhook `menu-matcher-library-sync`

**Input:**
```json
{
  "sync_id": "sync-2026-001",
  "operation": "add",
  "images": [
    {
      "item_name": "Chicken Shawarma",
      "category": "Sandwiches",
      "file_url": "s3://bucket/image.jpg",
      "language": "ar",
      "approved": true
    }
  ],
  "callback_url": "https://menu-matcher.lths.ai/api/sync-result"
}
```

**Output:**
```json
{
  "status": "synced",
  "sync_id": "sync-2026-001",
  "images_synced": 5,
  "timestamp": "2026-01-15T10:30:00Z"
}
```

**Setup Steps:**
1. Webhook node: `menu-matcher-library-sync`
2. Parse input (sync_id, images, callback_url)
3. HTTP Request to your library API:
   - Endpoint: `POST /api/sync`
   - Body: send images batch
4. Check response status (200-299)
5. Return success or error

---

### **4. Image Generation**

**Trigger:** Webhook `menu-matcher-gen-image`

**Input:**
```json
{
  "items": [
    {"name": "Pizza Margherita", "category": "Mains"}
  ],
  "model": "gemini-2.5-flash-image",
  "callback_url": "https://menu-matcher.lths.ai/api/generate-result"
}
```

**Output:**
```json
{
  "status": "generated",
  "item": {"name": "Pizza Margherita", "category": "Mains"},
  "image_url": "data:image/jpeg;base64,..."
}
```

**Setup Steps:**
1. Webhook node: `menu-matcher-gen-image`
2. Parse input (items, model, callback)
3. Loop over items
4. For each item, call Gemini:
   - URL: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}`
   - Prompt: "Generate professional food photo for {item_name}"
5. Return generated image URL
6. Send results back

---

## 🔗 Connect Webhooks to Menu Matcher

Once workflows are created, copy their webhook URLs and add to Menu Matcher Admin:

1. Open: **menu-matcher.lths.ai**
2. Tab: **⚙️ Admin**
3. Paste webhook URLs:

```
🧠 Claude Smart Matching
https://your-n8n-instance/webhook/menu-matcher-match-item

🤖 Smart Suggestions Ranker  
https://your-n8n-instance/webhook/menu-matcher-smart-suggestions

🔄 Library Sync
https://your-n8n-instance/webhook/menu-matcher-library-sync

📤 Image Generation
https://your-n8n-instance/webhook/menu-matcher-gen-image
```

4. **Save Settings**

---

## ✅ Testing

### Test Claude Smart Matching
```
In Menu Matcher:
1. Upload test menu
2. Click "Match Now"
3. Check n8n workflow logs
4. Verify Claude response in Menu Matcher
```

### Test Image Generation
```
1. After matching, click "Generate Missing"
2. Check n8n workflow runs
3. Verify images appear in Menu Matcher
```

### Test Library Sync
```
1. In Admin → Library Sync section
2. Paste webhook URL
3. Click "Sync Now"
4. Check n8n logs for execution
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| **Webhook returns 404** | Ensure workflow is active & webhook path matches |
| **Claude API error** | Check Anthropic API key has quota |
| **Gemini API fails** | Verify API key & model name |
| **Library sync fails** | Check endpoint URL & auth token |
| **Webhook times out** | Ensure callback URL is reachable |

Check n8n logs:
1. Click workflow
2. **Execution** tab
3. View logs for each failed run

---

## 📞 Environment Variables in n8n

Set these in n8n Settings → Environment:

```
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AIz...
LIBRARY_API_TOKEN=...
```

Or use Credentials system (recommended).

---

## ✨ Optional: Advanced Features

### Add Retry Logic
In each HTTP Request node:
- Settings → Retry
- Max retries: 3
- Delay: 1s between retries

### Add Error Notifications
After each workflow:
- Add Slack/Email node
- Send notification on error

### Add Rate Limiting
If using external APIs:
- Add wait node: 1s delay between items
- Prevent API throttling

---

## Summary

After setup, your Menu Matcher will:
✅ Auto-match ambiguous items using Claude  
✅ Rank suggestions intelligently  
✅ Generate images for missing items  
✅ Sync approved images to library  

**Estimated setup time:** 15 minutes

**Need help?** Check n8n logs or reach out!
