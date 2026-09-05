-- Reminders toggle + paused-game smart notifications.
--
-- notifications_enabled already exists on the live users table (selected by
-- GET /users/me) but nothing writes to it yet; the ALTER below just makes its
-- presence/default explicit for a fresh database. game_id lets a notification
-- point at a specific game the way activity_feed already does.
--
-- Safe to re-run.

ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS game_id INTEGER REFERENCES games(id) ON DELETE CASCADE;

-- One unread paused-game reminder per game at a time — once the user reads it,
-- a fresh pause period can generate another.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_pending_paused_reminder_key
  ON notifications (user_id, game_id)
  WHERE type = 'game_paused_reminder' AND is_read = FALSE;
