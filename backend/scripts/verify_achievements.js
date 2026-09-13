/**
 * Verification CLI for the achievement data layer (lib/achievements.js).
 *
 * Prints, per game: resolved source, Steam appid, total achievements, how
 * many have non-empty descriptions (and the coverage ratio -- this decides
 * how much usable text the trophy guide will have to work with), how many
 * are hidden, availability, and suspectedIncomplete.
 *
 * Accepts RAWG ids or game names as positional args. Names are resolved via
 * the same deterministic RAWG disambiguation the service uses. With no args,
 * runs the 20-game sample from the audit that established Steam as the
 * primary source.
 *
 * Usage:
 *   node scripts/verify_achievements.js
 *   node scripts/verify_achievements.js "Elden Ring" "Celeste" 3498
 */

require('dotenv').config();
const { resolveAchievements, resolveRawgGameId } = require('../lib/achievements');

const DEFAULT_SAMPLE = [
  'Grand Theft Auto V',
  'The Witcher 3 Wild Hunt',
  'Elden Ring',
  'Cyberpunk 2077',
  'Red Dead Redemption 2',
  'Hollow Knight',
  'Stardew Valley',
  'Celeste',
  'Hades',
  'Undertale',
  'God of War Ragnarok',
  'The Last of Us Part II',
  'Bloodborne',
  'Super Mario Odyssey',
  'The Legend of Zelda Breath of the Wild',
  'Half-Life 2',
  'Portal 2',
  'Fallout New Vegas',
  'Papers Please',
  'Return of the Obra Dinn',
];

function isNumericId(s) {
  return /^\d+$/.test(s);
}

async function resolveInput(input) {
  if (isNumericId(input)) {
    return { rawgId: parseInt(input, 10), label: input };
  }
  const { rawgId } = await resolveRawgGameId(input);
  return { rawgId, label: input };
}

function pct(part, total) {
  if (total === 0) return '0.0%';
  return `${((part / total) * 100).toFixed(1)}%`;
}

function pad(str, len) {
  str = String(str);
  return str.length >= len ? str : str + ' '.repeat(len - str.length);
}

async function main() {
  const args = process.argv.slice(2);
  const inputs = args.length > 0 ? args : DEFAULT_SAMPLE;

  const rows = [];

  for (const input of inputs) {
    process.stdout.write(`Resolving "${input}"...\n`);
    try {
      const { rawgId, label } = await resolveInput(input);
      if (!rawgId) {
        rows.push({ label, error: 'no RAWG match found' });
        continue;
      }

      const result = await resolveAchievements(rawgId);
      const hiddenCount = result.achievements.filter((a) => a.hidden).length;

      rows.push({
        label,
        rawgId,
        source: result.source,
        appid: result.appid || '-',
        total: result.total,
        withDescription: result.withDescription,
        descCoverage: pct(result.withDescription, result.total),
        hidden: hiddenCount,
        availability: result.availability,
        suspectedIncomplete: result.suspectedIncomplete,
      });
    } catch (err) {
      rows.push({ label: input, error: err.message });
    }
  }

  console.log('\n' + '='.repeat(120));
  console.log(
    pad('GAME', 32) +
      pad('SRC', 6) +
      pad('APPID', 10) +
      pad('TOTAL', 7) +
      pad('W/DESC', 9) +
      pad('DESC%', 8) +
      pad('HIDDEN', 8) +
      pad('AVAILABILITY', 20) +
      'SUSPECT'
  );
  console.log('-'.repeat(120));

  for (const r of rows) {
    if (r.error) {
      console.log(pad(r.label, 32) + `ERROR: ${r.error}`);
      continue;
    }
    console.log(
      pad(r.label, 32) +
        pad(r.source, 6) +
        pad(r.appid, 10) +
        pad(r.total, 7) +
        pad(r.withDescription, 9) +
        pad(r.descCoverage, 8) +
        pad(r.hidden, 8) +
        pad(r.availability, 20) +
        (r.suspectedIncomplete ? 'YES' : '')
    );
  }
  console.log('='.repeat(120));

  const resolved = rows.filter((r) => !r.error);
  const totalAch = resolved.reduce((sum, r) => sum + r.total, 0);
  const totalWithDesc = resolved.reduce((sum, r) => sum + r.withDescription, 0);
  const totalHidden = resolved.reduce((sum, r) => sum + r.hidden, 0);
  const steamCount = resolved.filter((r) => r.source === 'steam').length;
  const rawgCount = resolved.filter((r) => r.source === 'rawg').length;
  const suspectCount = resolved.filter((r) => r.suspectedIncomplete).length;

  console.log(`\nGames resolved: ${resolved.length}/${rows.length} (${rows.length - resolved.length} errored)`);
  console.log(`Source split: ${steamCount} steam, ${rawgCount} rawg`);
  console.log(`Achievements: ${totalAch} total across all games, ${totalHidden} hidden`);
  console.log(
    `\nDESCRIPTION COVERAGE (overall): ${totalWithDesc}/${totalAch} = ${pct(totalWithDesc, totalAch)}`
  );
  console.log(`suspectedIncomplete flagged on ${suspectCount} game(s)`);

  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
