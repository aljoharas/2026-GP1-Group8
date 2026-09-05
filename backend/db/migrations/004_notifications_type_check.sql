-- The live notifications table carries a type CHECK from before the migrations
-- folder existed: only friend_request, friend_accepted, game_update, reminder
-- were allowed. The reminders feature writes more specific values
-- (game_paused_reminder, log_reminder, list_reminder) so the Flutter app can
-- show a distinct icon per kind — widen the constraint to include them rather
-- than collapsing everything into the single 'reminder' value it already
-- reserved. Same drop-and-recreate pattern as activity_feed_type_check in
-- 001_social.sql, for the same reason: two CHECKs on the same column can't
-- both apply.
--
-- Safe to re-run.

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

DO $$
BEGIN
  ALTER TABLE notifications
    ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
      'friend_request', 'friend_accepted', 'game_update', 'reminder',
      'game_paused_reminder', 'log_reminder', 'list_reminder'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN check_violation THEN NULL;
END $$;
