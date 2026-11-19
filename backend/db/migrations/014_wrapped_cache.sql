-- wrapped_cache: stored Endgame (Gaming Wrapped) responses, one row per user
-- and year. Written and read by the Python service (recommender/wrapped_cache.py).
--
-- Used only during a year's release window, Dec 31 through Jan 14 of the next
-- year (Asia/Riyadh), and only for normal users; early-access users are always
-- calculated live and never stored. On Dec 31 every open recalculates and
-- replaces the row; from Jan 1 a row is served only if generated_at is on or
-- after Jan 1 00:00 Riyadh, so a Dec 31 snapshot is never served as final.
-- After Jan 14 the service's daily cleanup deletes that year's rows.
--
-- payload is exactly the JSON body /wrapped returns.
-- user_id is TEXT to match public.users.id (Firebase UID).
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS wrapped_cache (
  user_id      TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  year         INTEGER     NOT NULL,
  payload      JSONB       NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, year)
);

-- Cleanup deletes by year across all users
CREATE INDEX IF NOT EXISTS wrapped_cache_year_idx ON wrapped_cache (year);

ALTER TABLE wrapped_cache ENABLE ROW LEVEL SECURITY;
