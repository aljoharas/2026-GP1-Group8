// achievementGuide.js
//
// Trophy guide generation. Ordering is deterministic code (lib/guide/*); the
// LLM only enriches individual trophies afterwards and cannot affect
// sequence. The previous LLM-ordering implementation is preserved in
// achievementGuideLegacy.js (unused).

const OpenAI = require('openai');
const pool = require('../db/index');
const { buildDeterministicGuide, applyEnrichment, ALGO_VERSION } = require('./guide');
const { enrichTrophies, PROMPT_VERSION, DEFAULT_MODEL } = require('./guide/enrich');
const { loadOverrides } = require('./guide/overrides');
const { enrichWithCache } = require('./guide/enrichCache');
const { formatLadderLog } = require('./guide/ladders');
const { getGameAchievements } = require('./achievements');

// Stored with every guide; a cached guide from another version is regenerated.
const GUIDE_VERSION = `${ALGO_VERSION}/${PROMPT_VERSION}`;

let _client = null;
function getClient() {
  if (!_client) {
    if (!process.env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not set');
    _client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return _client;
}

// Manual overrides + schema-order flag. (There is deliberately no store-`dlc`
// gate: see the KNOWN LIMITATION note in guide/classify.js.)
//
// A failed override load is NOT swallowed: it is logged as an error and
// recorded (overridesError) so it lands in the stored guide's meta.
async function gatherContext(resolved, { logger = console } = {}) {
  const appid = resolved.appid;
  // Only Steam's schema is in "date added" order, which the rarity-cliff signal relies on.
  const schemaOrdered = resolved.source === 'steam';
  if (!appid) return { overrides: new Map(), overridesError: null, schemaOrdered };
  let overrides = new Map();
  let overridesError = null;
  try {
    overrides = await loadOverrides(pool, appid);
  } catch (err) {
    overridesError = err.message;
    logger.error(`[guide] OVERRIDES NOT APPLIED for appid ${appid}: ${err.message}`);
  }
  return { overrides, overridesError, schemaOrdered };
}

function logGuide(logger, label, guide) {
  const { ladders, contradictions, classification } = guide.logs;
  logger.log(`[guide] ${label}: ${guide.nodes.length} entries`);
  logger.log(`[guide] ${label}: ${ladders.length} ladder log entr${ladders.length === 1 ? 'y' : 'ies'}`);
  for (const entry of ladders) logger.log(`[guide][ladder] ${formatLadderLog(entry)}`);
  for (const c of contradictions) {
    logger.log(
      `[guide][contradiction] ladder "${c.ladder}": tier ${c.higher} (${c.higherRarity}%) more common than ` +
        `${c.lower} (${c.lowerRarity}%) -- ${c.resolution}`
    );
  }
  for (const c of classification) {
    logger.log(
      `[guide][classify] ${c.name} (${c.key || 'no key'}) -> ${c.category} via ${c.decidedBy}` +
        ` signals=[${c.signals.join(',')}]`
    );
  }
}

// Enrichment cache: rows are per (game, trophy, ENRICH version). An ordering
// (ALGO_VERSION) bump reuses them all; an enrichment (PROMPT_VERSION) bump
// misses them all. No gameId => no cache.
async function loadEnrichment(gameId) {
  if (!gameId) return new Map();
  const res = await pool.query(
    `SELECT trophy_id, input_hash, steps, category_vote, confidence
     FROM achievement_enrichment WHERE game_id = $1 AND enrich_version = $2`,
    [gameId, PROMPT_VERSION]
  );
  return new Map(res.rows.map((r) => [r.trophy_id, r]));
}

async function saveEnrichment(gameId, rows) {
  if (!gameId || rows.length === 0) return;
  const payload = rows.map((r) => ({
    trophy_id: r.trophyId,
    input_hash: r.hash,
    steps: r.value.steps,
    category_vote: r.value.categoryVote,
    confidence: r.value.confidence,
  }));
  await pool.query(
    `INSERT INTO achievement_enrichment (game_id, trophy_id, enrich_version, input_hash, steps, category_vote, confidence, model)
     SELECT $1, r.trophy_id, $2, r.input_hash, r.steps, r.category_vote, r.confidence, $3
     FROM jsonb_to_recordset($4::jsonb) AS r(trophy_id text, input_hash text, steps jsonb, category_vote text, confidence text)
     ON CONFLICT (game_id, trophy_id, enrich_version) DO UPDATE
       SET input_hash = EXCLUDED.input_hash, steps = EXCLUDED.steps, category_vote = EXCLUDED.category_vote,
           confidence = EXCLUDED.confidence, model = EXCLUDED.model, created_at = now()`,
    [gameId, PROMPT_VERSION, DEFAULT_MODEL, JSON.stringify(payload)]
  );
}

// resolved: result of getGameAchievements() (source, appid, achievements).
async function generateAchievementGuide(resolved, { skipLLM = false, logger = console, label = 'game', gameId = null } = {}) {
  const ctx = await gatherContext(resolved, { logger });
  const deterministic = buildDeterministicGuide(resolved.achievements, ctx);
  logGuide(logger, label, deterministic);

  let guide = deterministic;
  const meta = {
    algoVersion: ALGO_VERSION,
    promptVersion: PROMPT_VERSION,
    guideVersion: GUIDE_VERSION,
    model: null,
    source: resolved.source,
    appid: resolved.appid || null,
    phases: deterministic.phases,
    logs: deterministic.logs,
    overrides: { count: ctx.overrides.size, error: ctx.overridesError },
    enrichment: { status: 'skipped' },
  };

  if (!skipLLM) {
    const trophies = deterministic.nodes.flatMap((n) =>
      n.kind === 'ladder' ? n.tiers.flatMap((t) => t.trophies) : [n]
    ).map((t) => ({ id: t.id, name: t.name, description: t.description }));
    try {
      const result = await enrichWithCache({
        trophies,
        logger,
        load: () => loadEnrichment(gameId),
        save: (rows) => saveEnrichment(gameId, rows),
        enrich: (missing) => enrichTrophies(getClient(), missing, { model: DEFAULT_MODEL }),
      });
      guide = applyEnrichment(deterministic, result.byId);
      meta.model = DEFAULT_MODEL;
      meta.enrichment = {
        status: result.errors.length ? 'partial' : 'ok',
        version: PROMPT_VERSION,
        total: trophies.length,
        reused: result.reused,
        requested: result.requested,
        apiCalls: result.apiCalls,
        errors: result.errors,
        ignoredFields: result.ignoredKeys,
      };
      logger.log(`[guide] enrichment ${PROMPT_VERSION}: ${result.reused} reused, ${result.requested} sent to the LLM (${result.apiCalls} API call(s))`);
      if (result.ignoredKeys.length) {
        logger.warn(`[guide] ignored non-enrichment fields from LLM: ${result.ignoredKeys.join(', ')}`);
      }
    } catch (err) {
      logger.warn(`[guide] enrichment failed, serving deterministic guide only: ${err.message}`);
      meta.enrichment = { status: 'failed', errors: [err.message] };
    }
  }

  return { nodes: guide.nodes, phases: guide.phases, meta };
}

// Full request flow shared by the route and the CLI: serve a current-version
// cached guide, otherwise resolve achievements, generate and persist.
// Returns { statusCode, body }.
async function getOrCreateGuide(rawgId, { forceRefresh = false, skipLLM = false, logger = console } = {}) {
  const gameRow = await pool.query('SELECT id, name FROM games WHERE rawg_id = $1', [rawgId]);
  const game = gameRow.rows[0];
  if (!game) return { statusCode: 404, body: { message: 'Game not found' } };

  if (!forceRefresh) {
    const cached = await pool.query(
      'SELECT nodes, meta, model, prompt_version, generated_at FROM achievement_guides WHERE game_id = $1',
      [game.id]
    );
    const row = cached.rows[0];
    if (row && row.prompt_version === GUIDE_VERSION) {
      return {
        statusCode: 200,
        body: {
          nodes: row.nodes,
          phases: row.meta?.phases || [],
          model: row.model,
          promptVersion: row.prompt_version,
          generatedAt: row.generated_at,
          cached: true,
        },
      };
    }
  }

  const resolved = await getGameAchievements(rawgId);
  if (resolved.availability !== 'available' || resolved.achievements.length === 0) {
    return { statusCode: 400, body: { message: 'No achievements available for this game' } };
  }

  const guide = await generateAchievementGuide(resolved, { skipLLM, logger, label: game.name, gameId: game.id });

  await pool.query(
    `INSERT INTO achievement_guides (game_id, nodes, model, prompt_version, meta)
     VALUES ($1, $2::jsonb, $3, $4, $5::jsonb)
     ON CONFLICT (game_id) DO UPDATE
       SET nodes = EXCLUDED.nodes, model = EXCLUDED.model,
           prompt_version = EXCLUDED.prompt_version, meta = EXCLUDED.meta,
           generated_at = now()`,
    [game.id, JSON.stringify(guide.nodes), guide.meta.model || 'none', GUIDE_VERSION, JSON.stringify(guide.meta)]
  );

  return {
    statusCode: 200,
    body: { nodes: guide.nodes, phases: guide.phases, model: guide.meta.model, promptVersion: GUIDE_VERSION, cached: false, meta: guide.meta },
  };
}

module.exports = { generateAchievementGuide, getOrCreateGuide, gatherContext, logGuide, saveEnrichment, GUIDE_VERSION };
