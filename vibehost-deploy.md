# Menu Matcher 2.0 — Talabat Vibehost Deployment

## Quick Deploy to Vibehost

### 1. Prepare Files

```bash
cd C:\ME\menu-matcher
# Ensure these files exist:
# - index.html (frontend)
# - server.js (backend)
# - package.json (dependencies)
# - .env (credentials)
```

### 2. Deploy via Vibehost CLI/Dashboard

**Option A: Via Vibehost Dashboard**
1. Login to vibehost.talabat.com
2. Create new App → Node.js
3. Upload files
4. Set environment variables (ANTHROPIC_API_KEY, etc.)
5. Deploy

**Option B: Via CLI**
```bash
vibehost login
vibehost deploy --app menu-matcher --region production
```

### 3. Configure Environment on Vibehost

In Vibehost Dashboard → App Settings → Secrets:
```
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AI...
NODE_ENV=production
API_URL=https://your-vibehost-app-url
```

### 4. Get Webhook URLs from n8n

Each n8n workflow generates a webhook. Paste these in Menu Matcher Admin:
- Claude Smart Matching: `https://your-n8n.../webhook/menu-matcher-match-item`
- Smart Suggestions: `https://your-n8n.../webhook/menu-matcher-smart-suggestions`
- Library Sync: `https://your-n8n.../webhook/menu-matcher-library-sync`
- Email: `https://your-n8n.../webhook/menu-matcher-email-deliver`

### 5. Connect to Talabat Internal APIs

If using Talabat AI Gateway:
```
TALABAT_AI_GATEWAY=https://ai-gateway.talabat.internal
TALABAT_AUTH_TOKEN=<internal-token>
```

---

## Vibehost App Database

### Use Vibehost Built-in Database

```javascript
// In server.js, replace in-memory library:
const db = require('vibehost').database;

// Get library from DB
async function getLibrary() {
  return await db.query('SELECT * FROM image_library');
}

// Update library after sync
async function syncLibrary(images) {
  await db.insertMany('image_library', images);
}
```

### Environment Variables on Vibehost

Vibehost automatically provides:
- `DATABASE_URL` (PostgreSQL)
- `REDIS_URL` (Cache)
- `APP_URL` (Your app's public URL)

---

## Testing on Vibehost

### Health Check
```bash
curl https://your-menu-matcher-vibehost.app/api/health
# Should return: {"status": "ok"}
```

### Test Upload
Upload test `menu.xlsx` via UI at `https://your-menu-matcher-vibehost.app`

### Logs
```bash
vibehost logs menu-matcher --follow
```

---

## Production Checklist

- [ ] Files uploaded to Vibehost
- [ ] Environment variables set
- [ ] Database initialized
- [ ] n8n workflows imported & activated
- [ ] Webhook URLs configured in Menu Matcher Admin
- [ ] Test upload → match → export flow
- [ ] Verify emails send via n8n
- [ ] Monitor logs for errors

---

**Deploy Status**: Ready for Vibehost ✓
