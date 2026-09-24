/**
 * Generates (or serves from cache) the trophy guide for a game through the
 * same code path as GET /games/:id/achievement-guide, and prints the result.
 *
 * Usage:
 *   node scripts/generate_guide.js <rawgId> [--refresh] [--no-llm] [--json]
 */
require('dotenv').config({ quiet: true });
const { getOrCreateGuide } = require('../lib/achievementGuide');

(async () => {
  const args = process.argv.slice(2);
  const rawgId = parseInt(args.find((a) => /^\d+$/.test(a)), 10);
  if (!rawgId) return console.log('usage: node scripts/generate_guide.js <rawgId> [--refresh] [--no-llm] [--json]');

  const { statusCode, body } = await getOrCreateGuide(rawgId, {
    forceRefresh: args.includes('--refresh'),
    skipLLM: args.includes('--no-llm'),
  });
  if (statusCode !== 200) return console.log(statusCode, body);
  if (args.includes('--json')) return console.log(JSON.stringify(body.nodes));

  console.log(`\ncached=${body.cached} model=${body.model} promptVersion=${body.promptVersion}`);
  console.log(`phases: ${body.phases.map((p) => `${p.name}(${p.count})`).join(', ')}`);
  if (body.meta) console.log(`enrichment: ${JSON.stringify(body.meta.enrichment)}`);
  for (const n of body.nodes) {
    const tail = n.kind === 'ladder' ? '' : n.steps?.length ? `  | steps: ${n.steps.join(' / ')}` : '';
    console.log(`${String(n.order).padStart(3)} [${n.category}] ${String(n.rarity ?? 'null').padStart(6)}%  ${n.name}${tail}  (${n.confidence || '-'}${n.suspectedCategory ? `, LLM suspects ${n.suspectedCategory}` : ''})`);
  }
})().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
