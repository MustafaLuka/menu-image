# Menu Matcher 2.0 — Production Deployment Checklist

## ✅ Completed

- [x] **App Deployed** to Vibehost (menu-matcher.lths.ai)
- [x] **Backend API** running (parse, match, generate, export)
- [x] **Frontend** modernized with Talabat branding
- [x] **E2E Tests** all passing
- [x] **Codebase Committed** (git)
- [x] **Credentials** configured
  - Anthropic API: `sk-IQvLbdYLZFl1Ph_FN_n9hg`
  - n8n Project Token: JWT active
  - n8n Base: `https://mono-mcp-server.dhhmena.com`

---

## 🔧 Setup n8n Automation (Next Steps)

### Phase 1: Import Workflows

**1. Log in to n8n**
```
https://mono-mcp-server.dhhmena.com
Project: 3SGU8EYe7UAl3gUn
```

**2. Create Workflows**
```
Settings → Import from JSON
└─ Copy from: n8n-workflows-complete.json
└─ Import each of 4 workflows:
   ✓ Claude Smart Matching
   ✓ Smart Suggestions Ranker
   ✓ Library Sync
   ✓ Image Generation
```

### Phase 2: Configure Credentials

**3. Add Anthropic Credential**
```
n8n Settings → Credentials → Create new
├─ Type: HTTP Bearer Auth
├─ Name: Anthropic API
├─ Token: sk-IQvLbdYLZFl1Ph_FN_n9hg
└─ Save & test
```

**4. Set Environment Variables**
```
n8n Settings → Environment Variables
├─ ANTHROPIC_API_KEY=sk-IQvLbdYLZFl1Ph_FN_n9hg
├─ GEMINI_API_KEY=(if using image generation)
└─ (Optional) LIBRARY_API_TOKEN=...
```

### Phase 3: Activate & Test Workflows

**5. Activate Each Workflow**
```
For each workflow:
├─ Click workflow
├─ Settings → Activate
├─ Save
└─ Verify status shows "Active" (green)
```

**6. Get Webhook URLs**
```
For each workflow:
├─ Click workflow
├─ Copy the Production Webhook URL
├─ Format: https://your-n8n.../webhook/menu-matcher-XXX
└─ Save for next step
```

### Phase 4: Connect to Menu Matcher

**7. Configure Admin Panel**
```
URL: https://menu-matcher.lths.ai
Tab: ⚙️ Admin

Paste webhook URLs:
┌─────────────────────────────────────────┐
│ 🧠 Claude Smart Matching                │
│ https://.../webhook/menu-matcher-match-item
│                                         │
│ 🤖 Smart Suggestions                    │
│ https://.../webhook/menu-matcher-smart-suggestions
│                                         │
│ 🔄 Library Sync                         │
│ https://.../webhook/menu-matcher-library-sync
│                                         │
│ 📤 Image Generation                     │
│ https://.../webhook/menu-matcher-gen-image
└─────────────────────────────────────────┘

Click: Save Settings ✓
```

### Phase 5: End-to-End Testing

**8. Test Automation Flow**

```
Step 1: Upload Menu
├─ URL: https://menu-matcher.lths.ai
├─ Tab: 📤 Upload
├─ Paste: Falafel Wrap,Appetizers
│         Chicken Shawarma,Sandwiches
│         Greek Salad,Salads
└─ Click: Next: Matching ←

Step 2: Match Items
├─ Tab: 🍽️ Match
├─ Stats: Shows total items, matched, missing
├─ Click: 🔍 Match Now
├─ Watch: n8n webhook is called
└─ Expected: Items matched via Claude

Step 3: Generate Missing
├─ Click: 🎨 Generate Missing
├─ Watch: n8n creates images
└─ Expected: SVG placeholders appear

Step 4: Export Results
├─ Tab: 📦 Export
├─ Click: ⬇️ Download ZIP
├─ Expected: ZIP with menu.xlsx + manifest
└─ Verify: File size > 10KB

Step 5: Monitor Logs
├─ n8n Dashboard → Workflows
├─ Click each workflow → Executions
├─ Expected: All show green (success)
└─ Check: No errors in logs
```

