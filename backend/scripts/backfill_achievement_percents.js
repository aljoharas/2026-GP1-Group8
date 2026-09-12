/**
 * Backfill achievement `percent` for games whose cached achievements were
 * stored before RAWG's percent data was being read correctly.
 *
 * The /games/:id/achievements route used to treat "any cached rows exist"
 * as a full cache hit, even when every row had percent = null, so those
 * games were never refreshed. This one-time script re-fetches achievements
 * from RAWG for just the affected games and updates their percent values.
 *
 * These same rows also predate a schema change: api_name used to store the
 * achievement's display name instead of RAWG's numeric achievement id, so
 * it no longer matches the (game_id, api_name) shape the live route uses.
 * We match old rows to fresh RAWG data by display_name (unique per game),
 * then UPDATE in place — never delete/reinsert — since achievements.id is
 * referenced by user_achievements.achievement_id and must stay stable.
 *
 * Run: node scripts/backfill_achievement_percents.js
 */

require('dotenv').config();
const pool = require('../db');

const RAWG_KEY = process.env.RAWG_API_KEY;
const RAWG_BASE = 'https://api.rawg.io/api';
const DELAY_MS = 300; // be polite to RAWG between games

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchAllAchievements(rawgId) {
  let all = [];
  let url = `${RAWG_BASE}/games/${rawgId}/achievements?page_size=40&key=${RAWG_KEY}`;
  while (url && all.length < 200) {
    const response = await fetch(url);
    if (!response.ok) break;
    const data = await response.json();
    all = all.concat(data.results || []);
    url = data.next || null;
  }
  return all;
}

async function main() {
  const { rows: affected } = await pool.query(`
    SELECT g.id AS game_id, g.rawg_id
    FROM games g
    JOIN achievements a ON a.game_id = g.id
    GROUP BY g.id, g.rawg_id
    HAVING count(a.percent) = 0
    ORDER BY g.id
  `);

  console.log(`Found ${affected.length} games with all-null achievement percent.`);

  let updatedGames = 0;
  let updatedRows = 0;
  let stillMissing = 0;

  for (const { game_id, rawg_id } of affected) {
    process.stdout.write(`[game_id=${game_id} rawg_id=${rawg_id}] fetching RAWG achievements...`);
    let achievements;
    try {
      achievements = await fetchAllAchievements(rawg_id);
    } catch (err) {
      console.log(` ✗ ${err.message}`);
      await sleep(DELAY_MS);
      continue;
    }

    const byName = new Map(achievements.map(a => [a.name, a]));
    const { rows: existing } = await pool.query(
      'SELECT id, display_name FROM achievements WHERE game_id = $1',
      [game_id]
    );

    let rowsForThisGame = 0;
    let unmatched = 0;
    for (const row of existing) {
      const match = byName.get(row.display_name);
      if (!match) { unmatched += 1; continue; }
      const pct = match.percent != null ? parseFloat(match.percent) : null;
      const result = await pool.query(
        `UPDATE achievements SET api_name = $1, percent = $2 WHERE id = $3`,
        [String(match.id), Number.isFinite(pct) ? pct : null, row.id]
      );
      rowsForThisGame += result.rowCount;
    }

    if (rowsForThisGame > 0) {
      updatedGames += 1;
      updatedRows += rowsForThisGame;
      console.log(` ✓ ${rowsForThisGame} rows updated${unmatched ? `, ${unmatched} unmatched` : ''}`);
    } else {
      stillMissing += 1;
      console.log(' — no matching RAWG data found');
    }

    await sleep(DELAY_MS);
  }

  console.log(`\nDone. Games updated: ${updatedGames} | Rows updated: ${updatedRows} | Still no data: ${stillMissing}`);
  process.exit(0);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
