// Menu Image Matcher — Cloudflare Worker backend (cloud version)
//
// Bindings expected (see worker/README.md for how to create/attach these
// via the Cloudflare dashboard — no wrangler/Node required):
//   MM_KV        KV namespace   — auth codes ("code:<CODE>" -> {role}) + sessions ("session:<token>" -> {role,email,iat})
//   DB           D1 database    — login_log table (see worker/schema.sql)
//   MENU_IMAGES  R2 bucket      — the existing "menu-images" bucket (index.json + img/<id>.<ext>)
//   GEMINI_API_KEY  secret      — real Gemini API key, never sent to the client
//
// Endpoints:
//   POST /api/login      {code, email?}              -> {ok, token, role, email}
//   POST /api/gemini     {model, body}  (Bearer)      -> Gemini's response, forwarded verbatim
//   POST /api/cloud-add  {name, b64, pull} (Bearer, admin) -> {ok, id, file}
//   GET  /api/log?limit=50                (Bearer, admin) -> {ok, rows:[{email,date,ua}]}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getSession(env, token) {
  if (!token) return null;
  const raw = await env.MM_KV.get(`session:${token}`);
  return raw ? JSON.parse(raw) : null;
}

function bearerToken(req) {
  const h = req.headers.get('Authorization') || '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

async function requireSession(req, env, roleRequired) {
  const session = await getSession(env, bearerToken(req));
  if (!session) return { error: json({ ok: false, error: 'unauthorized' }, 401) };
  if (roleRequired && session.role !== roleRequired) {
    return { error: json({ ok: false, error: 'forbidden' }, 403) };
  }
  return { session };
}

// ----- POST /api/login -----
async function handleLogin(req, env) {
  let body;
  try { body = await req.json(); } catch (e) { return json({ ok: false, error: 'bad json' }, 400); }
  const code = (body.code || '').trim();
  if (!code) return json({ ok: false, error: 'code required' }, 400);

  const codeRaw = await env.MM_KV.get(`code:${code}`);
  if (!codeRaw) return json({ ok: false, error: 'invalid code' }, 401);
  const { role } = JSON.parse(codeRaw);

  let email = (body.email || '').trim().toLowerCase();
  if (role === 'user') {
    if (!email.endsWith('@talabat.com')) {
      return json({ ok: false, error: 'email must be @talabat.com' }, 400);
    }
  } else {
    email = email || '';
  }

  const token = randomToken();
  await env.MM_KV.put(`session:${token}`, JSON.stringify({ role, email, iat: Date.now() }), {
    expirationTtl: 60 * 60 * 24, // 24h
  });

  // log the login server-side — no separate client-fired call, can't be spoofed or dropped
  try {
    const ua = (req.headers.get('User-Agent') || '').slice(0, 200);
    const ip = req.headers.get('CF-Connecting-IP') || '';
    await env.DB.prepare(
      'INSERT INTO login_log (email, role, ts, ua, ip) VALUES (?, ?, ?, ?, ?)'
    ).bind(email, role, Date.now(), ua, ip).run();
  } catch (e) {
    // never fail the login because logging failed
    console.error('login_log insert failed', e);
  }

  return json({ ok: true, token, role, email });
}

// ----- POST /api/gemini -----
async function handleGemini(req, env) {
  const auth = await requireSession(req, env, null);
  if (auth.error) return auth.error;

  let payload;
  try { payload = await req.json(); } catch (e) { return json({ ok: false, error: 'bad json' }, 400); }
  const { model, body } = payload;
  if (!model || !body) return json({ ok: false, error: 'model and body required' }, 400);

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${env.GEMINI_API_KEY}`;
  const upstream = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

// ----- POST /api/cloud-add -----
function extOf(name) {
  const m = String(name).match(/\.[^.]+$/);
  return m ? m[0] : '.jpg';
}

async function handleCloudAdd(req, env) {
  const auth = await requireSession(req, env, 'admin');
  if (auth.error) return auth.error;

  let payload;
  try { payload = await req.json(); } catch (e) { return json({ ok: false, error: 'bad json' }, 400); }
  const { name, b64 } = payload;
  if (!name || !b64) return json({ ok: false, error: 'name and b64 required' }, 400);

  const bytes = b64ToBytes(b64);
  const ext = extOf(name);

  // read-modify-write index.json with a conditional-put retry against concurrent admins
  for (let attempt = 0; attempt < 5; attempt++) {
    const idxObj = await env.MENU_IMAGES.get('index.json');
    const list = idxObj ? JSON.parse(await idxObj.text()) : [];
    const etag = idxObj ? idxObj.httpEtag : undefined;

    let nextId = 0;
    for (const e of list) if (typeof e.id === 'number' && e.id >= nextId) nextId = e.id + 1;

    const file = `img/${nextId}${ext}`;
    await env.MENU_IMAGES.put(file, bytes);
    list.push({ id: nextId, name, file });

    const putResult = await env.MENU_IMAGES.put('index.json', JSON.stringify(list), {
      onlyIf: etag ? { etagMatches: etag } : undefined,
    });
    if (putResult) {
      return json({ ok: true, id: nextId, file });
    }
    // etag mismatch (another admin wrote concurrently) — retry the whole read-modify-write
  }
  return json({ ok: false, error: 'too much contention on index.json, try again' }, 409);
}

// ----- GET /api/log -----
async function handleLog(req, env, url) {
  const auth = await requireSession(req, env, 'admin');
  if (auth.error) return auth.error;

  const limit = Math.min(200, parseInt(url.searchParams.get('limit') || '50', 10) || 50);
  const { results } = await env.DB.prepare(
    'SELECT email, ts, ua FROM login_log ORDER BY ts DESC LIMIT ?'
  ).bind(limit).all();

  const rows = (results || []).map(r => ({
    email: r.email,
    date: new Date(r.ts).toISOString(),
    ua: r.ua,
  }));
  return json({ ok: true, rows });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (req.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    try {
      if (url.pathname === '/api/login' && req.method === 'POST') return await handleLogin(req, env);
      if (url.pathname === '/api/gemini' && req.method === 'POST') return await handleGemini(req, env);
      if (url.pathname === '/api/cloud-add' && req.method === 'POST') return await handleCloudAdd(req, env);
      if (url.pathname === '/api/log' && req.method === 'GET') return await handleLog(req, env, url);
      return json({ ok: false, error: 'not found' }, 404);
    } catch (err) {
      console.error(err);
      return json({ ok: false, error: String(err && err.message || err) }, 500);
    }
  },
};
