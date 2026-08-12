-- Menu Image Matcher — login/activity log
-- Paste this into the D1 database's "Console" tab in the Cloudflare dashboard once, after creating the database.
CREATE TABLE IF NOT EXISTS login_log (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  role  TEXT NOT NULL,
  ts    INTEGER NOT NULL,   -- epoch millis, server clock
  ua    TEXT,
  ip    TEXT
);

CREATE INDEX IF NOT EXISTS idx_login_log_ts ON login_log (ts DESC);
