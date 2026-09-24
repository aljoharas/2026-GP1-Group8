// Resolves achievements for a game from exactly one source: Steam first,
// RAWG as fallback. Never merge the two for the same title -- they use
// different schemas and incompatible rarity bases (Steam = % of owners,
// RAWG = PSN-derived).
//
// Resolution order, per an audit of 20 games (RAWG silently truncates
// achievement lists for some titles with no signal to detect it; Steam was
// equal or better everywhere both had data):
//   1. Find the Steam appid via RAWG's /games/{id}/stores (store_id 1).
//   2. If an appid exists, Steam is authoritative -- including a real
//      zero-achievement result (e.g. Undertale). Do not fall back to RAWG.
//   3. If Steam errors out (not a confirmed empty list) or there's no appid,
//      fall back to RAWG, gated for suspected truncation.
//
// See db/migrations/008_game_achievements.sql for the cache table this
// backs, and scripts/verify_achievements.js for a CLI to spot-check output.

const pool = require('../db/index');
require('dotenv').config();

const RAWG_KEY = process.env.RAWG_API_KEY;
const RAWG_BASE = 'https://api.rawg.io/api';
const STEAM_KEY = process.env.STEAM_API_KEY;
const STEAM_BASE = 'https://api.steampowered.com';
const STEAM_STORE_ID = 1; // RAWG's numeric id for the Steam storefront in /stores

const FRAGMENT_PATTERN = /\b(all trophies|all achievements|platinum|100%)\b/i;
const NINTENDO_PLATFORM_RE = /nintendo/i;

// ── low-level fetchers ──────────────────────────────────────────────────────

async function fetchRawgJson(pathAndQuery) {
  const sep = pathAndQuery.includes('?') ? '&' : '?';
  const url = `${RAWG_BASE}${pathAndQuery}${sep}key=${RAWG_KEY}`;
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`RAWG ${pathAndQuery} -> ${resp.status}`);
  return resp.json();
}

async function fetchRawgGameDetail(rawgId) {
  return fetchRawgJson(`/games/${rawgId}`);
}

async function fetchRawgStores(rawgId) {
  return fetchRawgJson(`/games/${rawgId}/stores`);
}

async function fetchAllRawgAchievements(rawgId) {
  let all = [];
  let url = `${RAWG_BASE}/games/${rawgId}/achievements?page_size=40&key=${RAWG_KEY}`;
  while (url && all.length < 200) {
    const resp = await fetch(url);
    if (!resp.ok) break;
    const data = await resp.json();
    all = all.concat(data.results || []);
    url = data.next || null;
  }
  return all;
}

// Extracts the Steam appid from RAWG's stores endpoint. Worked for 16/16
// games in the audit -- preferred over name matching against the Steam store.
async function fetchSteamAppId(rawgId) {
  const stores = await fetchRawgStores(rawgId);
  const steamEntry = (stores?.results || []).find((s) => s.store_id === STEAM_STORE_ID);
  if (!steamEntry?.url) return null;
  const match = steamEntry.url.match(/\/app\/(\d+)/);
  return match ? match[1] : null;
}

// GetSchemaForGame is the membership source of truth -- the percentages
// endpoint below invents "ghost" achievements at 0% that aren't in the real
// list, so it's only ever used to attach rarity, never to decide what exists.
async function fetchSteamSchema(appid) {
  if (!STEAM_KEY) throw new Error('STEAM_API_KEY not configured');
  const url = `${STEAM_BASE}/ISteamUserStats/GetSchemaForGame/v2/?key=${STEAM_KEY}&appid=${appid}`;
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`Steam schema for appid ${appid} -> ${resp.status}`);
  const data = await resp.json();
  return data?.game?.availableGameStats?.achievements || [];
}

// Rarity is best-effort: a failure here should never block the achievement
// list itself, so callers get an empty map rather than a thrown error.
async function fetchSteamGlobalPercentages(appid) {
  const url = `${STEAM_BASE}/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid=${appid}`;
  try {
    const resp = await fetch(url);
    if (!resp.ok) return new Map();
    const data = await resp.json();
    const list = data?.achievementpercentages?.achievements || [];
    const map = new Map();
    for (const a of list) {
      const pct = parseFloat(a.percent); // percent is a string on this endpoint too
      if (Number.isFinite(pct)) map.set(a.name, pct);
    }
    return map;
  } catch {
    return new Map();
  }
}

