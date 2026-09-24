/**
 * Audit CLI for the deterministic trophy guide. Runs the pipeline (no LLM)
 * for each game and prints: source/appid, overrides applied, every ladder formed (key,
 * members, extracted numbers), rarity-vs-ladder contradictions, non-base
 * classifications with their signals, and a byte-identical regeneration check.
 *
 * Accepts RAWG ids or game names (resolved like verify_achievements.js).
 * With no args, runs the 20-game sample.
 *
 * Usage:
 *   node scripts/guide_ladder_report.js "Fallout New Vegas" "Stardew Valley"
 *   node scripts/guide_ladder_report.js --full 3328
 *   node scripts/guide_ladder_report.js --summary        (one line per ladder-less game)
 */

require('dotenv').config({ quiet: true });
const { resolveAchievements, resolveRawgGameId } = require('../lib/achievements');
const { gatherContext } = require('../lib/achievementGuide');
const { buildDeterministicGuide } = require('../lib/guide');
const { formatLadderLog } = require('../lib/guide/ladders');

const DEFAULT_SAMPLE = [
  'Grand Theft Auto V', 'The Witcher 3 Wild Hunt', 'Elden Ring', 'Cyberpunk 2077',
  'Red Dead Redemption 2', 'Hollow Knight', 'Stardew Valley', 'Celeste', 'Hades', 'Undertale',
  'God of War Ragnarok', 'The Last of Us Part II', 'Bloodborne', 'Super Mario Odyssey',
  'The Legend of Zelda Breath of the Wild', 'Half-Life 2', 'Portal 2', 'Fallout New Vegas',
  'Papers Please', 'Return of the Obra Dinn',
];

async function reportOne(input, { full }) {
  const rawgId = /^\d+$/.test(input) ? parseInt(input, 10) : (await resolveRawgGameId(input)).rawgId;
  if (!rawgId) return console.log(`\n=== ${input} ===\n  no RAWG match`);

  const resolved = await resolveAchievements(rawgId);
  console.log(`\n${'='.repeat(100)}\n=== ${input} (rawg ${rawgId}) source=${resolved.source} appid=${resolved.appid || '-'} ` +
    `availability=${resolved.availability} total=${resolved.total}`);
  if (resolved.availability !== 'available') return;

  const ctx = await gatherContext(resolved);
  const guide = buildDeterministicGuide(resolved.achievements, ctx);
  const again = buildDeterministicGuide(resolved.achievements, ctx);
  const identical = JSON.stringify(guide) === JSON.stringify(again);

  const { ladders, contradictions, classification, tailStart } = guide.logs;
  const inLadders = ladders.filter((l) => l.verdict === 'ladder');
  const counts = guide.nodes.reduce((m, n) => ((m[n.category] = (m[n.category] || 0) + 1), m), {});
  console.log(`  rarity-cliff tail start=${tailStart} overrides applied=${ctx.overrides.size}${ctx.overridesError ? ' (LOAD ERROR: ' + ctx.overridesError + ')' : ''}`);
  console.log(`  entries=${guide.nodes.length} phases=${JSON.stringify(counts)} ladders=${inLadders.length} ` +
    `(collisions=${ladders.filter((l) => l.verdict === 'collision').length}, skipped=${ladders.filter((l) => l.verdict === 'skipped').length}) ` +
    `contradictions=${contradictions.length} byte-identical-regeneration=${identical}`);

  if (ladders.length === 0) console.log('  ladder log: (none)');
  for (const e of ladders) console.log(`  ladder ${formatLadderLog(e)}`);
  for (const c of contradictions) {
    console.log(`  contradiction: "${c.ladder}" tier ${c.higher} (${c.higherRarity}%) > tier ${c.lower} (${c.lowerRarity}%) -> ${c.resolution}`);
  }
  if (classification.length === 0) console.log('  classification: all base, nothing suppressed');
  for (const c of classification) {
    console.log(`  classify: ${c.name} [${c.key || '-'}] -> ${c.category} via ${c.decidedBy}` +
      ` signals=[${c.signals.join(',')}]`);
  }
  if (full) {
    for (const n of guide.nodes) {
      console.log(`  ${String(n.order).padStart(3)} [${n.category}] ${n.rarity ?? 'null'}% ${n.name}`);
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const full = args.includes('--full');
  const inputs = args.filter((a) => !a.startsWith('--'));
  for (const input of inputs.length ? inputs : DEFAULT_SAMPLE) {
    try {
      await reportOne(input, { full });
    } catch (err) {
      console.log(`\n=== ${input} ===\n  ERROR: ${err.message}`);
    }
  }
}

main().then(() => process.exit(0));
