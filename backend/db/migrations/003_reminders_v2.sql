-- Reminders v2: general log-inactivity nudge + add-to-list nudge, alongside
-- the existing paused-game reminder from 002_reminders.sql.
--
-- Safe to re-run.

-- log_reminder is user-wide (game_id is always NULL for it), so it dedupes on
-- user_id alone rather than the (user_id, game_id) pair.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_pending_log_reminder_key
  ON notifications (user_id)
  WHERE type = 'log_reminder' AND is_read = FALSE;

-- list_reminder points at a specific game, same shape as the paused-game
-- reminder's dedupe index.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_pending_list_reminder_key
  ON notifications (user_id, game_id)
  WHERE type = 'list_reminder' AND is_read = FALSE;
