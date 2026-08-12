# Menu Image Matcher — Cloudflare Worker backend

Replaces four fragile per-browser mechanisms (hardcoded auth codes, per-admin
Gemini API keys, per-admin login-log webhooks, per-admin cloud-upload
endpoints) with one small Worker. No Node.js/npm/wrangler needed — every step
below is done through the Cloudflare dashboard.

## 1. Create the Worker

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Create Worker**.
2. Name it (e.g. `menu-matcher-api`). Deploy the default "Hello World" first,
   then open **Edit code** and replace the entire contents with `worker/index.js`
   from this repo. Click **Deploy**.
3. Note the resulting URL, e.g. `https://menu-matcher-api.<your-subdomain>.workers.dev`.
   This is `WORKER_BASE` — you'll paste it into `index.html`.

## 2. KV namespace (auth codes + sessions)

1. **Workers & Pages** → **KV** → **Create namespace** → name it `MM_KV`.
2. Open the namespace → **Add entry** and create the two starter codes
   (these replace the old `AUTH_CODES` object that used to be visible in the
   shipped JS):
   - Key: `code:TLB_ADMIN_2026`  Value: `{"role":"admin"}`
   - Key: `code:TLB_LUKA_2026`   Value: `{"role":"user"}`
   Add/rotate more codes the same way at any time — no redeploy needed.
3. Go back to your Worker → **Settings** → **Bindings** → **Add binding** →
   **KV Namespace** → variable name `MM_KV` → select the namespace you created.

## 3. D1 database (login/activity log)

1. **Workers & Pages** → **D1** → **Create database** → name it `mm_log`.
2. Open it → **Console** tab → paste the contents of `worker/schema.sql` → **Execute**.
3. Worker → **Settings** → **Bindings** → **Add binding** → **D1 Database** →
   variable name `DB` → select `mm_log`.

## 4. R2 bucket binding (existing bucket, no new data)

1. Worker → **Settings** → **Bindings** → **Add binding** → **R2 Bucket** →
   variable name `MENU_IMAGES` → select the existing `menu-images` bucket
   (the same one `R2_BASE` in `index.html` already reads from — this just
   lets the Worker write to it too).

## 5. Gemini API key secret

1. Worker → **Settings** → **Variables** → **Add variable** under
   "Environment Variables" → name `GEMINI_API_KEY` → paste the real key →
   toggle **Encrypt** → **Save and deploy**.
   This key is never sent to the browser — the Worker injects it server-side.

## 6. Point the app at the Worker

In `index.html`, set `WORKER_BASE` (near `R2_BASE`) to the URL from step 1,
then deploy `index.html` as usual (push to GitHub Pages / vibehost).

## Updating the Worker later

Any time `worker/index.js` changes: Worker → **Edit code** → paste the new
contents → **Deploy**. That's the entire release process — no build step.

## Verifying it works (from a terminal, e.g. `curl`)

```bash
# should return {"ok":true,"token":"...","role":"admin","email":""}
curl -s -X POST https://<WORKER_BASE>/api/login -H "Content-Type: application/json" -d '{"code":"TLB_ADMIN_2026"}'

# should return 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://<WORKER_BASE>/api/login -H "Content-Type: application/json" -d '{"code":"WRONG"}'

# using the token from the first call, should return recent logins (including the two calls above)
curl -s "https://<WORKER_BASE>/api/log" -H "Authorization: Bearer <token>"
```
