-- Social graph + activity feed + notifications.
--
-- friendships, activity_feed and notifications already exist in the live
-- database (all three empty at the time this was written). This migration
-- adapts them rather than replacing them, so it only adds what the friend feed
-- needs and leaves the existing columns alone:
--
--   friendships    — gains a surrogate id and updated_at. The primary key stays
--                    (addressee_id, requester_id), which already enforces one
--                    row per pair.
--   activity_feed  — gains dedupe_key so re-runnable backfills and edit-style
--                    activity (ratings, reviews) don't stack duplicate rows.
--   notifications  — unchanged shape. It keeps message/related_user_id as
--                    built; the app aliases related_user_id to actor_id when
--                    reading, so nothing has to be renamed.
--
-- Safe to re-run.

-- ── friendships ──────────────────────────────────────────────────────────────
-- A relationship is one row stored from the requester's side. A pair counts as
-- friends when status = 'accepted', regardless of direction, so every read has
-- to check both columns.

CREATE TABLE IF NOT EXISTS friendships (
  requester_id TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       TEXT        NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (addressee_id, requester_id)
);

-- Accept/decline address a request by a single id rather than a composite key,
-- which keeps the API and the Flutter models simple.
--
-- Deliberately int4, not bigint: node-postgres returns bigint as a *string* to
-- avoid precision loss, so the id would reach Flutter as "1" and blow up the
-- `as int` cast on the request. int4 arrives as a real number, and this table
-- will never come close to 2^31 rows. The ALTER is a no-op once applied.
ALTER TABLE friendships ADD COLUMN IF NOT EXISTS id         SERIAL;
ALTER TABLE friendships ALTER COLUMN id TYPE INTEGER;
ALTER TABLE friendships ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS friendships_id_key ON friendships (id);

CREATE INDEX IF NOT EXISTS friendships_addressee_status_idx
  ON friendships (addressee_id, status);
CREATE INDEX IF NOT EXISTS friendships_requester_status_idx
  ON friendships (requester_id, status);

DO $$
BEGIN
  ALTER TABLE friendships
    ADD CONSTRAINT friendships_no_self CHECK (requester_id <> addressee_id);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- The table as originally built allowed only 'pending' and 'accepted'.
-- Declining has to be recorded — dropping the row instead would let a rejected
-- requester re-send immediately and keep pestering. The old constraint is
-- replaced rather than added to, since two CHECKs both have to pass.
ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_status_check;

DO $$
BEGIN
  ALTER TABLE friendships
    ADD CONSTRAINT friendships_status_valid
    CHECK (status IN ('pending', 'accepted', 'declined'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
  -- An existing row carrying some other status would fail the check; leave the
  -- table as it is rather than aborting the migration.
  WHEN check_violation THEN NULL;
END $$;

-- friendships_check is the original, identical self-reference guard. Dropping
-- it leaves friendships_no_self above as the single definition on both a live
-- database and a freshly created one.
ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_check;

-- ── activity_feed ────────────────────────────────────────────────────────────
-- Append-only log of what a user did. game_id is nullable because list activity
-- isn't tied to a single game.

CREATE TABLE IF NOT EXISTS activity_feed (
  id         BIGSERIAL PRIMARY KEY,
  user_id    TEXT        REFERENCES users(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL,
  game_id    INTEGER     REFERENCES games(id) ON DELETE CASCADE,
  payload    JSONB       DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Lets the backfill re-run without duplicating, and stops a re-saved rating
-- from posting a second card. Nullable on purpose: activity with no natural key
-- (a plain log entry) leaves it NULL, and Postgres treats NULLs as distinct.
ALTER TABLE activity_feed ADD COLUMN IF NOT EXISTS dedupe_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS activity_feed_dedupe_key
  ON activity_feed (dedupe_key) WHERE dedupe_key IS NOT NULL;

-- The feed query is "rows for these N users, newest first".
CREATE INDEX IF NOT EXISTS activity_feed_user_created_idx
  ON activity_feed (user_id, created_at DESC);

-- The original type vocabulary predates logging, reviews, and adding a game to
-- a list, so those three inserts were rejected outright. Replaced rather than
-- supplemented, because two CHECK constraints both have to pass. The older
-- names are kept so any row written against the previous vocabulary stays
-- valid, and lib/activity.js mirrors this list.
ALTER TABLE activity_feed DROP CONSTRAINT IF EXISTS activity_feed_type_check;

DO $$
BEGIN
  ALTER TABLE activity_feed
    ADD CONSTRAINT activity_feed_type_check
    CHECK (type IN (
      'game_logged', 'game_added', 'game_rated', 'game_reviewed',
      'status_changed', 'achievement_unlocked',
      'list_created', 'list_updated', 'list_game_added'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN check_violation THEN NULL;
END $$;

-- ── notifications ────────────────────────────────────────────────────────────
-- Existing shape, kept as-is: user_id is the recipient, related_user_id is
-- whoever caused it, message is the human-readable line.

CREATE TABLE IF NOT EXISTS notifications (
  id              BIGSERIAL PRIMARY KEY,
  user_id         TEXT        REFERENCES users(id) ON DELETE CASCADE,
  type            TEXT        NOT NULL,
  message         TEXT        NOT NULL,
  related_user_id TEXT        REFERENCES users(id) ON DELETE CASCADE,
  is_read         BOOLEAN     DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_created_idx
  ON notifications (user_id, created_at DESC);

-- Powers the unread dot without scanning rows already read.
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx
  ON notifications (user_id) WHERE is_read = FALSE;

-- A pending friend request should surface once, not once per tap of "Add
-- friend". The row is deleted when the request is resolved, so re-adding
-- someone later still notifies.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_pending_friend_request_key
  ON notifications (user_id, related_user_id)
  WHERE type = 'friend_request';

-- ── users.username search ────────────────────────────────────────────────────
-- /users/search matches case-insensitively on username.
CREATE INDEX IF NOT EXISTS users_username_lower_idx ON users (lower(username));
