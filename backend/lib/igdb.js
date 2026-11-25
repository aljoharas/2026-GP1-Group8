// IGDB lookups for enrichment (themes, game_modes, keywords, cover, summary,
// storyline). Used by saveGameToDB (routes/games.js) and
// scripts/backfill_igdb_enrichment.js, so both find games the same way.
//
// Games are found by, in order:
//   1. slug    — RAWG's slug, which is usually IGDB's too
//   2. name    — exact name (case-insensitive), main versions only
//   3. alt     — exact IGDB alternative name (IGDB renamed "Overwatch 2" to
//                "Overwatch" and keeps the old name there)
// RAWG and IGDB slugs often differ ("god-of-war-2" on RAWG is "god-of-war--1"
// on IGDB), which is why 2 and 3 exist. When several games share the name, the
// release year closest to RAWG's wins; with no year to compare, nothing is
// guessed.

// Credentials are read at call time: routes/games.js loads dotenv after its requires
// Alternative names are looser (abbreviations, old titles), so they need more:
// a name of at least this many characters, and a release year this close
const ALT_MIN_NAME_LENGTH = 4;
const ALT_MAX_YEAR_GAP = 2;
const FIELDS = 'slug,name,first_release_date,themes.name,game_modes.name,keywords.name,cover.url,summary,storyline';

// Twitch tokens last ~60 days so one fetch covers a long time
let _token = null;
let _tokenExpiry = 0;

async function getIGDBToken() {
  if (_token && Date.now() < _tokenExpiry) return _token;
  const resp = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${process.env.IGDB_CLIENT_ID}&client_secret=${process.env.IGDB_CLIENT_SECRET}&grant_type=client_credentials`,
    { method: 'POST' }
  );
  if (!resp.ok) throw new Error('IGDB auth failed');
  const data = await resp.json();
  _token = data.access_token;
  _tokenExpiry = Date.now() + (data.expires_in - 300) * 1000; // expire 5 min early
  return _token;
}

const MAX_ATTEMPTS = 3; // network resets, 429 and 5xx are retried after 1s, then 2s

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function igdbQuery(body) {
  for (let attempt = 1; ; attempt++) {
    let retryable;
    try {
      const token = await getIGDBToken();
      const resp = await fetch('https://api.igdb.com/v4/games', {
        method: 'POST',
        headers: { 'Client-ID': process.env.IGDB_CLIENT_ID, Authorization: `Bearer ${token}` },
        body,
      });
      if (resp.ok) return resp.json();
      retryable = new Error(`IGDB error ${resp.status}`);
      if (resp.status !== 429 && resp.status < 500) throw retryable;
    } catch (err) {
      // fetch throws a TypeError on network failures (ECONNRESET and the like)
      if (!(err instanceof TypeError) && err !== retryable) throw err;
      retryable = err;
    }
    if (attempt === MAX_ATTEMPTS) throw retryable;
    await sleep(1000 * 2 ** (attempt - 1));
  }
}

// A string literal for an IGDB query
function quote(text) {
  return `"${String(text).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

// "God of War (2018)" → { name: "God of War", year: 2018 }
function cleanName(name) {
  const match = /^(.*?)\s*\((\d{4})\)\s*$/.exec(name || '');
  return match ? { name: match[1], year: Number(match[2]) } : { name: (name || '').trim(), year: null };
}

function releaseYear(igdbGame) {
  return igdbGame.first_release_date ? new Date(igdbGame.first_release_date * 1000).getUTCFullYear() : null;
}

// One result is taken as is; several need a year, and the closest dated one wins
function pickByYear(results, year) {
  if (results.length === 1) return results[0];
  if (results.length === 0 || !year) return null;
  const dated = results.filter((g) => releaseYear(g) !== null);
  if (dated.length === 0) return null;
  return dated.reduce((best, g) => (Math.abs(releaseYear(g) - year) < Math.abs(releaseYear(best) - year) ? g : best));
}

// Drops games released more than ALT_MAX_YEAR_GAP years from `year`; games
// without a date, or any game when there's no year, are kept
function closeInYear(results, year) {
  if (!year) return results;
  return results.filter((g) => releaseYear(g) === null || Math.abs(releaseYear(g) - year) <= ALT_MAX_YEAR_GAP);
}

// IGDB game → the columns we store
function enrichmentFields(igdbGame) {
  const rawCoverUrl = igdbGame.cover?.url;
  return {
    themes: (igdbGame.themes || []).map((t) => t.name),
    gameModes: (igdbGame.game_modes || []).map((m) => m.name),
    keywords: (igdbGame.keywords || []).slice(0, 50).map((k) => k.name),
    // IGDB URLs start with // and use t_thumb; upgrade to https + t_cover_big
    coverImage: rawCoverUrl ? `https:${rawCoverUrl.replace('t_thumb', 't_cover_big')}` : null,
    summary: igdbGame.summary || null,
    storyline: igdbGame.storyline || null,
  };
}

// Batched step 1: { slug: igdbGame } for every slug IGDB knows (≤ 50 per call)
async function fetchBySlugs(slugs) {
  if (slugs.length === 0) return {};
  const results = await igdbQuery(`where slug = (${slugs.map(quote).join(',')}); fields ${FIELDS}; limit ${slugs.length};`);
  return Object.fromEntries(results.map((g) => [g.slug, g]));
}

// Steps 2 and 3 for one game. releasedAt is games.released_at (Date/string/null).
async function findByName(name, releasedAt) {
  const { name: clean, year: nameYear } = cleanName(name);
  if (!clean) return null;
  const year = nameYear || (releasedAt ? new Date(releasedAt).getUTCFullYear() : null);
  const byName = await igdbQuery(`where name ~ ${quote(clean)} & version_parent = null; fields ${FIELDS}; limit 10;`);
  const named = pickByYear(byName, year);
  if (named) return { game: named, method: 'name' };
  if (byName.length > 0) return null; // ambiguous: don't fall through to a looser match
  // "TA" or "PAD" as an alternative name matches unrelated games
  if (clean.length < ALT_MIN_NAME_LENGTH) return null;
  const byAlt = await igdbQuery(`where alternative_names.name ~ ${quote(clean)} & version_parent = null; fields ${FIELDS}; limit 10;`);
  const alt = pickByYear(closeInYear(byAlt, year), year);
  return alt ? { game: alt, method: 'alternative_name' } : null;
}

// All three steps for one game → { game, method } or null
async function findIGDBGame({ slug, name, releasedAt }) {
  if (slug) {
    const bySlug = await fetchBySlugs([slug]);
    if (bySlug[slug]) return { game: bySlug[slug], method: 'slug' };
  }
  return findByName(name, releasedAt);
}

module.exports = {
  getIGDBToken, igdbQuery, quote, cleanName, pickByYear, closeInYear, enrichmentFields,
  fetchBySlugs, findByName, findIGDBGame,
};
