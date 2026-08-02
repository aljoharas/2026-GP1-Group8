const pool = require('../db/index');

// Every activity type the feed knows how to render. Kept here so a typo in a
// route shows up in the log instead of silently producing a card that the app
// falls back to "updated" for.
const ACTIVITY_TYPES = new Set([
  'game_logged',
  'game_added',
  'game_rated',
  'game_reviewed',
  'status_changed',
  'achievement_unlocked',
  'list_created',
  'list_game_added',
]);

// Writes one row to activity_feed.
//
// Activity is a side effect of the action the user actually asked for, so a
// failure here must not fail their request — every error is swallowed after
// logging. Callers should not await this in a transaction they care about.
//
// `dedupeKey` is optional. Pass one for actions that are edits rather than
// events (a rating the user can change, a review they can rewrite) so the feed
// shows the latest state once instead of a row per keystroke-save.
async function recordActivity({ userId, type, gameId = null, payload = {}, dedupeKey = null }, runner = pool) {
  if (!userId || !type) return;

  if (!ACTIVITY_TYPES.has(type)) {
    console.warn(`[activity] unknown type "${type}" — not recorded`);
    return;
  }

  try {
    // On a repeat of the same dedupe key, refresh the payload and bump the
    // timestamp so the action floats back to the top of the feed. That matches
    // what a friend expects to see: "she just re-rated this", not two cards.
    await runner.query(
      `INSERT INTO activity_feed (user_id, type, game_id, payload, dedupe_key)
       VALUES ($1, $2, $3, $4::jsonb, $5)
       ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
       DO UPDATE SET payload = EXCLUDED.payload, created_at = now()`,
      [userId, type, gameId, JSON.stringify(payload), dedupeKey]
    );
  } catch (error) {
    console.error('[activity] failed to record:', error.message);
  }
}

// Writes one row to notifications. Same fire-and-forget contract as above.
//
// The notifications table predates this feature and stores the other party in
// `related_user_id` with a human-readable `message`. Rather than rename its
// columns, the read path aliases related_user_id to actor_id — so the naming
// here is the only place the older shape shows through.
//
// The partial unique index on (user_id, related_user_id) for friend_request
// means a second tap of "Add friend" refreshes the existing row instead of
// raising, and the recipient sees one request rather than a pile.
async function notify({ userId, actorId = null, type, message }, runner = pool) {
  if (!userId || !type) return;

  // Nobody needs a notification about their own action.
  if (userId === actorId) return;

  try {
    await runner.query(
      `INSERT INTO notifications (user_id, related_user_id, type, message)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, related_user_id) WHERE type = 'friend_request'
       DO UPDATE SET message = EXCLUDED.message, created_at = now(), is_read = FALSE`,
      [userId, actorId, type, message || type]
    );
  } catch (error) {
    console.error('[notify] failed to record:', error.message);
  }
}

// The accepted-friend ids for a user. Friendships are stored once from the
// requester's side, so "who am I friends with" has to look at both columns.
async function getFriendIds(userId, runner = pool) {
  const result = await runner.query(
    `SELECT CASE WHEN requester_id = $1 THEN addressee_id ELSE requester_id END AS friend_id
     FROM friendships
     WHERE (requester_id = $1 OR addressee_id = $1) AND status = 'accepted'`,
    [userId]
  );
  return result.rows.map((r) => r.friend_id);
}

module.exports = { recordActivity, notify, getFriendIds, ACTIVITY_TYPES };
