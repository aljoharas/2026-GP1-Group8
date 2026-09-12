-- The "add this game to a list" reminder has been removed at the user's
-- request. This clears out its dedupe index and any rows it already wrote,
-- rather than leaving dead data behind — lib/reminders.js no longer produces
-- this type, so nothing will recreate them.
--
-- Safe to re-run.

DROP INDEX IF EXISTS notifications_pending_list_reminder_key;

DELETE FROM notifications WHERE type = 'list_reminder';
