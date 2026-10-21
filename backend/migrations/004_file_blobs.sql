-- Uploaded documents are also stored here so they survive redeploys on hosts with an ephemeral disk (e.g. Render without a persistent disk).
CREATE TABLE IF NOT EXISTS file_blobs (
  path         TEXT PRIMARY KEY,
  content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
  data         BYTEA NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
