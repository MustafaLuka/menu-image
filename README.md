# Menu Matcher 2.0 — Talabat Modernized

Smart Excel menu parsing + AI image matching + n8n automation.

## Quick Start

```bash
cd C:\ME\menu-matcher
npm install
npm start
```

Open http://localhost:3001

## Architecture

| Component | Purpose |
|-----------|---------|
| `index.html` | Talabat-branded UI (upload → match → export) |
| `server.js` | Parse, fuzzy match, generate images, export ZIP |
| `n8n-workflows.json` | Claude matching, smart suggestions, library sync |

## Features

✅ Smart Excel parser with anomaly detection  
✅ Fuzzy matching + synonym lookup (local)  
✅ AI image generation integration  
✅ n8n webhook automation  
✅ ZIP export with manifest  
✅ Email delivery via n8n  

## n8n Setup

1. Import `n8n-workflows.json` to your n8n instance
2. Get webhook URLs for each workflow
3. Paste URLs in Admin panel (⚙️)
4. Click "Match Now" — Claude will handle ambiguous items

## Webhooks

- `menu-matcher-match-item`: Claude smart matching
- `menu-matcher-smart-suggestions`: AI re-ranking
- `menu-matcher-library-sync`: Cloud sync
- `menu-matcher-email-deliver`: Email delivery

## Credentials

Set environment variables:
```
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AI...
```

## Database

Currently uses in-memory library. Replace `library` object in `server.js` with DB queries for production.

---

**Ready for deployment** ✓
