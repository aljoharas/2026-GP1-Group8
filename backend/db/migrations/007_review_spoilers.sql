-- Lets a review author mark their review as containing spoilers. Defaults to
-- false so every existing review stays visible exactly as it is today.
--
-- Safe to re-run.

ALTER TABLE library_entries ADD COLUMN IF NOT EXISTS is_spoiler BOOLEAN NOT NULL DEFAULT FALSE;
