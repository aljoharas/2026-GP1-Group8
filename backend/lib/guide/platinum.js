// platinum.js
//
// PlayStation's Platinum trophy ("earn every other trophy") has no Steam
// equivalent, so a Steam-sourced list never contains it. RAWG's list is
// PSN-derived and usually does, but it is labelled inconsistently:
//   - "Collect all trophies." / "Obtain all trophies."  (Witcher 3, RE4)
//   - the name repeated as the description               (RDR2: "Legend of the West")
//   - flavour text                                       (GTA V: "Congratulations! ...")
// So detection is best-effort: a clear match gives the real name and icon,
// otherwise the game gets a generic "Platinum" stop.
//
// Every game with achievements gets a Platinum, PlayStation or not: games
// that aren't on PlayStation (or whose lookup fails) get the generic one,
// earned the same way, by finishing every other achievement.
//
// Sources, in order: RAWG data already saved in the `achievements` table,
// then RAWG live, then (only if RAWG can't be reached) OpenAI.
//
// Both the trophy guide and the log checklist use getPlatinum(), so they
// always agree on the Platinum's name.

const OpenAI = require('openai');
const pool = require('../../db/index');
const { fetchAllRawgAchievements, fetchRawgGameDetail } = require('../achievements');
const { DEFAULT_MODEL } = require('./enrich');

// Part of GUIDE_VERSION and of the cached result, so bumping it recomputes both.
const PLATINUM_VERSION = 'plat-4';

// "platinum" alone is too loose: GTA Online has "Earn 25 platinum medals".
const ALL_TROPHIES_RE = /\b(all (the )?(other )?trophies|every (other )?trophy|platinum trophy)\b/i;
const PLATINUM_NAME_RE = /^\s*platinum( trophy)?\s*$/i;
const PLAYSTATION_RE = /playstation/i;

const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

function toPlatinum(a) {
  const description = (a.description || '').trim();
  const pct = a.percent != null ? parseFloat(a.percent) : null;
  return {
    name: (a.name || '').trim(),
    // A description that only repeats the name carries no information.
    description: description && norm(description) !== norm(a.name) ? description : null,
    image: a.image || null,
    rarity: Number.isFinite(pct) ? pct : null,
    generic: false,
  };
}

// Pure: picks the Platinum out of a raw RAWG achievement list, or null.
// guideNames are the names already in the resolved (Steam or RAWG) list.
function pickPlatinum(rawgList, guideNames = []) {
  const byRarity = (a, b) => (parseFloat(a.percent) || 0) - (parseFloat(b.percent) || 0);

  const explicit = rawgList.filter((a) => PLATINUM_NAME_RE.test(a.name || '') || ALL_TROPHIES_RE.test(a.description || ''));
  if (explicit.length > 0) return toPlatinum([...explicit].sort(byRarity)[0]);

  // Name-only entries that the resolved list doesn't have. Only trusted when
  // there is exactly one, so a stray PS-only trophy isn't mistaken for it.
  const inGuide = new Set(guideNames.map(norm));
  const nameOnly = rawgList.filter((a) => {
    if (inGuide.has(norm(a.name))) return false;
    const d = (a.description || '').trim();
    return !d || norm(d) === norm(a.name);
  });
  if (nameOnly.length === 1) return toPlatinum(nameOnly[0]);

  return null;
}

const GENERIC = { name: 'Platinum', description: null, image: null, rarity: null, generic: true };

// RAWG lists saved earlier by the old /achievements route, in the shape
// pickPlatinum expects. Lets detection work without a RAWG call.
async function savedRawgList(rawgId) {
  const { rows } = await pool.query(
    `SELECT a.display_name AS name, a.description, a.icon_url AS image, a.percent
       FROM achievements a JOIN games g ON g.id = a.game_id
      WHERE g.rawg_id = $1`,
    [rawgId]
  );
  return rows;
}

async function fromRawg(rawgId, guideNames) {
  const detail = await fetchRawgGameDetail(rawgId);
  const platforms = (detail.platforms || []).map((p) => p.platform?.name || '');
  if (!platforms.some((p) => PLAYSTATION_RE.test(p))) return null;

  const rawg = await fetchAllRawgAchievements(rawgId);
  return pickPlatinum(rawg, guideNames) || GENERIC;
}

