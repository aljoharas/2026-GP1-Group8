/**
 * Permanently force trophies' category. Overrides are checked before every
 * heuristic (and before the DLC confirmation gate). Applies to Steam-sourced
 * guides, keyed on (appid, Steam internal achievement key).
 *
 * <keys> is a comma-separated list, or a range like A51-A75 (same prefix,
 * zero-padded numeric suffix).
 *
 * Usage:
 *   node scripts/set_category_override.js <appid> <keys> <base|dlc|online> [note]
 *   node scripts/set_category_override.js <appid> <keys> --remove
 *
 * Takes effect the next time that game's guide is regenerated (?refresh=true).
 */
require('dotenv').config({ quiet: true });
const pool = require('../db/index');
const { setOverrides, removeOverrides, loadOverrides } = require('../lib/guide/overrides');

function expandKeys(spec) {
  const range = spec.match(/^([A-Za-z_]*)(\d+)-\1(\d+)$/);
  if (!range) return spec.split(',').map((k) => k.trim()).filter(Boolean);
  const [, prefix, from, to] = range;
  const width = Math.max(from.length, to.length);
  const keys = [];
  for (let n = parseInt(from, 10); n <= parseInt(to, 10); n++) keys.push(prefix + String(n).padStart(width, '0'));
  return keys;
}

(async () => {
  const [appid, spec, category, ...noteParts] = process.argv.slice(2);
  if (!appid || !spec || !category) {
    console.log('usage: node scripts/set_category_override.js <appid> <keys|A51-A75> <base|dlc|online|--remove> [note]');
    return;
  }
  const keys = expandKeys(spec);
  if (category === '--remove') {
    return console.log(`removed ${await removeOverrides(pool, appid, keys)} override(s)`);
  }
  const written = await setOverrides(pool, appid, keys, category, noteParts.join(' ') || null);
  // Read back through the same loader the guide uses, so a "written" that
  // isn't actually visible to the guide can't go unnoticed.
  const stored = await loadOverrides(pool, appid);
  const visible = keys.filter((k) => stored.get(k) === category).length;
  console.log(`override set: appid ${appid}, ${written} written, ${visible}/${keys.length} read back as "${category}"`);
  if (visible !== keys.length) process.exitCode = 1;
})().then(() => process.exit()).catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
