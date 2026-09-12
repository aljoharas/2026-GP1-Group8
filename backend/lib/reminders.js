const pool = require('../db/index');

const PAUSE_THRESHOLD = '3 days';
const LOG_INACTIVITY_THRESHOLD = '7 days';

// How long a repeat reminder of the same kind (same user, same game where
// applicable) stays suppressed after one was last sent — regardless of
// whether that one has been read. Without this, reading a reminder while the
// underlying condition is still true (the game is still paused) let the very
// next check re-create it immediately, since the old dedupe index only ever
// blocked a second *unread* copy.
const RENOTIFY_COOLDOWN = '3 days';

// Nudges a user about games they've neglected. Fire-and-forget, same
// contract as lib/activity.js: called on the way to answering an unrelated
// request (checking the notification bell), so a failure here must not fail
// that request.
//
// Each reminder type has its own partial unique index (see
// db/migrations/002_reminders.sql and 003_reminders_v2.sql) as a race-condition
// safety net, and each check also excludes anything already reminded within
// RENOTIFY_COOLDOWN — so calling this on every unread-count check won't stack
// duplicates, and won't re-fire the moment a reminder is read either.
//
// The unlisted-game reminder (list_reminder) that used to live here has been
// removed at the user's request; db/migrations/006_remove_list_reminder.sql
// retires its rows and dedupe index rather than leaving them behind unused.
//
// Returns the notifications actually inserted this call (empty on a repeat
// call where nothing has cleared its cooldown yet) — the push scheduler uses
// this to know what's actually new and worth pushing.
async function checkReminders(userId) {
  if (!userId) return [];

  try {
    const user = await pool.query(
      'SELECT notifications_enabled FROM users WHERE id = $1',
      [userId]
    );
    if (user.rows.length === 0 || user.rows[0].notifications_enabled === false) return [];

    // Sequential, not Promise.all: this runs from a cron tick over every user
    // (see lib/reminderScheduler.js), and a background job has no latency
    // pressure — no reason to hold 3x the DB connections at once against a
    // pooler that may cap concurrent sessions low (e.g. Supabase's
    // session-mode pooler defaults to 15 total).
    const created = [
      ...(await remindPausedGames(userId)),
      ...(await remindToLog(userId)),
    ];
    return created;
  } catch (error) {
    console.error('[reminders] failed to check:', error.message);
    return [];
  }
}

// A game paused for a while and never resumed.
async function remindPausedGames(userId) {
  const paused = await pool.query(
    `SELECT le.game_id, g.name
     FROM library_entries le
     JOIN games g ON g.id = le.game_id
     WHERE le.user_id = $1
       AND le.status = 'paused'
       AND le.updated_at < now() - interval '${PAUSE_THRESHOLD}'
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
         WHERE n.user_id = $1 AND n.game_id = le.game_id AND n.type = 'game_paused_reminder'
           AND n.created_at > now() - interval '${RENOTIFY_COOLDOWN}'
       )`,
    [userId]
  );

  const inserted = [];
  for (const { game_id, name } of paused.rows) {
    const message = `You paused ${name}. Ready to jump back in?`;
    const result = await pool.query(
      `INSERT INTO notifications (user_id, type, message, game_id)
       VALUES ($1, 'game_paused_reminder', $2, $3)
       ON CONFLICT (user_id, game_id) WHERE type = 'game_paused_reminder' AND is_read = FALSE
       DO NOTHING
       RETURNING id`,
      [userId, message, game_id]
    );
    if (result.rows.length > 0) inserted.push({ message });
  }
  return inserted;
}

// General inactivity nudge — only for users who have logged at least one game
// before, so a brand-new account isn't nagged before it's used the feature.
async function remindToLog(userId) {
  // HAVING with no GROUP BY collapses to 0 or 1 row: 0 if the user has never
  // logged a game (MAX is NULL) or their last log is still recent.
  const stale = await pool.query(
    `SELECT 1
     FROM library_entries
     WHERE user_id = $1 AND logged_at IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
         WHERE n.user_id = $1 AND n.type = 'log_reminder'
           AND n.created_at > now() - interval '${RENOTIFY_COOLDOWN}'
       )
     HAVING MAX(logged_at) < now() - interval '${LOG_INACTIVITY_THRESHOLD}'`,
    [userId]
  );
  if (stale.rows.length === 0) return [];

  const message = "You haven't logged any games in a while. What have you been playing?";
  const result = await pool.query(
    `INSERT INTO notifications (user_id, type, message)
     VALUES ($1, 'log_reminder', $2)
     ON CONFLICT (user_id) WHERE type = 'log_reminder' AND is_read = FALSE
     DO NOTHING
     RETURNING id`,
    [userId, message]
  );
  return result.rows.length > 0 ? [{ message }] : [];
}

module.exports = { checkReminders };
