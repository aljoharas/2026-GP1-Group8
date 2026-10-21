-- Gaming Wrapped early access.
--
-- Wrapped for the current year normally unlocks on Dec 31 (Asia/Riyadh).
-- Users with this flag see it before then, marked is_partial. The flag is read
-- by the Python service (recommender/wrapped.py); nothing in the app writes it
-- yet. Defaults to false so every existing user keeps the normal unlock date.
--
-- Safe to re-run.

ALTER TABLE users ADD COLUMN IF NOT EXISTS wrapped_early_access BOOLEAN NOT NULL DEFAULT FALSE;
