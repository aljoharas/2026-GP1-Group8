'use strict';

const crypto = require('crypto');

// Hash of exactly what the model sees for one trophy. Changing a trophy's
// name/description re-enriches that trophy only.
function inputHash(trophy) {
  return crypto
    .createHash('sha1')
    .update(`${trophy.name || ''}\u0000${trophy.description || ''}`)
    .digest('hex');
}

// Reuses cached enrichment where the input hash still matches and calls the
// LLM only for the rest. Storage and the LLM are injected so this is testable
// without a database or network:
//   load(): Promise<Map<trophyId, { input_hash, steps, category_vote, confidence }>>
//   save(rows): Promise<void>            rows: [{ trophyId, hash, value }]
//   enrich(trophies): Promise<{ byId, apiCalls, errors, ignoredKeys }>
async function enrichWithCache({ trophies, load, save, enrich, logger = console }) {
  let cached = new Map();
  try {
    cached = await load();
  } catch (err) {
    logger.warn(`[guide] enrichment cache unreadable, enriching everything: ${err.message}`);
  }

  const byId = new Map();
  const missing = [];
  for (const t of trophies) {
    const row = cached.get(t.id);
    if (row && row.input_hash === inputHash(t)) {
      byId.set(t.id, { steps: row.steps, categoryVote: row.category_vote, confidence: row.confidence });
    } else {
      missing.push(t);
    }
  }
  const reused = byId.size;

  let apiCalls = 0;
  let errors = [];
  let ignoredKeys = [];
  if (missing.length > 0) {
    const res = await enrich(missing);
    apiCalls = res.apiCalls;
    errors = res.errors;
    ignoredKeys = res.ignoredKeys;
    for (const [id, v] of res.byId) byId.set(id, v);
    const fresh = missing.filter((t) => res.byId.has(t.id));
    try {
      await save(fresh.map((t) => ({ trophyId: t.id, hash: inputHash(t), value: res.byId.get(t.id) })));
    } catch (err) {
      logger.warn(`[guide] could not persist enrichment cache: ${err.message}`);
    }
  }

  return { byId, reused, requested: missing.length, apiCalls, errors, ignoredKeys };
}

module.exports = { enrichWithCache, inputHash };
