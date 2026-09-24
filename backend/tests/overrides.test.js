'use strict';

// Integration test for the manual-override path. Runs against the real
// database inside a transaction that is always rolled back, so it writes,
// reads back and feeds the guide pipeline without leaving a trace. It FAILS
// (not skips) if the override table/privileges are broken -- the point is that
// this mechanism cannot silently stop working.

const test = require('node:test');
const assert = require('node:assert/strict');

require('dotenv').config({ quiet: true });
const hasDb = !!process.env.DATABASE_URL;
const pool = hasDb ? require('../db/index') : null;

const { loadOverrides, setOverrides, removeOverrides } = require('../lib/guide/overrides');
const { buildDeterministicGuide } = require('../lib/guide');

const TEST_APPID = '__override_test__';

test('override table is writable, read back, and applied by the guide pipeline', { skip: !hasDb && 'DATABASE_URL not set' }, async (t) => {
  t.after(() => pool.end());
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const written = await setOverrides(client, TEST_APPID, ['A51', 'A52'], 'dlc', 'test');
    assert.equal(written, 2);

    const stored = await loadOverrides(client, TEST_APPID);
    assert.equal(stored.get('A51'), 'dlc');
    assert.equal(stored.get('A52'), 'dlc');

    // Re-writing the same key updates rather than duplicating.
    await setOverrides(client, TEST_APPID, ['A51'], 'online', 'changed');
    assert.equal((await loadOverrides(client, TEST_APPID)).get('A51'), 'online');

    // Fed into the real pipeline.
    const guide = buildDeterministicGuide(
      [
        { externalId: 'A50', internalKey: 'A50', name: 'Base', description: 'Do a thing', rarityPercent: 10, source: 'steam' },
        { externalId: 'A52', internalKey: 'A52', name: 'Extra', description: 'Do another thing', rarityPercent: 90, source: 'steam' },
      ],
      { overrides: await loadOverrides(client, TEST_APPID) }
    );
    assert.equal(guide.nodes.find((n) => n.name === 'Extra').phase, 'dlc');
    assert.equal(guide.nodes.find((n) => n.name === 'Base').phase, 'base');
    assert.deepEqual(guide.nodes.map((n) => n.name), ['Base', 'Extra'], 'dlc phase sorts after base regardless of rarity');

    // 'base' is storable too (DB CHECK constraint), so an override can force a
    // key back to base -- e.g. Half-Life 2's EP1_/EP2_ (separate Steam apps).
    await setOverrides(client, TEST_APPID, ['EP1_TEST'], 'base', 'separate app');
    const back = await loadOverrides(client, TEST_APPID);
    assert.equal(back.get('EP1_TEST'), 'base');
    const g2 = buildDeterministicGuide(
      [{ externalId: 'EP1_TEST', internalKey: 'EP1_TEST', name: 'Ep', description: 'Do a thing', rarityPercent: 5, source: 'steam' }],
      { overrides: back }
    );
    assert.equal(g2.nodes[0].phase, 'base', 'EP1_ matches the DLC pattern but the override wins');
    assert.equal(buildDeterministicGuide(g2.nodes.length ? [{ externalId: 'EP1_TEST', internalKey: 'EP1_TEST', name: 'Ep', description: 'Do a thing', rarityPercent: 5, source: 'steam' }] : []).nodes[0].phase, 'dlc', 'without the override it is dlc');

    assert.equal(await removeOverrides(client, TEST_APPID, ['A51', 'A52', 'EP1_TEST']), 3);
    assert.equal((await loadOverrides(client, TEST_APPID)).size, 0);

    await assert.rejects(setOverrides(client, TEST_APPID, ['A1'], 'nonsense'), /invalid category/);
  } finally {
    await client.query('ROLLBACK');
    client.release();
  }

  // Nothing leaked out of the rolled-back transaction.
  assert.equal((await loadOverrides(pool, TEST_APPID)).size, 0);
});
