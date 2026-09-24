'use strict';

// Manual category overrides, keyed on (Steam appid, internal achievement key).
// Checked before every heuristic and before the DLC confirmation gate.
//
// `db` is anything with .query (a pg Pool or a checked-out client), so the
// same code runs in production, the CLI, and transactional tests.

const CATEGORIES = ['base', 'dlc', 'online'];

function assertCategory(category) {
  if (!CATEGORIES.includes(category)) {
    throw new Error(`invalid category "${category}" (expected ${CATEGORIES.join('|')})`);
  }
}

// Throws on failure -- callers decide how loud to be. Never returns a silent
// empty map for an error.
async function loadOverrides(db, appid) {
  const res = await db.query(
    'SELECT achievement_key, category FROM achievement_category_overrides WHERE appid = $1',
    [String(appid)]
  );
  return new Map(res.rows.map((r) => [r.achievement_key, r.category]));
}

async function setOverrides(db, appid, keys, category, note = null) {
  assertCategory(category);
  if (!keys.length) return 0;
  const res = await db.query(
    `INSERT INTO achievement_category_overrides (appid, achievement_key, category, note)
     SELECT $1, k, $3, $4 FROM unnest($2::text[]) AS k
     ON CONFLICT (appid, achievement_key)
     DO UPDATE SET category = EXCLUDED.category, note = EXCLUDED.note`,
    [String(appid), keys, category, note]
  );
  return res.rowCount;
}

async function removeOverrides(db, appid, keys) {
  const res = await db.query(
    'DELETE FROM achievement_category_overrides WHERE appid = $1 AND achievement_key = ANY($2::text[])',
    [String(appid), keys]
  );
  return res.rowCount;
}

module.exports = { loadOverrides, setOverrides, removeOverrides, CATEGORIES };
