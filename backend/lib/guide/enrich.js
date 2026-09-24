'use strict';

// Per-trophy enrichment. The LLM is demoted to hints only:
//   - at most 2 short concrete steps derived from the description
//   - a category vote (secondary signal; never moves a trophy between phases)
//   - a confidence rating, with empty steps when the description gives nothing
// The response schema has NO ordering / phase / dependency fields, and
// sanitizeEnrichment() drops anything outside the allowed four even if a
// model returns it anyway -- so a bad response cannot affect sequence.

const PROMPT_VERSION = 'enrich-1';
const DEFAULT_MODEL = 'gpt-4o-mini';
const BATCH_SIZE = 25;
const MAX_STEPS = 2;
const MAX_STEP_LENGTH = 140;

const ALLOWED_FIELDS = ['id', 'steps', 'categoryVote', 'confidence'];
const CATEGORIES = ['base', 'dlc', 'online'];
const CONFIDENCES = ['low', 'medium', 'high'];

const ENRICH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['trophies'],
  properties: {
    trophies: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ALLOWED_FIELDS,
        properties: {
          id: { type: 'string' },
          steps: { type: 'array', items: { type: 'string' } },
          categoryVote: { type: 'string', enum: CATEGORIES },
          confidence: { type: 'string', enum: CONFIDENCES },
        },
      },
    },
  },
};

const INSTRUCTIONS =
  'You annotate individual video game achievements. For each achievement return: ' +
  '"steps" -- at most 2 short, concrete actions derived ONLY from its description ' +
  '(never invent mechanics you cannot read in the description); "categoryVote" -- ' +
  '"online" if it needs multiplayer/online play, "dlc" if it clearly belongs to ' +
  'downloadable/expansion content, otherwise "base"; "confidence" -- "low" with an ' +
  'EMPTY steps array when the description does not support a concrete step (that is ' +
  'a correct answer, not a failure), otherwise "medium" or "high". ' +
  'You do not decide the order of achievements. Return one entry per input id.';

function buildEnrichInput(trophies) {
  const lines = trophies.map((t) => `- id: ${t.id} | name: ${t.name} | description: ${t.description || '(none)'}`);
  return `Achievements:\n${lines.join('\n')}`;
}

// Keeps only the four allowed fields per trophy; everything else (order,
// phase, sequence, dependsOn, top-level extras ...) is dropped and reported.
function sanitizeEnrichment(parsed, validIds) {
  const byId = new Map();
  const ignoredKeys = new Set();
  if (!parsed || typeof parsed !== 'object') return { byId, ignoredKeys };

  for (const k of Object.keys(parsed)) if (k !== 'trophies') ignoredKeys.add(k);
  const list = Array.isArray(parsed.trophies) ? parsed.trophies : [];

  for (const raw of list) {
    if (!raw || typeof raw !== 'object') continue;
    for (const k of Object.keys(raw)) if (!ALLOWED_FIELDS.includes(k)) ignoredKeys.add(k);

    const id = typeof raw.id === 'string' ? raw.id : null;
    if (id === null || !validIds.has(id) || byId.has(id)) continue;

    const confidence = CONFIDENCES.includes(raw.confidence) ? raw.confidence : 'low';
    let steps = Array.isArray(raw.steps)
      ? raw.steps
          .filter((s) => typeof s === 'string' && s.trim())
          .slice(0, MAX_STEPS)
          .map((s) => s.trim().slice(0, MAX_STEP_LENGTH))
      : [];
    if (confidence === 'low') steps = [];

    byId.set(id, {
      steps,
      categoryVote: CATEGORIES.includes(raw.categoryVote) ? raw.categoryVote : 'base',
      confidence,
    });
  }
  return { byId, ignoredKeys };
}

async function enrichBatch(client, trophies, model) {
  const response = await client.responses.create({
    model,
    instructions: INSTRUCTIONS,
    input: buildEnrichInput(trophies),
    temperature: 0,
    text: { format: { type: 'json_schema', name: 'trophy_enrichment', strict: true, schema: ENRICH_SCHEMA } },
  });
  return JSON.parse(response.output_text);
}

// trophies: [{ id, name, description }]. Never throws -- enrichment is
// optional, so a failed batch just leaves those trophies un-enriched.
async function enrichTrophies(client, trophies, { model = DEFAULT_MODEL, batchSize = BATCH_SIZE } = {}) {
  const byId = new Map();
  const ignoredKeys = new Set();
  const errors = [];
  const validIds = new Set(trophies.map((t) => t.id));
  let apiCalls = 0;

  for (let i = 0; i < trophies.length; i += batchSize) {
    const batch = trophies.slice(i, i + batchSize);
    apiCalls++;
    try {
      const parsed = await enrichBatch(client, batch, model);
      const res = sanitizeEnrichment(parsed, new Set(batch.map((t) => t.id)));
      for (const [id, v] of res.byId) byId.set(id, v);
      for (const k of res.ignoredKeys) ignoredKeys.add(k);
    } catch (err) {
      errors.push(`batch ${i / batchSize + 1}: ${err.message}`);
    }
  }

  return { byId, ignoredKeys: [...ignoredKeys], errors, requested: validIds.size, apiCalls };
}

module.exports = {
  enrichTrophies,
  sanitizeEnrichment,
  buildEnrichInput,
  ENRICH_SCHEMA,
  PROMPT_VERSION,
  DEFAULT_MODEL,
};