const OPENAI_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['onPlayStation', 'platinumName', 'platinumDescription', 'confident'],
  properties: {
    onPlayStation: { type: 'boolean' },
    platinumName: { type: ['string', 'null'] },
    platinumDescription: { type: ['string', 'null'] },
    confident: { type: 'boolean' },
  },
};

const OPENAI_INSTRUCTIONS = `You identify PlayStation Platinum trophies.
Given a video game title, answer:
- onPlayStation: whether the game was released on PlayStation 3, 4 or 5 with a trophy list.
- platinumName: the exact English name of its Platinum trophy, or null if it has none.
- platinumDescription: that trophy's in-game description, or null.
- confident: true only if you are certain of the exact name. Never guess a name; if unsure, set confident to false.`;

let _client = null;
function openai() {
  if (!process.env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not set');
  if (!_client) _client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  return _client;
}

// Pure: turns the model's answer into a platinum (or null). An unconfident
// name, or one that is actually a regular (Steam) achievement, is not
// trusted: the game still gets a generic "Platinum" stop.
function platinumFromModel(answer, guideNames = []) {
  if (!answer || answer.onPlayStation !== true) return null;
  const name = (answer.platinumName || '').trim();
  const isRegular = new Set(guideNames.map(norm)).has(norm(name));
  if (!answer.confident || !name || isRegular) return GENERIC;
  const description = (answer.platinumDescription || '').trim();
  return { name, description: description || null, image: null, rarity: null, generic: false, source: 'openai' };
}

async function fromOpenAI(rawgId, guideNames) {
  const { rows } = await pool.query('SELECT name FROM games WHERE rawg_id = $1', [rawgId]);
  const title = rows[0]?.name;
  if (!title) throw new Error('game not found for OpenAI lookup');

  const response = await openai().responses.create({
    model: DEFAULT_MODEL,
    instructions: OPENAI_INSTRUCTIONS,
    input: `Game: ${title}`,
    temperature: 0,
    text: { format: { type: 'json_schema', name: 'platinum', strict: true, schema: OPENAI_SCHEMA } },
  });
  return platinumFromModel(JSON.parse(response.output_text), guideNames);
}

// Throws only if every source fails, so callers can tell "not a
// PlayStation game" (null) from "couldn't check".
async function lookupPlatinum(rawgId, guideNames, { logger = console } = {}) {
  // A Platinum found in the saved PSN-derived list is proof enough that the
  // game is on PlayStation, so no platform check (or RAWG call) is needed.
  const saved = pickPlatinum(await savedRawgList(rawgId), guideNames);
  if (saved) return saved;

  try {
    return await fromRawg(rawgId, guideNames);
  } catch (err) {
    logger.warn(`[guide] RAWG platinum lookup failed for rawg ${rawgId} (${err.message}); asking OpenAI`);
    return fromOpenAI(rawgId, guideNames);
  }
}

// resolved: result of getGameAchievements(). The answer is cached on the
// game_achievements row; a failed lookup is not cached, so it is retried.
// Never throws: a failure just means the generic Platinum for this request.
// Only a game with no achievements gets null.
async function getPlatinum(resolved, { logger = console } = {}) {
  if (!resolved.achievements || resolved.achievements.length === 0) return null;
  if (resolved.platinumVersion === PLATINUM_VERSION) return resolved.platinum || GENERIC;

  const rawgId = resolved.gameId;
  if (!rawgId) return GENERIC;

  let platinum;
  try {
    platinum = (await lookupPlatinum(rawgId, resolved.achievements.map((a) => a.name), { logger })) || GENERIC;
  } catch (err) {
    logger.warn(`[guide] platinum lookup failed for rawg ${rawgId}: ${err.message}`);
    return GENERIC;
  }

  try {
    await pool.query(
      `UPDATE game_achievements
          SET payload = payload || jsonb_build_object('platinum', $2::jsonb, 'platinumVersion', $3::text)
        WHERE game_id = (SELECT id FROM games WHERE rawg_id = $1)`,
      [rawgId, JSON.stringify(platinum), PLATINUM_VERSION]
    );
  } catch (err) {
    logger.warn(`[guide] could not cache platinum for rawg ${rawgId}: ${err.message}`);
  }
  return platinum;
}

module.exports = { getPlatinum, pickPlatinum, platinumFromModel, PLATINUM_VERSION };