async function isNintendoOnlyPlatform(rawgId) {
  try {
    const detail = await fetchRawgGameDetail(rawgId);
    const platforms = (detail.platforms || [])
      .map((p) => p.platform?.name)
      .filter(Boolean);
    if (platforms.length === 0) return false;
    return platforms.every((name) => NINTENDO_PLATFORM_RE.test(name));
  } catch (err) {
    console.warn(`[achievements] platform lookup failed for rawg ${rawgId}: ${err.message}`);
    return false;
  }
}

// ── normalization ────────────────────────────────────────────────────────

function normalizeNameForDedupe(name) {
  return (name || '')
    .toLowerCase()
    .replace(/\p{P}/gu, '') // strips punctuation, including the unicode ellipsis char
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeSteamAchievements(schemaAchievements, percentMap) {
  return schemaAchievements.map((a) => {
    const pct = percentMap.get(a.name);
    return {
      externalId: a.name,
      // Developer's internal key (DLC1_, EP2_, MP_, COOP_ ...). Kept separate
      // from `name` (the display name) so the trophy guide can classify on it.
      internalKey: a.name,
      name: a.displayName || a.name,
      description: a.description || '',
      iconUrl: a.icon || null,
      rarityPercent: Number.isFinite(pct) ? pct : null,
      hidden: a.hidden === 1, // preserved as-is, never inferred from a missing description
      source: 'steam',
    };
  });
}

function normalizeRawgAchievements(results) {
  const byKey = new Map(); // normalized name -> achievement, first occurrence wins
  for (const a of results) {
    const key = normalizeNameForDedupe(a.name);
    if (byKey.has(key)) continue;

    const pct = a.percent != null ? parseFloat(a.percent) : null;
    const name = (a.name || '').trim();
    const descRaw = (a.description || '').trim();
    // RAWG sometimes repeats the name as the description ("Legend of the
    // West -- Legend of the West") -- that's not real text, treat as empty.
    const description = descRaw && descRaw.toLowerCase() !== name.toLowerCase() ? descRaw : '';

    byKey.set(key, {
      externalId: String(a.id),
      internalKey: null, // RAWG has no developer key
      name,
      description,
      iconUrl: a.image || null,
      rarityPercent: Number.isFinite(pct) ? pct : null,
      hidden: false, // RAWG exposes no hidden/secret flag
      source: 'rawg',
    });
  }
  return Array.from(byKey.values());
}

function isSuspectedIncomplete(achievements) {
  if (achievements.length >= 20) return false;
  return achievements.some(
    (a) => FRAGMENT_PATTERN.test(a.name) || FRAGMENT_PATTERN.test(a.description)
  );
}

function summarize(achievements) {
  return {
    total: achievements.length,
    withDescription: achievements.filter((a) => a.description).length,
  };
}

// ── RAWG title disambiguation ───────────────────────────────────────────────

// RAWG's plain `search` can return several entries for the same title (e.g.
// two "God of War Ragnarok" rows, one real and one a near-empty duplicate)
// and picks whichever comes first by luck. This resolves deterministically:
// prefer the entry with a Steam store link, then the one with more
// achievements, and logs when alternates existed.
async function resolveRawgGameId(query) {
  const data = await fetchRawgJson(`/games?search=${encodeURIComponent(query)}&page_size=10`);
  const results = data.results || [];
  if (results.length === 0) return { rawgId: null, alternates: [] };

  const topKey = normalizeNameForDedupe(results[0].name);
  const sameTitle = results.filter((r) => normalizeNameForDedupe(r.name) === topKey);

  if (sameTitle.length === 1) {
    return { rawgId: sameTitle[0].id, alternates: [] };
  }

  const enriched = await Promise.all(
    sameTitle.map(async (c) => {
      const [appid, achievements] = await Promise.all([
        fetchSteamAppId(c.id).catch(() => null),
        fetchAllRawgAchievements(c.id).catch(() => []),
      ]);
      return { id: c.id, name: c.name, hasSteam: !!appid, achievementCount: achievements.length };
    })
  );

  enriched.sort((a, b) => {
    if (a.hasSteam !== b.hasSteam) return a.hasSteam ? -1 : 1;
    return b.achievementCount - a.achievementCount;
  });

  const [chosen, ...alternates] = enriched;
  console.warn(
    `[achievements] ambiguous RAWG title "${results[0].name}": chose id=${chosen.id} ` +
      `(steam=${chosen.hasSteam}, achievements=${chosen.achievementCount}); alternates: ` +
      (alternates.length
        ? alternates.map((a) => `id=${a.id} (steam=${a.hasSteam}, achievements=${a.achievementCount})`).join(', ')
        : 'none')
  );

  return { rawgId: chosen.id, alternates };
}

// ── resolution ───────────────────────────────────────────────────────────

async function resolveFromRawg(rawgId, appidTried) {
  const raw = await fetchAllRawgAchievements(rawgId);

  if (raw.length === 0) {
    const nintendoOnly = await isNintendoOnlyPlatform(rawgId);
    return {
      gameId: rawgId,
      source: 'rawg',
      appid: appidTried,
      achievements: [],
      total: 0,
      withDescription: 0,
      suspectedIncomplete: false,
      availability: nintendoOnly ? 'unsupported_platform' : 'no_data',
    };
  }

  const achievements = normalizeRawgAchievements(raw);
  const { total, withDescription } = summarize(achievements);
  return {
    gameId: rawgId,
    source: 'rawg',
    appid: appidTried,
    achievements,
    total,
    withDescription,
    suspectedIncomplete: isSuspectedIncomplete(achievements),
    availability: 'available',
  };
}

// Computes the normalized achievement result for a game. Pure -- does not
// read or write the cache table; see getGameAchievements for the cached path.
async function resolveAchievements(rawgId) {
  let appid = null;
  try {
    appid = await fetchSteamAppId(rawgId);
  } catch (err) {
    console.warn(`[achievements] stores lookup failed for rawg ${rawgId}: ${err.message}`);
  }

  if (!appid) {
    return resolveFromRawg(rawgId, null);
  }

  let schema;
  try {
    schema = await fetchSteamSchema(appid);
  } catch (err) {
    // A Steam error is inconclusive, not a confirmed empty list -- only an
    // actual zero-length schema is authoritative for `none`. Fall back to
    // RAWG rather than reporting availability we don't actually know.
    console.warn(`[achievements] steam schema failed for appid ${appid}: ${err.message}`);
    return resolveFromRawg(rawgId, appid);
  }

  if (schema.length === 0) {
    return {
      gameId: rawgId,
      source: 'steam',
      appid,
      achievements: [],
      total: 0,
      withDescription: 0,
      suspectedIncomplete: false,
      availability: 'none',
    };
  }

  const percentMap = await fetchSteamGlobalPercentages(appid);
  const achievements = normalizeSteamAchievements(schema, percentMap);
  const { total, withDescription } = summarize(achievements);
  return {
    gameId: rawgId,
    source: 'steam',
    appid,
    achievements,
    total,
    withDescription,
    suspectedIncomplete: false,
    availability: 'available',
  };
}

// ── cache ────────────────────────────────────────────────────────────────

// Resolves achievements for a game, reading/writing the game_achievements
// cache. rawgId is RAWG's id; caching only happens when the game already has
// a row in `games` (needed for the foreign key) -- a game not yet saved
// locally still resolves correctly, it just isn't persisted.
async function getGameAchievements(rawgId, { forceRefresh = false } = {}) {
  const gameRow = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [rawgId]);
  const gameId = gameRow.rows[0]?.id || null;

  if (gameId && !forceRefresh) {
    const cached = await pool.query(
      `SELECT source, payload, availability, fetched_at
       FROM game_achievements WHERE game_id = $1`,
      [gameId]
    );
    if (cached.rows.length > 0) {
      const row = cached.rows[0];
      return { ...row.payload, cached: true, fetchedAt: row.fetched_at };
    }
  }

  const result = await resolveAchievements(rawgId);

  if (gameId) {
    await pool.query(
      `INSERT INTO game_achievements (game_id, source, payload, availability, fetched_at)
       VALUES ($1, $2, $3::jsonb, $4, now())
       ON CONFLICT (game_id) DO UPDATE
         SET source = EXCLUDED.source, payload = EXCLUDED.payload,
             availability = EXCLUDED.availability, fetched_at = now()`,
      [gameId, result.source, JSON.stringify(result), result.availability]
    );
  }

  return { ...result, cached: false, fetchedAt: null };
}

module.exports = {
  resolveAchievements,
  getGameAchievements,
  resolveRawgGameId,
  // exported for the verification CLI and tests
  normalizeNameForDedupe,
  fetchSteamAppId,
  fetchAllRawgAchievements,
};
