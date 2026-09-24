/**
 * One-time backfill of achievement_enrichment from guides that already carry
 * LLM enrichment in their stored nodes, so switching to the enrichment cache
 * does not re-pay for content that hasn't changed. Only guides produced with
 * the CURRENT enrichment version are used.
 *
 * Usage: node scripts/backfill_enrichment_cache.js
 */
require('dotenv').config({ quiet: true });
const pool = require('../db/index');
const { saveEnrichment } = require('../lib/achievementGuide');
const { PROMPT_VERSION } = require('../lib/guide/enrich');
const { inputHash } = require('../lib/guide/enrichCache');

(async () => {
  const { rows } = await pool.query(
    `SELECT ag.game_id, g.name, ag.nodes FROM achievement_guides ag JOIN games g ON g.id = ag.game_id
     WHERE ag.prompt_version LIKE $1`,
    [`%/${PROMPT_VERSION}`]
  );
  let total = 0;
  for (const row of rows) {
    const trophies = row.nodes.flatMap((n) => (n.kind === 'ladder' ? n.tiers.flatMap((t) => t.trophies) : [n]));
    const enriched = trophies
      .filter((t) => t.confidence)
      .map((t) => ({
        trophyId: t.id,
        hash: inputHash({ name: t.name, description: t.description }),
        value: { steps: t.steps || [], categoryVote: t.categoryVote || 'base', confidence: t.confidence },
      }));
    await saveEnrichment(row.game_id, enriched);
    total += enriched.length;
    console.log(`${row.name.padEnd(34)} ${enriched.length}/${trophies.length} trophies cached`);
  }
  console.log(`backfilled ${total} trophies from ${rows.length} guide(s) at ${PROMPT_VERSION}`);
})().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
