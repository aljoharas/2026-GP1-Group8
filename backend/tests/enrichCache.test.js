'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { enrichWithCache, inputHash } = require('../lib/guide/enrichCache');
const { buildDeterministicGuide } = require('../lib/guide');

const silent = { warn() {}, log() {} };
const trophies = (n, desc = (i) => `Do thing ${i}`) => Array.from({ length: n }, (_, i) => ({ id: `t${i}`, name: `Trophy ${i}`, description: desc(i) }));

// In-memory stand-ins for the DB table (versioned like the real PK) and the LLM.
function harness(version = 'enrich-1') {
  const store = new Map(); // `${version}|${trophyId}` -> row
  const calls = { enrich: 0, trophiesSent: 0 };
  return {
    calls,
    store,
    run: (list, v = version) =>
      enrichWithCache({
        trophies: list,
        logger: silent,
        load: async () => new Map([...store].filter(([k]) => k.startsWith(v + '|')).map(([k, row]) => [k.split('|')[1], row])),
        save: async (rows) => rows.forEach((r) => store.set(`${v}|${r.trophyId}`, { input_hash: r.hash, steps: r.value.steps, category_vote: r.value.categoryVote, confidence: r.value.confidence })),
        enrich: async (missing) => {
          calls.enrich += Math.ceil(missing.length / 25);
          calls.trophiesSent += missing.length;
          return {
            byId: new Map(missing.map((t) => [t.id, { steps: [`step for ${t.id}`], categoryVote: 'base', confidence: 'high' }])),
            apiCalls: Math.ceil(missing.length / 25),
            errors: [],
            ignoredKeys: [],
          };
        },
      }),
  };
}

test('first run calls the LLM for everything; an unchanged second run makes ZERO calls', async () => {
  const h = harness();
  const list = trophies(60);
  const first = await h.run(list);
  assert.equal(first.requested, 60);
  assert.equal(first.apiCalls, 3);
  assert.equal(first.reused, 0);

  const second = await h.run(list);
  assert.equal(second.apiCalls, 0);
  assert.equal(second.requested, 0);
  assert.equal(second.reused, 60);
  assert.equal(h.calls.enrich, 3, 'no further LLM calls');
  assert.deepEqual([...second.byId.keys()].sort(), [...first.byId.keys()].sort());
  assert.deepEqual(second.byId.get('t7'), first.byId.get('t7'));
});

test('an ordering-only change (different trophy order/ladders) reuses enrichment: zero calls', async () => {
  const h = harness();
  const ach = (name, description, r) => ({ externalId: name, name, description, rarityPercent: r, source: 'steam' });
  const data = [ach('A', 'Do a', 50), ach('B', 'Do b', 20), ach('C', 'Do c', 80)];
  const enrichInput = (guide) => guide.nodes.map((n) => ({ id: n.id, name: n.name, description: n.description }));

  const g1 = buildDeterministicGuide(data);
  await h.run(enrichInput(g1));
  const before = h.calls.enrich;

  // "Ordering version bump": same trophies, different resulting order.
  const g2 = buildDeterministicGuide([...data].reverse().map((a, i) => ({ ...a, rarityPercent: 10 + i })));
  assert.notDeepEqual(g2.nodes.map((n) => n.id), g1.nodes.map((n) => n.id));
  const res = await h.run(enrichInput(g2));
  assert.equal(res.apiCalls, 0);
  assert.equal(h.calls.enrich, before);
});

test('only a trophy whose text changed is re-enriched', async () => {
  const h = harness();
  const list = trophies(30);
  await h.run(list);
  const edited = list.map((t) => (t.id === 't5' ? { ...t, description: 'A brand new description' } : t));
  const res = await h.run(edited);
  assert.equal(res.requested, 1);
  assert.equal(res.reused, 29);
  assert.equal(res.apiCalls, 1);
  assert.notEqual(inputHash(list[5]), inputHash(edited[5]));
});

test('an enrichment-version bump invalidates enrichment (and only enrichment)', async () => {
  const h = harness();
  const list = trophies(30);
  await h.run(list, 'enrich-1');
  const res = await h.run(list, 'enrich-2');
  assert.equal(res.reused, 0, 'v2 finds no v1 rows');
  assert.equal(res.requested, 30);
  // v1 rows are still there for a rollback
  assert.equal((await h.run(list, 'enrich-1')).apiCalls, 0);
});

test('an unreadable cache degrades to a full enrichment instead of failing', async () => {
  const res = await enrichWithCache({
    trophies: trophies(3),
    logger: silent,
    load: async () => { throw new Error('db down'); },
    save: async () => { throw new Error('db down'); },
    enrich: async (m) => ({ byId: new Map(m.map((t) => [t.id, { steps: [], categoryVote: 'base', confidence: 'low' }])), apiCalls: 1, errors: [], ignoredKeys: [] }),
  });
  assert.equal(res.requested, 3);
  assert.equal(res.byId.size, 3);
});

test('a failed LLM batch is not cached, so the next run retries only those trophies', async () => {
  const store = new Map();
  const run = (fail) =>
    enrichWithCache({
      trophies: trophies(4),
      logger: silent,
      load: async () => store,
      save: async (rows) => rows.forEach((r) => store.set(r.trophyId, { input_hash: r.hash, steps: r.value.steps, category_vote: r.value.categoryVote, confidence: r.value.confidence })),
      enrich: async (m) => {
        const ok = fail ? m.filter((t) => t.id !== 't2') : m;
        return { byId: new Map(ok.map((t) => [t.id, { steps: [], categoryVote: 'base', confidence: 'low' }])), apiCalls: 1, errors: fail ? ['batch 1: boom'] : [], ignoredKeys: [] };
      },
    });
  const a = await run(true);
  assert.equal(a.byId.size, 3);
  const b = await run(false);
  assert.equal(b.requested, 1);
  assert.equal(b.reused, 3);
});
