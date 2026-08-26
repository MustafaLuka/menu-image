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

-- Audit trail for the library-sync 'approved' action (an operator picked an existing library
-- image for a menu item — no R2 write, just a record of which images get reused often).
CREATE TABLE IF NOT EXISTS match_feedback (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  item_name         TEXT NOT NULL,
  source_library_id INTEGER,
  action            TEXT NOT NULL,   -- 'approved' | 'renamed' | 'generated' | 'uploaded'
  ts                INTEGER NOT NULL -- epoch millis, server clock
);

CREATE INDEX IF NOT EXISTS idx_match_feedback_ts ON match_feedback (ts DESC);
