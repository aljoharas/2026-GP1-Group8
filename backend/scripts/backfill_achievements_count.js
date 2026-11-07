/**
 * Backfill games.achievements_count from RAWG game details (achievements_count).
 * Needs migration 013. New games get the count from saveGameToDB; this fills
 * the games saved before that. One RAWG request per game, at most one per
 * second; 429s, 5xx (including Cloudflare's 52x when RAWG is down), timeouts
 * and non-JSON answers are retried with exponential backoff.
 *
 * Only games with a NULL count are fetched, so it can be re-run safely; games
 * RAWG has no count for stay NULL and are fetched again next time.
 * Games in manual logs go first: they are the ones Player Archetypes reads.
 *
 * Run: node scripts/backfill_achievements_count.js [--dry-run]
 *   --dry-run  fetch and report, write nothing
 */

require('dotenv').config();
const pool = require('../db');

const RAWG_KEY = process.env.RAWG_API_KEY;
const RAWG_BASE = 'https://api.rawg.io/api';
const DELAY_MS = 1000;        // at most one RAWG request per second
const TIMEOUT_MS = 20000;     // per attempt
const MAX_ATTEMPTS = 5;       // backoff 2s, 4s, 8s, 16s between them
const MAX_FAILS_IN_A_ROW = 3; // then RAWG is down: stop instead of retrying every game
const DRY_RUN = process.argv.includes('--dry-run');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

class RetryableError extends Error {}

async function fetchOnce(rawgId) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${RAWG_BASE}/games/${rawgId}?key=${RAWG_KEY}`, { signal: controller.signal });
    if (response.status === 429 || response.status >= 500) {
      const retryAfter = Number(response.headers.get('retry-after'));
      const err = new RetryableError(`RAWG ${response.status}`);
      err.retryAfterMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 0;
      throw err;
    }
    if (!response.ok) throw new Error(`RAWG ${response.status}`);
    let body;
    try {
      body = await response.json();
    } catch {
      throw new RetryableError('RAWG sent a non-JSON body');
    }
    const count = body.achievements_count;
    return Number.isInteger(count) && count >= 0 ? count : null;
  } catch (err) {
    if (err.name === 'AbortError') throw new RetryableError(`RAWG timed out after ${TIMEOUT_MS}ms`);
    if (err instanceof TypeError) throw new RetryableError(`network error: ${err.message}`);
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchAchievementsCount(rawgId) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fetchOnce(rawgId);
    } catch (err) {
      if (!(err instanceof RetryableError) || attempt === MAX_ATTEMPTS) throw err;
      const backoff = Math.max(2000 * 2 ** (attempt - 1), err.retryAfterMs || 0);
      console.warn(`  ${err.message}; retry ${attempt}/${MAX_ATTEMPTS - 1} in ${backoff / 1000}s`);
      await sleep(backoff);
    }
  }
}

async function main() {
  const { rows: games } = await pool.query(`
    SELECT g.id, g.rawg_id, g.name,
           EXISTS (
             SELECT 1 FROM library_entries le
             WHERE le.game_id = g.id AND le.source = 'manual'
           ) AS in_manual_logs
    FROM games g
    WHERE g.achievements_count IS NULL
      AND g.rawg_id IS NOT NULL
    ORDER BY in_manual_logs DESC, g.id
  `);

  console.log(`${games.length} games without achievements_count${DRY_RUN ? ' (dry run)' : ''}\n`);

  let withCount = 0;
  let zero = 0;
  let noCount = 0;
  let failed = 0;
  let failsInARow = 0;

  for (const game of games) {
    if (failsInARow === MAX_FAILS_IN_A_ROW) {
      console.error(`\n${MAX_FAILS_IN_A_ROW} games failed in a row; RAWG looks down. Stopping; re-run later.`);
      process.exitCode = 1;
      break;
    }
    try {
      const count = await fetchAchievementsCount(game.rawg_id);
      if (count === null) noCount++;
      else if (count === 0) zero++;
      else withCount++;
      if (!DRY_RUN && count !== null) {
        await pool.query('UPDATE games SET achievements_count = $1 WHERE id = $2', [count, game.id]);
      }
      console.log(`[game_id=${game.id} rawg_id=${game.rawg_id}] ${game.name}: ${count ?? 'no count'}`);
      failsInARow = 0;
    } catch (err) {
      failed++;
      failsInARow++;
      console.warn(`[game_id=${game.id} rawg_id=${game.rawg_id}] ${game.name}: failed (${err.message})`);
    }
    await sleep(DELAY_MS);
  }

  console.log(`\nDone. count > 0: ${withCount}, count 0: ${zero}, no count: ${noCount}, failed: ${failed}`);
}

main()
  .catch(err => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
