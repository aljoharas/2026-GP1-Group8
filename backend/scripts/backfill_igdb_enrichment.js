/**
 * Re-run IGDB enrichment for every game with NULL or empty game_modes.
 *
 * Why games were missed: most were bulk-inserted without going through
 * saveGameToDB, so enrichment never ran; others went through it but RAWG's
 * slug isn't IGDB's ("god-of-war-2" vs "god-of-war--1"), and games that had
 * themes but no modes were skipped as "already enriched". lib/igdb now falls
 * back to the exact name and IGDB's alternative names.
 *
 * Fills only what is empty: game_modes, themes and keywords when NULL/empty,
 * cover_image, summary and storyline when NULL. Nothing is overwritten.
 * Slugs go 50 per IGDB request, then a name lookup per game left; ~3 req/s,
 * under IGDB's 4/s limit. Safe to re-run.
 *
 * Run: node scripts/backfill_igdb_enrichment.js [--dry-run]
 *   --dry-run  look up and report, write nothing
 */

require('dotenv').config();
const pool = require('../db');
const { fetchBySlugs, findByName, enrichmentFields } = require('../lib/igdb');

const BATCH_SIZE = 50;
const DELAY_MS = 300;
const DRY_RUN = process.argv.includes('--dry-run');

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function save(game, found) {
  const f = enrichmentFields(found.game);
  if (DRY_RUN) return f;
  await pool.query(
    `UPDATE games SET
       game_modes  = CASE WHEN game_modes IS NULL OR cardinality(game_modes) = 0 THEN $1 ELSE game_modes END,
       themes      = CASE WHEN themes     IS NULL OR cardinality(themes)     = 0 THEN $2 ELSE themes END,
       keywords    = CASE WHEN keywords   IS NULL OR cardinality(keywords)   = 0 THEN $3 ELSE keywords END,
       cover_image = COALESCE(cover_image, $4),
       summary     = COALESCE(summary, $5),
       storyline   = COALESCE(storyline, $6),
       updated_at  = now()
     WHERE id = $7`,
    [f.gameModes, f.themes, f.keywords, f.coverImage, f.summary, f.storyline, game.id]
  );
  return f;
}

async function main() {
  const { rows: games } = await pool.query(`
    SELECT g.id, g.name, g.slug, g.released_at,
           EXISTS (
             SELECT 1 FROM library_entries le
             WHERE le.game_id = g.id AND le.source = 'manual'
           ) AS in_manual_logs
    FROM games g
    WHERE (g.game_modes IS NULL OR cardinality(g.game_modes) = 0)
      AND (g.slug IS NOT NULL OR g.name IS NOT NULL)
    ORDER BY in_manual_logs DESC, g.id
  `);
  console.log(`${games.length} games without game_modes${DRY_RUN ? ' (dry run)' : ''}\n`);

  const results = []; // { game, method, modes }

  // 1. Slugs, batched
  const bySlug = {};
  const slugged = games.filter(g => g.slug);
  for (let i = 0; i < slugged.length; i += BATCH_SIZE) {
    try {
      Object.assign(bySlug, await fetchBySlugs(slugged.slice(i, i + BATCH_SIZE).map(g => g.slug)));
    } catch (err) {
      // Those games still get the name lookups below
      console.warn(`slug batch ${i / BATCH_SIZE + 1} failed (${err.message})`);
    }
    await sleep(DELAY_MS);
  }

  // 2–3. Exact name, then alternative name, for games the slug missed
  for (const game of games) {
    let found = bySlug[game.slug] ? { game: bySlug[game.slug], method: 'slug' } : null;
    if (!found) {
      try {
        found = await findByName(game.name, game.released_at);
      } catch (err) {
        console.warn(`[game_id=${game.id}] ${game.name}: lookup failed (${err.message})`);
      }
      await sleep(DELAY_MS * 2); // up to two requests
    }
    const fields = found ? await save(game, found) : null;
    const modes = fields ? fields.gameModes : [];
    results.push({ game, method: found ? found.method : 'no_match', modes });
    console.log(`[game_id=${game.id}] ${game.name}: ${found ? `${found.method} → ${found.game.slug}` : 'no match'}`
      + `${modes.length ? ` [${modes.join(', ')}]` : found ? ' (IGDB has no modes)' : ''}`);
  }

  const count = (pred) => results.filter(pred).length;
  console.log('\nSummary');
  console.log(`  matched by slug:             ${count(r => r.method === 'slug')}`);
  console.log(`  matched by name:             ${count(r => r.method === 'name')}`);
  console.log(`  matched by alternative name: ${count(r => r.method === 'alternative_name')}`);
  console.log(`  no match:                    ${count(r => r.method === 'no_match')}`);
  console.log(`  got game_modes:              ${count(r => r.modes.length > 0)}`);
  console.log(`  still without game_modes:    ${count(r => r.modes.length === 0)}`);
  console.log('\nGames in manual logs:');
  for (const r of results.filter(x => x.game.in_manual_logs)) {
    console.log(`  ${r.game.name}: ${r.modes.length ? r.modes.join(', ') : `none (${r.method})`}`);
  }
}

main()
  .catch(err => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
