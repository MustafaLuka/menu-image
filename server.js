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
  'فلافل': [{ id: 'falafel-1', name: 'فلافل', url: 'data:image/svg+xml,...', lang: 'ar' }],
  'شاورما': [{ id: 'shawarma-1', name: 'شاورما دجاج', url: 'data:image/svg+xml,...', lang: 'ar' }],
  'burger': [{ id: 'burger-1', name: 'Burger', url: 'data:image/svg+xml,...', lang: 'en' }]
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

// Smart match
app.post('/api/match', async (req, res) => {
  try {
    const { items, webhook } = req.body;
    const matched = {};

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      let best = null, bestScore = 0;

      for (const [key, candidates] of Object.entries(library)) {
        for (const candidate of candidates) {
          const score = fuzzyMatch(item.name, candidate.name);
          if (score > bestScore) {
            bestScore = score;
            best = candidate;
          }
        }
      }

      if (bestScore > 0.7) {
        matched[i] = best.url;
      } else if (webhook) {
        // Send to Claude for intelligent matching
        try {
          await fetch(webhook, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              item_id: i,
              item_name: item.name,
              category: item.category,
              candidates: Object.values(library).flat(),
              callback_url: `${process.env.API_URL || 'http://localhost:3001'}/api/match-result`
            })
          });
        } catch (e) {
          console.log('Claude webhook failed:', e);
        }
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
