// One-time backfill of activity_feed from data that predates the friend feed.
//
// Usage:  node scripts/backfill_activity.js
//
// Without this, a user who adds their first friend sees an empty feed even
// though that friend has logged fifty games. Every insert carries a dedupe_key
// matching the one the live routes use, so this is safe to re-run and won't
// duplicate anything the app has already posted.
//
// Original timestamps are preserved — a game logged in April shows up dated
// April, not dated "now", so the feed reads chronologically from day one.

const pool = require('../db/index');

async function run(label, sql) {
  const result = await pool.query(sql);
  console.log(`  ${label}: ${result.rowCount} row(s) inserted`);
  return result.rowCount;
}

async function main() {
  console.log('Backfilling activity_feed…\n');
  let total = 0;

  // Logged games. Keyed on the library entry id because one user can log the
  // same game more than once and each play-through is its own event.
  total += await run('game_logged', `
    INSERT INTO activity_feed (user_id, type, game_id, payload, created_at, dedupe_key)
    SELECT le.user_id, 'game_logged', le.game_id,
           jsonb_build_object(
             'status',        le.status,
             'hours_played',  le.hours_played,
             'comment',       le.comment,
             'platform_name', p.name
           ),
           le.logged_at,
           'backfill_log:' || le.id
    FROM library_entries le
    LEFT JOIN platforms p ON p.id = le.platform_id
    WHERE le.logged_at IS NOT NULL
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
  `);

  // Ratings. Keyed the same way the live /rate route keys them, so a game
  // rated before the backfill and re-rated after updates one card.
  total += await run('game_rated', `
    INSERT INTO activity_feed (user_id, type, game_id, payload, created_at, dedupe_key)
    SELECT DISTINCT ON (le.user_id, le.game_id)
           le.user_id, 'game_rated', le.game_id,
           jsonb_build_object('rating', le.user_rating::int),
           COALESCE(le.updated_at, le.added_at, now()),
           'rating:' || le.user_id || ':' || le.game_id
    FROM library_entries le
    WHERE le.user_rating IS NOT NULL
    ORDER BY le.user_id, le.game_id, le.updated_at DESC NULLS LAST
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
  `);

  total += await run('game_reviewed', `
    INSERT INTO activity_feed (user_id, type, game_id, payload, created_at, dedupe_key)
    SELECT DISTINCT ON (le.user_id, le.game_id)
           le.user_id, 'game_reviewed', le.game_id,
           jsonb_build_object(
             'review_text', le.review_text,
             'rating',      le.user_rating::int
           ),
           COALESCE(le.updated_at, le.added_at, now()),
           'review:' || le.user_id || ':' || le.game_id
    FROM library_entries le
    WHERE le.review_text IS NOT NULL AND le.review_text <> ''
    ORDER BY le.user_id, le.game_id, le.updated_at DESC NULLS LAST
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
  `);

  // Public lists only — a private list must not leak into anyone's feed.
  total += await run('list_created', `
    INSERT INTO activity_feed (user_id, type, game_id, payload, created_at, dedupe_key)
    SELECT l.user_id, 'list_created', NULL,
           jsonb_build_object('list_id', l.id, 'list_name', l.name, 'emoji', l.emoji),
           l.created_at,
           'list:' || l.id
    FROM lists l
    WHERE l.is_public = TRUE
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
  `);

  total += await run('list_game_added', `
    INSERT INTO activity_feed (user_id, type, game_id, payload, created_at, dedupe_key)
    SELECT l.user_id, 'list_game_added', lg.game_id,
           jsonb_build_object('list_id', l.id, 'list_name', l.name, 'emoji', l.emoji),
           COALESCE(lg.added_at, l.created_at),
           'list_game:' || l.id || ':' || lg.game_id
    FROM list_games lg
    JOIN lists l ON l.id = lg.list_id
    WHERE l.is_public = TRUE
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
  `);

  console.log(`\nDone — ${total} activity row(s) added.`);
}

main()
  .then(() => pool.end())
  .catch((error) => {
    console.error('\nBackfill failed:', error.message);
    pool.end();
    process.exit(1);
  });
