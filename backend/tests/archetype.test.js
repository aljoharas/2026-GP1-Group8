'use strict';

// Player Archetypes in Node: the shaping helpers, and the real routes from
// routes/users.js mounted on a throwaway app with the database, the token check
// and the Python service stubbed. No network, no database.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { largestRemainder, normaliseScores, ownArchetype, friendArchetype } = require('../lib/archetype');

// A full body as Python returns it
const PY_BODY = {
  archetype: 'Devotee',
  description: 'One game you keep coming back to, over and over.',
  scores: [
    { archetype: 'Devotee', description: 'd', percent: 62 },
    { archetype: 'The Main', description: 'd', percent: 21 },
    { archetype: 'Casual', description: 'd', percent: 7 },
    { archetype: 'Explorer', description: 'd', percent: 5 },
    { archetype: 'Competitor', description: 'd', percent: 3 },
    { archetype: 'Completionist', description: 'd', percent: 2 },
  ],
  reasons: ['98% of your hours go to Elden Ring', 'You keep to a small set of 5 games'],
  games_played: 5,
  model_version: '1.0.0',
};

// --- helpers -----------------------------------------------------------------

test('largestRemainder always adds up to 100', () => {
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let n = 0; n < 5000; n++) {
    const k = 2 + Math.floor(rand() * 7);
    const values = Array.from({ length: k }, () => rand() ** 3);
    const out = largestRemainder(values);
    assert.equal(out.reduce((a, b) => a + b, 0), 100);
    assert.ok(out.every(Number.isInteger));
  }
  assert.deepEqual(largestRemainder([1, 1, 1]), [34, 33, 33]);
  assert.deepEqual(largestRemainder([46.7, 33.3, 20]), [47, 33, 20]);
});

test('normaliseScores fixes parts that do not add up to 100 and sorts highest first', () => {
  const out = normaliseScores([
    { archetype: 'A', percent: 20.4 }, { archetype: 'B', percent: 50.4 }, { archetype: 'C', percent: 29.2 },
  ]);
  assert.equal(out.reduce((a, s) => a + s.percent, 0), 100);
  assert.deepEqual(out.map((s) => s.archetype), ['B', 'C', 'A']);
});

test('ownArchetype keeps Python scores that already add up to 100', () => {
  const out = ownArchetype(PY_BODY);
  assert.deepEqual(out.scores.map((s) => s.percent), [62, 21, 7, 5, 3, 2]);
  assert.equal(out.scores.length, 6);
  assert.deepEqual(Object.keys(out).sort(),
    ['archetype', 'description', 'games_played', 'model_version', 'reasons', 'scores']);
});

test('ownArchetype passes on not enough games', () => {
  assert.deepEqual(
    ownArchetype({ archetype: null, reason: 'not_enough_games', games_played: 3, min_games: 5 }),
    { archetype: null, reason: 'not_enough_games', games_played: 3, min_games: 5 });
});

test('friendArchetype returns only the name and description', () => {
  assert.deepEqual(friendArchetype(PY_BODY), { archetype: PY_BODY.archetype, description: PY_BODY.description });
  assert.deepEqual(friendArchetype({ archetype: null, reason: 'not_enough_games', games_played: 2 }),
    { archetype: null, description: null });
});

// --- routes --------------------------------------------------------------------

function stubModule(relPath, exports) {
  const resolved = require.resolve(path.join(__dirname, '..', relPath));
  require.cache[resolved] = { id: resolved, filename: resolved, loaded: true, exports };
}

const ME = 'user-me';
const FRIEND = 'user-friend';
const STRANGER = 'user-stranger';
const pythonCalls = [];

stubModule('db/index', {
  // The friendship check: only ME ↔ FRIEND is accepted
  query: async (sql, params) => {
    const ids = new Set(params);
    const accepted = /friendships/.test(sql) && ids.has(ME) && ids.has(FRIEND);
    return { rows: accepted ? [{ '?column?': 1 }] : [] };
  },
});
stubModule('middleware/verifyToken', (req, _res, next) => {
  req.user = { uid: ME };
  next();
});

const express = require('express');
const usersRouter = require('../routes/users');

async function withApp(fn) {
  const realFetch = global.fetch;
  // Every fetch the routes make goes to Python; the test itself uses realFetch
  global.fetch = async (url) => {
    pythonCalls.push(new URL(String(url)).searchParams.get('uid'));
    return new Response(JSON.stringify(PY_BODY), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  const app = express();
  app.use('/users', usersRouter);
  const server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn((p) => realFetch(base + p));
  } finally {
    server.close();
    global.fetch = realFetch;
  }
}

test('GET /users/me/archetype uses the token uid and returns the full mix', async () => {
  await withApp(async (get) => {
    pythonCalls.length = 0;
    const res = await get(`/users/me/archetype?uid=${STRANGER}`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(pythonCalls, [ME]); // never the uid from the query
    assert.equal(body.scores.reduce((a, s) => a + s.percent, 0), 100);
    assert.equal(body.reasons.length, 2);
  });
});

test('GET /users/:id/archetype for a friend never returns scores or reasons', async () => {
  await withApp(async (get) => {
    pythonCalls.length = 0;
    const res = await get(`/users/${FRIEND}/archetype`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(body, { archetype: PY_BODY.archetype, description: PY_BODY.description });
    assert.equal('scores' in body, false);
    assert.equal('reasons' in body, false);
    assert.deepEqual(pythonCalls, [FRIEND]);
  });
});

test('GET /users/:id/archetype for a non-friend is 403 and never asks Python', async () => {
  await withApp(async (get) => {
    pythonCalls.length = 0;
    const res = await get(`/users/${STRANGER}/archetype`);
    assert.equal(res.status, 403);
    assert.deepEqual(pythonCalls, []);
  });
});