---

## 🎯 Success Criteria

After completing all steps, verify:

- [x] **Menu Matcher app** loads at menu-matcher.lths.ai
- [x] **Parse API** extracts menu items correctly
- [x] **Match API** fuzzy-matches items
- [x] **Generate API** creates images
- [x] **Export API** creates ZIP files
- [ ] **n8n workflows** are active (4/4)
- [ ] **Claude matching** triggers successfully
- [ ] **Images generate** when requested
- [ ] **Library sync** updates cloud storage
- [ ] **Full flow** works end-to-end

---

## 📊 Monitoring

### Health Checks (Daily)

```bash
# Check app is up
curl -I https://menu-matcher.lths.ai

# Check API endpoints
curl https://menu-matcher.lths.ai/api/menu/parse \
  -X POST -H "Content-Type: application/json" \
  -d '{"text":"Test"}'

# Check n8n workflows
curl -H "Authorization: Bearer TOKEN" \
  https://mono-mcp-server.dhhmena.com/api/v1/workflows
```

### Logs to Monitor

1. **n8n Dashboard**
   - Workflow executions
   - Error rates
   - Webhook hit counts

2. **Menu Matcher**
   - API response times
   - Export ZIP sizes
   - User uploads

3. **Anthropic API**
   - Token usage
   - Rate limits
   - Error rates

---

## 🚨 Troubleshooting

### Issue: Webhook returns 404
**Solution:**
- Verify workflow is Active (green status)
- Check webhook path matches exactly
- Test webhook URL directly with curl

### Issue: Claude matching fails
**Solution:**
- Verify Anthropic API key is correct
- Check API quota not exceeded
- Look at n8n execution logs

### Issue: Images don't generate
**Solution:**
- Verify Gemini API key (if using)
- Check image generation API quota
- Monitor n8n logs for errors

### Issue: Library sync fails
**Solution:**
- Verify library API endpoint is correct
- Check auth token is valid
- Ensure payload format matches API spec

---

## 📈 Scaling

When ready to scale:

1. **Increase n8n Concurrency**
   - Settings → Execution → Max workers

2. **Add Image Caching**
   - Cache generated images in Redis

3. **Database Indexing**
   - Index library by item_name, category

4. **Rate Limiting**
   - Add CloudFlare rate limiting
   - Implement webhook throttling

---

## 🔐 Security

Before production release:

- [ ] Rotate API keys
- [ ] Enable HTTPS (already done via Vibehost)
- [ ] Add API rate limiting
- [ ] Enable audit logging
- [ ] Set up alerts for errors
- [ ] Add input validation
- [ ] Enable CORS correctly
- [ ] Monitor for abuse

---

## 📋 Deployment Summary

| Component | Status | URL |
|-----------|--------|-----|
| **App** | 🟢 Live | https://menu-matcher.lths.ai |
| **API** | 🟢 Live | /api/menu/* |
| **n8n** | 🟡 Ready | https://mono-mcp-server.dhhmena.com |
| **Database** | 🟢 Ready | Vibehost MySQL |
| **Anthropic** | 🟢 Ready | API configured |
| **Automation** | 🟡 Ready | 4 workflows pending activation |

---

## ✨ Final Status

```
MENU MATCHER 2.0
└─ ✅ App Deployed
└─ ✅ API Working
└─ ✅ Tests Passing
└─ ✅ Credentials Configured
└─ 🟡 n8n Automation (Pending Activation)
└─ 🟡 Production Go-Live (After n8n setup)
```

---

**Last Updated:** 2026-01-15
**Version:** 2.0.0
**Status:** Production Ready (Awaiting n8n Activation)

For questions, refer to:
- `N8N_SETUP_INSTRUCTIONS.md` — Detailed n8n guide
- `n8n-workflows-complete.json` — Workflow definitions
- `DELIVERABLES.md` — Feature list
