# Menu Matcher 2.0 — Deployment Guide

## Files Structure

```
menu-matcher/
├── index.html          # Talabat-branded UI
├── server.js           # Express API (parse, match, generate, export)
├── package.json        # Dependencies
├── .env.example        # Credentials template
├── n8n-workflows.json  # n8n automation workflows
├── README.md           # Quick start
└── .claude/launch.json # Claude Code dev server config
```

## Local Development

### 1. Install & Start

```bash
cd C:\ME\menu-matcher
npm install
npm start
```

Server runs on `http://localhost:3001`

### 2. Configure Credentials

```bash
cp .env.example .env
# Edit .env with your API keys
```

### 3. Import n8n Workflows

1. Go to your n8n instance
2. **Settings → Import Workflows**
3. Paste contents of `n8n-workflows.json`
4. For each workflow:
   - Click workflow → Copy Production Webhook URL
   - Save URLs

### 4. Connect Webhooks in Menu Matcher

Open `http://localhost:3001` → Admin (⚙️) panel:
- **Claude Smart Matching**: `https://your-n8n.../webhook/menu-matcher-match-item`
- **Smart Suggestions**: `https://your-n8n.../webhook/menu-matcher-smart-suggestions`
- **Library Sync**: `https://your-n8n.../webhook/menu-matcher-library-sync`
- **Email Delivery**: `https://your-n8n.../webhook/menu-matcher-email-deliver`

Click **💾 Save Settings**

## Production Deployment

### Docker

```dockerfile
FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3001
CMD ["npm", "start"]
```

```bash
docker build -t menu-matcher:2.0 .
docker run -p 3001:3001 -e ANTHROPIC_API_KEY=... menu-matcher:2.0
```

### Environment Variables (Production)

```
PORT=3001
API_URL=https://your-menu-matcher-domain.com
NODE_ENV=production

ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AI...

DATABASE_URL=postgresql://...  # Replace in-memory with DB
REDIS_URL=redis://...           # For caching
```

### Database Migration

Replace `library` object in `server.js`:

```javascript
// Before: const library = { ... }

// After: Query from DB
const getLibrary = async () => {
  return await db.query('SELECT * FROM images GROUP BY name');
};
```

### Scale to Production

1. **Database**: Switch from in-memory to PostgreSQL/MongoDB
2. **Cache**: Add Redis for fuzzy matching results
3. **Storage**: Use S3/GCS for image storage
4. **Monitoring**: Add logging (Winston/Bunyan)
5. **Auth**: Add JWT token validation on API routes

---

## Testing

### Parse Excel

```bash
curl -X POST http://localhost:3001/api/parse \
  -F "file=@menu.xlsx" \
  -F "headerRow=1" \
  -F "nameCol=A" \
  -F "catCol=B"
```

### Match Items

```bash
curl -X POST http://localhost:3001/api/match \
  -H "Content-Type: application/json" \
  -d '{
    "items": [{"name": "Falafel", "category": "Appetizers"}],
    "webhook": "https://..."
  }'
```

### Generate Missing Images

```bash
curl -X POST http://localhost:3001/api/generate \
  -H "Content-Type: application/json" \
  -d '{"items": [{"name": "Pizza Margherita"}]}'
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| **Port 3001 in use** | Change PORT in .env or `npm start -- --port 3002` |
| **CORS error** | Ensure CORS is enabled in server.js |
| **API key rejected** | Verify key in .env, check quota |
| **n8n webhook fails** | Test webhook in n8n UI, check logs |
| **Excel parsing error** | Verify Excel format, check headers |

---

## Rollback

Keep previous version in S3:
```bash
# Before deploy
aws s3 cp dist/ s3://backups/menu-matcher-v1.0/ --recursive

# If needed
aws s3 cp s3://backups/menu-matcher-v1.0/ dist/ --recursive
```

---

**Ready for Production** ✓ | v2.0 | Talabat Branding Applied
