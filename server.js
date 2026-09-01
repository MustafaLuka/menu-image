const express = require('express');
const multer = require('multer');
const xlsx = require('xlsx');
const JSZip = require('jszip');
const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());
const upload = multer({ storage: multer.memoryStorage() });

// Library (in-memory, replace with DB)
const library = {
  'falafel': [{ id: 'falafel-1', name: 'Falafel', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'shawarma': [{ id: 'shawarma-1', name: 'Shawarma', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'salad': [{ id: 'salad-1', name: 'Greek Salad', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'chicken': [{ id: 'chicken-1', name: 'Grilled Chicken', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'baklava': [{ id: 'baklava-1', name: 'Baklava', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'burger': [{ id: 'burger-1', name: 'Burger', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }],
  'pizza': [{ id: 'pizza-1', name: 'Pizza', url: 'data:image/svg+xml,%3Csvg%3E%3Crect fill=%22%23FF5A00%22/%3E%3C/svg%3E', lang: 'en' }]
};

// Parse Excel/CSV
app.post('/api/parse', upload.single('file'), (req, res) => {
  try {
    let items = [];
    const headerRow = parseInt(req.body.headerRow || 1) - 1;
    const nameCol = req.body.nameCol || 'A';
    const catCol = req.body.catCol || 'B';

    if (req.file) {
      const wb = xlsx.read(req.file.buffer, { type: 'buffer' });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const data = xlsx.utils.sheet_to_json(ws, { header: 1, defval: '' });

      items = data.slice(headerRow + 1).map(row => ({
        name: String(row[nameCol.charCodeAt(0) - 65] || '').trim(),
        category: String(row[catCol.charCodeAt(0) - 65] || '').trim(),
        rawRow: row
      })).filter(i => i.name);
    } else if (req.body.text) {
      items = req.body.text.split('\n')
        .map(line => {
          const parts = line.split('-').map(p => p.trim());
          return { name: parts[0], category: 'Other', rawRow: [parts[0]] };
        })
        .filter(i => i.name);
    }

    // Structural anomaly detection
    items = items.map(item => {
      const isCategoryWord = ['تصنيف', 'category', 'قسم', 'section'].some(w => item.name.toLowerCase().includes(w));
      return { ...item, isCategoryRow: isCategoryWord };
    });

    res.json({ items, count: items.length });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// Fuzzy match + synonym lookup
function fuzzyMatch(needle, haystack) {
  needle = needle.toLowerCase();
  haystack = haystack.toLowerCase();
  if (haystack === needle) return 1;
  if (haystack.includes(needle)) return 0.9;
  const damerau = (a, b) => {
    const arr = Array(a.length).fill().map(() => Array(b.length).fill(0));
    for (let i = 0; i <= a.length; i++) arr[i][0] = i;
    for (let j = 0; j <= b.length; j++) arr[0][j] = j;
    for (let i = 1; i <= a.length; i++) {
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i-1] === b[j-1] ? 0 : 1;
        arr[i][j] = Math.min(arr[i-1][j] + 1, arr[i][j-1] + 1, arr[i-1][j-1] + cost);
      }
    }
    return 1 - arr[a.length][b.length] / Math.max(a.length, b.length);
  };
  return damerau(needle, haystack);
}

// Smart match with Claude integration
app.post('/api/match', async (req, res) => {
  try {
    const { items, webhook } = req.body;
    const matched = {};
    const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY || 'sk-IQvLbdYLZFl1Ph_FN_n9hg';

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      let best = null, bestScore = 0;

      // Strategy 1: Try fuzzy match against all library items
      for (const [key, candidates] of Object.entries(library)) {
        const keyScore = fuzzyMatch(item.name, key);
        if (keyScore > bestScore) {
          bestScore = keyScore;
          best = candidates[0];
        }

        for (const candidate of candidates) {
          const score = fuzzyMatch(item.name, candidate.name);
          if (score > bestScore) {
            bestScore = score;
            best = candidate;
          }
        }
      }

      // Strategy 2: Check if item name contains library key (substring match)
      if (bestScore < 0.5) {
        for (const [key, candidates] of Object.entries(library)) {
          if (item.name.toLowerCase().includes(key) || key.includes(item.name.toLowerCase().split(' ')[0])) {
            bestScore = 0.8;
            best = candidates[0];
            break;
          }
        }
      }

      // Strategy 3: Use Claude for final matching
      if (bestScore < 0.7 && ANTHROPIC_KEY) {
        try {
          const candidates = Object.values(library).flat().map(c => c.name).join(', ');
          const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'anthropic-version': '2023-06-01',
              'x-api-key': ANTHROPIC_KEY
            },
            body: JSON.stringify({
              model: 'claude-opus-5',
              max_tokens: 30,
              messages: [{
                role: 'user',
                content: `Match "${item.name}" to: ${candidates}. Reply: just the name.`
              }]
            })
          });

          if (claudeResponse.ok) {
            const claudeData = await claudeResponse.json();
            if (claudeData.content && claudeData.content[0]) {
              const selectedName = claudeData.content[0].text.trim().toLowerCase();
              const selected = Object.values(library).flat().find(c =>
                c.name.toLowerCase().includes(selectedName) || selectedName.includes(c.name.toLowerCase())
              );
              if (selected) {
                best = selected;
                bestScore = 0.9;
              }
            }
          }
        } catch (e) {
          console.log('Claude API error:', e.message);
        }
      }

      // Accept match if score > 0.5
      if (bestScore > 0.5 && best) {
        matched[i] = best.url;
      }
    }

    res.json({ matched, count: Object.keys(matched).length });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// Direct Claude matching (workaround for slow deployment)
app.post('/api/menu/match-claude', async (req, res) => {
  try {
    const { items } = req.body;
    const matched = {};
    const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY || 'sk-IQvLbdYLZFl1Ph_FN_n9hg';

    const candidates = Object.values(library).flat().map(c => c.name).join(', ');

    for (let i = 0; i < items.length; i++) {
      const item = items[i];

      try {
        const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'anthropic-version': '2023-06-01',
            'x-api-key': ANTHROPIC_KEY
          },
          body: JSON.stringify({
            model: 'claude-opus-5',
            max_tokens: 30,
            messages: [{
              role: 'user',
              content: `Best match for "${item.name}" (${item.category}) from: ${candidates}. Reply: just the name.`
            }]
          })
        });

        if (claudeResponse.ok) {
          const claudeData = await claudeResponse.json();
          if (claudeData.content && claudeData.content[0]) {
            const selectedName = claudeData.content[0].text.trim().toLowerCase();
            const selected = Object.values(library).flat().find(c =>
              c.name.toLowerCase().includes(selectedName) ||
              selectedName.includes(c.name.toLowerCase())
            );
            if (selected) matched[i] = selected.url;
          }
        }
      } catch (e) {
        console.log('Claude match error for item', i, ':', e.message);
      }
    }

    res.json({ matched, count: Object.keys(matched).length });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// Match result callback from n8n
app.post('/api/match-result', (req, res) => {
  const { item_id, selected_image, status } = req.body;
  if (status === 'matched') {
    // Store in cache
    console.log(`Item ${item_id} matched to image`);
  }
  res.json({ ok: true });
});

// AI image generation
app.post('/api/generate', async (req, res) => {
  try {
    const { items } = req.body;
    const generated = [];

    for (const item of items) {
      // Placeholder - replace with actual Gemini/DALL-E call
      const svg = `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='300'%3E%3Crect fill='%23FF5A00' width='300' height='300'/%3E%3Ctext x='50%25' y='50%25' dominant-baseline='middle' text-anchor='middle' fill='white' font-size='20' font-family='Arial'%3E${item.name}%3C/text%3E%3C/svg%3E`;
      generated.push({ item, image: svg });
    }

    res.json({ generated, count: generated.length });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// Export to ZIP
app.post('/api/export', async (req, res) => {
  try {
    const { items, matched } = req.body;
    const zip = new JSZip();

    // Create xlsx with matched items
    const exportData = items.map((item, i) => ({
      'Item Name': item.name,
      'Category': item.category,
      'Matched': matched[i] ? 'Yes' : 'No',
      'Image': matched[i] ? 'included' : 'missing'
    }));

    const ws = xlsx.utils.json_to_sheet(exportData);
    const wb = xlsx.utils.book_new();
    xlsx.utils.book_append_sheet(wb, ws, 'Menu');
    const xlsxBuffer = xlsx.write(wb, { bookType: 'xlsx', type: 'buffer' });

    zip.file('menu.xlsx', xlsxBuffer);

    // Add images (as data URLs or metadata)
    let idx = 0;
    for (const [i, image] of Object.entries(matched)) {
      if (image) {
        zip.file(`images/${items[i].name.replace(/\s+/g, '_')}.txt`, `Image URL: ${image}`);
      }
    }

    // Add manifest
    zip.file('manifest.json', JSON.stringify({
      timestamp: new Date().toISOString(),
      totalItems: items.length,
      matchedCount: Object.keys(matched).length,
      items: items
    }, null, 2));

    const blob = await zip.generateAsync({ type: 'nodebuffer' });
    res.set('Content-Type', 'application/zip');
    res.set('Content-Disposition', 'attachment; filename=menu-images.zip');
    res.send(blob);
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// Library sync (called from n8n)
app.post('/api/library-sync', (req, res) => {
  const { images, operation } = req.body;
  console.log(`Syncing ${images.length} images (${operation})`);
  // Update library DB here
  res.json({ synced: images.length, timestamp: new Date().toISOString() });
});

// Email delivery (called from n8n)
app.post('/api/email-deliver', (req, res) => {
  const { to, subject, items, matched } = req.body;
  console.log(`Email to ${to}: ${subject}`);
  res.json({ sent: true, recipient: to });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`Menu Matcher API running on :${PORT}`));
