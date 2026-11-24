// Survey game lookup outside the app's games table, with the app's own sources:
// RAWG search (as routes/games.js /search) for the title and genres, then the app's IGDB
// lookup (lib/igdb findIGDBGame) for game_modes. Read-only: nothing is saved to the database.
//
//   node notebooks/survey_validation/lookup_games.js IN.json OUT.json
// IN: [{ "title", "slug"?, "released"?, "need": "rawg+igdb" | "rawg-slug+igdb" | "igdb" }]
// OUT: same list with rawg_name, rawg_slug, rawg_id, released, genres, rawg_exact, igdb_name,
//      igdb_method, game_modes, error

const path = require('path');
const fs = require('fs');
const BACKEND = path.resolve(__dirname, '..', '..', 'backend');
require(path.join(BACKEND, 'node_modules', 'dotenv')).config({ path: path.join(BACKEND, '.env') });
const { findIGDBGame, enrichmentFields } = require(path.join(BACKEND, 'lib', 'igdb'));

const RAWG = 'https://api.rawg.io/api';
const key = (s) => String(s || '').normalize('NFKD').toLowerCase().replace(/[^a-z0-9]/g, '');

async function rawgSearch(title) {
  const url = `${RAWG}/games?search=${encodeURIComponent(title)}&page_size=10&key=${process.env.RAWG_API_KEY}`;
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`RAWG ${resp.status}`);
  const { results = [] } = await resp.json();
  const exact = results.filter((g) => key(g.name) === key(title));
  // Several exact names (remakes): the most-rated one
  exact.sort((a, b) => (b.ratings_count || 0) - (a.ratings_count || 0));
  const pick = exact[0] || results[0];
  return pick ? { game: pick, exact: exact.length > 0 } : null;
}

async function main() {
  const [inPath, outPath] = process.argv.slice(2);
  const items = JSON.parse(fs.readFileSync(inPath, 'utf8'));
  const out = [];
  for (const item of items) {
    const row = { ...item };
    try {
      let slug = item.slug;
      let name = item.title;
      let released = item.released || null;
      if (item.need === 'rawg-slug+igdb') {
        const resp = await fetch(`${RAWG}/games/${item.slug}?key=${process.env.RAWG_API_KEY}`);
        if (!resp.ok) throw new Error(`RAWG ${resp.status}`);
        const g = await resp.json();
        Object.assign(row, {
          rawg_name: g.name, rawg_slug: g.slug, rawg_id: g.id, released: g.released,
          genres: (g.genres || []).map((x) => x.name), rawg_exact: true,
        });
        ({ slug, name } = { slug: g.slug, name: g.name });
        released = g.released;
      }
      if (item.need === 'rawg+igdb') {
        const found = await rawgSearch(item.title);
        if (found) {
          const g = found.game;
          Object.assign(row, {
            rawg_name: g.name, rawg_slug: g.slug, rawg_id: g.id, released: g.released,
            genres: (g.genres || []).map((x) => x.name), rawg_exact: found.exact,
          });
          ({ slug, name } = { slug: g.slug, name: g.name });
          released = g.released;
        }
      }
      // An IGDB slug override: the RAWG slug doesn't exist on IGDB, so look up by IGDB's own slug
      const igdb = await findIGDBGame({ slug: item.igdb_slug || slug, name, releasedAt: released });
      if (igdb) {
        row.igdb_name = igdb.game.name;
        row.igdb_method = igdb.method;
        row.game_modes = enrichmentFields(igdb.game).gameModes;
      }
    } catch (err) {
      row.error = err.message;
    }
    out.push(row);
    await new Promise((r) => setTimeout(r, 300)); // gentle on both APIs
  }
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log(`looked up ${out.length}; errors: ${out.filter((r) => r.error).length}`);
}

main();
