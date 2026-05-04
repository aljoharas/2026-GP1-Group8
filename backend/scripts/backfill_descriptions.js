/**
 * Backfill summary + storyline for all games in the DB using IGDB.
 * Batches 50 slugs per request, ~3 req/sec to stay under IGDB's 4/sec limit.
 * Games with no IGDB match keep whatever RAWG description they already have.
 *
 * Run: node scripts/backfill_descriptions.js
 */

require('dotenv').config();
const pool = require('../db');

const IGDB_CLIENT_ID     = process.env.IGDB_CLIENT_ID;
const IGDB_CLIENT_SECRET = process.env.IGDB_CLIENT_SECRET;
const BATCH_SIZE         = 50;
const DELAY_MS           = 300;

// ── IGDB auth ────────────────────────────────────────────────────────────────

let _token = null;
let _tokenExpiry = 0;

async function getToken() {
  if (_token && Date.now() < _tokenExpiry) return _token;
  const resp = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${IGDB_CLIENT_ID}&client_secret=${IGDB_CLIENT_SECRET}&grant_type=client_credentials`,
    { method: 'POST' }
  );
  if (!resp.ok) throw new Error(`IGDB auth failed: ${resp.status}`);
  const data = await resp.json();
  _token = data.access_token;
  _tokenExpiry = Date.now() + (data.expires_in - 300) * 1000;
  return _token;
}

// ── IGDB fetch ────────────────────────────────────────────────────────────────

async function fetchDescriptionsForSlugs(slugs) {
  const token = await getToken();
  const slugList = slugs.map(s => `"${s}"`).join(',');
  const resp = await fetch('https://api.igdb.com/v4/games', {
    method: 'POST',
    headers: {
      'Client-ID': IGDB_CLIENT_ID,
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'text/plain',
    },
    body: `where slug = (${slugList}); fields slug,summary,storyline; limit ${slugs.length};`,
  });
  if (!resp.ok) throw new Error(`IGDB error: ${resp.status} ${await resp.text()}`);
  return resp.json();
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // Target games missing both summary and storyline (description from RAWG is fine to keep)
  const { rows: games } = await pool.query(
    `SELECT id, slug FROM games
     WHERE summary IS NULL AND storyline IS NULL AND slug IS NOT NULL
     ORDER BY id`
  );

  if (games.length === 0) {
    console.log('All games already have descriptions. Nothing to do.');
    return;
  }

  console.log(`Found ${games.length} games to enrich. Batching ${BATCH_SIZE} slugs per request...\n`);

  let updated = 0;
  let skipped = 0;

  for (let i = 0; i < games.length; i += BATCH_SIZE) {
    const batch = games.slice(i, i + BATCH_SIZE);

    process.stdout.write(`[${i + 1}–${Math.min(i + BATCH_SIZE, games.length)}/${games.length}] fetching IGDB...`);

    let igdbResults;
    try {
      igdbResults = await fetchDescriptionsForSlugs(batch.map(g => g.slug));
    } catch (err) {
      console.error(` ERROR: ${err.message} — skipping batch`);
      skipped += batch.length;
      await sleep(DELAY_MS);
      continue;
    }

    // slug → { summary, storyline }
    const dataMap = {};
    for (const entry of igdbResults) {
      if (entry.slug && (entry.summary || entry.storyline)) {
        dataMap[entry.slug] = {
          summary:   entry.summary   || null,
          storyline: entry.storyline || null,
        };
      }
    }

    let batchUpdated = 0;
    for (const game of batch) {
      const data = dataMap[game.slug];
      if (data) {
        await pool.query(
          `UPDATE games
           SET summary   = COALESCE($1, summary),
               storyline = COALESCE($2, storyline),
               updated_at = now()
           WHERE id = $3`,
          [data.summary, data.storyline, game.id]
        );
        batchUpdated++;
      }
    }

    const batchSkipped = batch.length - batchUpdated;
    updated += batchUpdated;
    skipped += batchSkipped;

    console.log(` ✓ ${batchUpdated} updated, ${batchSkipped} no IGDB match`);

    if (i + BATCH_SIZE < games.length) await sleep(DELAY_MS);
  }

  console.log(`\nDone. Updated: ${updated} | No IGDB text found: ${skipped}`);

  // Quick stats
  const { rows } = await pool.query(
    `SELECT COUNT(*) FILTER (WHERE summary IS NOT NULL) as has_summary,
            COUNT(*) FILTER (WHERE storyline IS NOT NULL) as has_storyline,
            COUNT(*) FILTER (WHERE summary IS NULL AND storyline IS NULL AND description IS NULL) as still_empty
     FROM games`
  );
  console.log(`DB state: ${rows[0].has_summary} with summary, ${rows[0].has_storyline} with storyline, ${rows[0].still_empty} still fully empty`);
}

main()
  .then(() => pool.end())
  .catch(err => {
    console.error('Fatal:', err.message);
    pool.end();
    process.exit(1);
  });
