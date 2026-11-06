-- "Your Endgame is here" notification, sent when a year's Wrapped unlocks
-- (Dec 31, Asia/Riyadh; see recommender/wrapped.py release_date). Written by
-- lib/reminders.js remindWrappedReady.
--
-- Widens notifications_type_check with 'wrapped_ready', same drop-and-recreate
-- pattern as 004_notifications_type_check.sql. list_reminder stays allowed:
-- 006 deleted its rows but left the value in the CHECK.
--
-- Safe to re-run.

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

DO $$
BEGIN
  ALTER TABLE notifications
    ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
      'friend_request', 'friend_accepted', 'game_update', 'reminder',
      'game_paused_reminder', 'log_reminder', 'list_reminder',
      'wrapped_ready'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN check_violation THEN NULL;
END $$;

-- User-wide like log_reminder: at most one unread copy per user, as a
-- race-condition safety net for the cooldown check in remindWrappedReady.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_pending_wrapped_ready_key
  ON notifications (user_id)
  WHERE type = 'wrapped_ready' AND is_read = FALSE;
