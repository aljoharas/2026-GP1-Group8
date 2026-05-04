/**
 * Backfill cover_image for all games in the DB using IGDB.
 * Batches 50 slugs per IGDB request, ~4 req/sec to respect rate limits.
 * Games with no IGDB match keep their background_image as the UI fallback.
 *
 * Run: node scripts/backfill_cover_images.js
 */

require('dotenv').config();
const pool = require('../db');

const IGDB_CLIENT_ID     = process.env.IGDB_CLIENT_ID;
const IGDB_CLIENT_SECRET = process.env.IGDB_CLIENT_SECRET;
const BATCH_SIZE         = 50;   // slugs per IGDB request
const DELAY_MS           = 300;  // ~3.3 req/sec, comfortably under the 4/sec limit

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

// ── IGDB cover fetch ─────────────────────────────────────────────────────────

async function fetchCoversForSlugs(slugs) {
  const token = await getToken();
  const slugList = slugs.map(s => `"${s}"`).join(',');
  const resp = await fetch('https://api.igdb.com/v4/games', {
    method: 'POST',
    headers: {
      'Client-ID': IGDB_CLIENT_ID,
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'text/plain',
    },
    body: `where slug = (${slugList}); fields slug,cover.url; limit ${slugs.length};`,
  });
  if (!resp.ok) throw new Error(`IGDB error: ${resp.status} ${await resp.text()}`);
  return resp.json(); // [{ slug, cover: { url } }]
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function igdbUrlToCoverBig(rawUrl) {
  // rawUrl looks like: //images.igdb.com/igdb/image/upload/t_thumb/co1wyy.jpg
  return `https:${rawUrl.replace('t_thumb', 't_cover_big')}`;
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // Fetch games that still need a cover (slug required for IGDB lookup)
  const { rows: games } = await pool.query(
    `SELECT id, slug FROM games WHERE cover_image IS NULL AND slug IS NOT NULL ORDER BY id`
  );

  if (games.length === 0) {
    console.log('All games already have cover images. Nothing to do.');
    return;
  }

  console.log(`Found ${games.length} games to enrich. Batching ${BATCH_SIZE} slugs per request...\n`);

  let updated = 0;
  let skipped = 0; // no IGDB match or no cover on IGDB

  for (let i = 0; i < games.length; i += BATCH_SIZE) {
    const batch = games.slice(i, i + BATCH_SIZE);
    const slugMap = Object.fromEntries(batch.map(g => [g.slug, g.id]));

    process.stdout.write(`[${i + 1}–${Math.min(i + BATCH_SIZE, games.length)}/${games.length}] fetching IGDB...`);

    let igdbResults;
    try {
      igdbResults = await fetchCoversForSlugs(batch.map(g => g.slug));
    } catch (err) {
      console.error(` ERROR: ${err.message} — skipping batch`);
      skipped += batch.length;
      await sleep(DELAY_MS);
      continue;
    }

    // Build slug→coverUrl map from IGDB response
    const coverMap = {};
    for (const entry of igdbResults) {
      if (entry.slug && entry.cover?.url) {
        coverMap[entry.slug] = igdbUrlToCoverBig(entry.cover.url);
      }
    }

    // Update each game that got a cover
    let batchUpdated = 0;
    for (const game of batch) {
      const coverUrl = coverMap[game.slug];
      if (coverUrl) {
        await pool.query(
          'UPDATE games SET cover_image = $1, updated_at = now() WHERE id = $2',
          [coverUrl, game.id]
        );
        batchUpdated++;
      }
    }

    const batchSkipped = batch.length - batchUpdated;
    updated += batchUpdated;
    skipped += batchSkipped;

    console.log(` ✓ ${batchUpdated} updated, ${batchSkipped} no IGDB cover`);

    if (i + BATCH_SIZE < games.length) await sleep(DELAY_MS);
  }

  console.log(`\nDone. Updated: ${updated} | No cover found (fallback to background_image): ${skipped}`);
}

main()
  .then(() => pool.end())
  .catch(err => {
    console.error('Fatal:', err.message);
    pool.end();
    process.exit(1);
  });
