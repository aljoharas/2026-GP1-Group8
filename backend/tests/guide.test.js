'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { extractNumbers, ladderKey } = require('../lib/guide/numbers');
const { buildLadders } = require('../lib/guide/ladders');
const { classifyAll } = require('../lib/guide/classify');
const { orderEntries } = require('../lib/guide/order');
const { buildDeterministicGuide, applyEnrichment } = require('../lib/guide');
const { sanitizeEnrichment, ENRICH_SCHEMA } = require('../lib/guide/enrich');

function ach(name, description, rarity, extra = {}) {
  return { externalId: extra.key || name, name, description, rarityPercent: rarity, source: 'steam', ...extra };
}
const item = (id, description, rarity, category = 'base') => ({ id, name: id, description, rarity, category });
const names = (guide) => guide.nodes.map((n) => n.name);

// ── numbers ──────────────────────────────────────────────────────────────

test('ladder key: numbers become #, punctuation stripped', () => {
  assert.equal(ladderKey('Finish 50 contracts').key, 'finish # contracts');
  assert.equal(ladderKey('Finish 100 contracts!').key, 'finish # contracts');
});

test('written numbers parse (one-twenty, fifty, hundred, thousand, million)', () => {
  assert.deepEqual(extractNumbers('Collect twenty-five items').values, [25]);
  assert.deepEqual(extractNumbers('Win fifty matches').values, [50]);
  assert.deepEqual(extractNumbers('Deal one hundred damage').values, [100]);
  assert.deepEqual(extractNumbers('Earn two thousand points').values, [2000]);
  assert.deepEqual(extractNumbers('Earn one million gold').values, [1000000]);
  assert.deepEqual(extractNumbers('Kill seven enemies').values, [7]);
  assert.equal(extractNumbers('Kill twenty enemies').template, 'kill # enemies');
});

test('digits with thousands separators and k suffix parse', () => {
  assert.deepEqual(extractNumbers('Score 1,000 points').values, [1000]);
  assert.deepEqual(extractNumbers('Score 1.000 points').values, [1000]);
  assert.deepEqual(extractNumbers('Score 2,500,000 points').values, [2500000]);
  assert.deepEqual(extractNumbers('Deal 10k damage').values, [10000]);
  assert.deepEqual(extractNumbers('Run 1.5 miles').values, [1.5]);
});

test('"one" as a pronoun is not a number', () => {
  assert.deepEqual(extractNumbers('Defeat one of the bosses').values, []);
  assert.deepEqual(extractNumbers('Let no one die').values, []);
});

test('"all"/"every" with no number gets Infinity and matches the numeric key', () => {
  const all = ladderKey('Collect all coins');
  const num = ladderKey('Collect 50 coins');
  assert.equal(all.key, num.key);
  assert.deepEqual(all.values, [Infinity]);
});

// ── ladders ──────────────────────────────────────────────────────────────

test('ladder sorts ascending by value regardless of rarity or input order', () => {
  const { ladders } = buildLadders([
    item('c', 'Complete 100 contracts', 20),
    item('a', 'Complete 10 contracts', 60),
    item('b', 'Complete 50 contracts', 30),
  ]);
  assert.equal(ladders.length, 1);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['10', '50', '100']);
  assert.deepEqual(ladders[0].edges, [
    { from: 'a', to: 'b' },
    { from: 'b', to: 'c' },
  ]);
});

test('the 50 precedes the 100 even when 100 is (wrongly) rarer-listed first', () => {
  const guide = buildDeterministicGuide([
    ach('Boss', 'Finish 100 contracts', 5),
    ach('Pro', 'Finish 50 contracts', 30),
  ]);
  assert.equal(guide.nodes.length, 1);
  assert.equal(guide.nodes[0].kind, 'ladder');
  assert.deepEqual(guide.nodes[0].tiers.map((t) => t.label), ['50', '100']);
});

test('inverted ladder (under N) sorts the hardest (smallest) tier last', () => {
  const { ladders } = buildLadders([
    item('five', 'Finish the level in under 5 minutes', 5),
    item('ten', 'Finish the level in under 10 minutes', 20),
  ]);
  assert.equal(ladders[0].inverted, true);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['10', '5']);

  const three = buildLadders([
    item('a', 'Win within 3 minutes', 2),
    item('b', 'Win within 30 minutes', 40),
    item('c', 'Win within 10 minutes', 15),
  ]);
  assert.deepEqual(three.ladders[0].tiers.map((t) => t.label), ['30', '10', '3']);
});

test('"all" sorts last, even in an inverted ladder', () => {
  const { ladders } = buildLadders([
    item('all', 'Collect all coins', 3),
    item('fifty', 'Collect 50 coins', 40),
    item('ten', 'Collect 10 coins', 70),
  ]);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['10', '50', 'all']);
});

test('equal-value key collision is grouped/logged but not chained', () => {
  const { ladders, log } = buildLadders([
    item('x', 'Kill 10 wolves', 40),
    item('y', 'Kill 10 wolves', 35),
  ]);
  assert.equal(ladders.length, 0);
  assert.equal(log.length, 1);
  assert.equal(log[0].verdict, 'collision');
});

test('a single match is not a ladder; multi-number ambiguity is skipped', () => {
  assert.equal(buildLadders([item('only', 'Kill 10 wolves', 40)]).ladders.length, 0);
  const amb = buildLadders([
    item('p', 'Win 5 games in 10 minutes', 40),
    item('q', 'Win 8 games in 20 minutes', 30),
  ]);
  assert.equal(amb.ladders.length, 0);
  assert.equal(amb.log[0].verdict, 'skipped');
});

test('duplicates within one tier do not chain to each other', () => {
  const { ladders } = buildLadders([
    item('a1', 'Win 10 games', 50),
    item('a2', 'Win 10 games', 48),
    item('b', 'Win 50 games', 20),
  ]);
  assert.equal(ladders[0].tiers.length, 2);
  assert.deepEqual(
    ladders[0].edges.map((e) => `${e.from}>${e.to}`).sort(),
    ['a1>b', 'a2>b']
  );
});

test('rarity contradicting ladder order is logged and ladder wins', () => {
  const { ladders, contradictions } = buildLadders([
    item('low', 'Reach level 10', 10),
    item('high', 'Reach level 20', 60),
  ]);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['10', '20']);
  assert.equal(contradictions.length, 1);
  assert.equal(contradictions[0].resolution, 'ladder order wins');
});

test('ladders never span categories', () => {
  const { ladders } = buildLadders([
    item('a', 'Win 10 matches', 50, 'base'),
    item('b', 'Win 50 matches', 20, 'online'),
  ]);
  assert.equal(ladders.length, 0);
});

// ── ordering ─────────────────────────────────────────────────────────────

test('null rarity sorts last within its phase, never as 0, never crashes', () => {
  const entries = [
    { id: 'n', phase: 'base', rarity: null, name: 'A-null', dependsOn: [] },
    { id: 'z', phase: 'base', rarity: 0, name: 'Zero', dependsOn: [] },
    { id: 'h', phase: 'base', rarity: 80, name: 'High', dependsOn: [] },
    { id: 'n2', phase: 'base', rarity: null, name: 'B-null', dependsOn: [] },
  ];
  const { ordered } = orderEntries(entries);
  assert.deepEqual(ordered.map((e) => e.id), ['h', 'z', 'n', 'n2']);
});

test('dependencies are hard constraints; rarity only breaks ties', () => {
  const { ordered } = orderEntries([
    { id: 'hard', phase: 'base', rarity: 90, name: 'Popular', dependsOn: ['pre'] },
    { id: 'pre', phase: 'base', rarity: 5, name: 'Prereq', dependsOn: [] },
  ]);
  assert.deepEqual(ordered.map((e) => e.id), ['pre', 'hard']);
});

test('equal rarity falls back to name, then id (stable total order)', () => {
  const a = { id: '2', phase: 'base', rarity: 10, name: 'Beta', dependsOn: [] };
  const b = { id: '1', phase: 'base', rarity: 10, name: 'Alpha', dependsOn: [] };
  assert.deepEqual(orderEntries([a, b]).ordered.map((e) => e.name), ['Alpha', 'Beta']);
  assert.deepEqual(orderEntries([b, a]).ordered.map((e) => e.name), ['Alpha', 'Beta']);
});

test('DLC and online phases come after base regardless of rarity', () => {
  const { ordered } = orderEntries([
    { id: 'd', phase: 'dlc', rarity: 99, name: 'D', dependsOn: [] },
    { id: 'o', phase: 'online', rarity: 98, name: 'O', dependsOn: [] },
    { id: 'b', phase: 'base', rarity: 1, name: 'B', dependsOn: [] },
  ]);
  assert.deepEqual(ordered.map((e) => e.id), ['b', 'o', 'd']);
});

test('dependency cycle does not hang or drop entries', () => {
  const { ordered, log } = orderEntries([
    { id: 'a', phase: 'base', rarity: 10, name: 'A', dependsOn: ['b'] },
    { id: 'b', phase: 'base', rarity: 20, name: 'B', dependsOn: ['a'] },
  ]);
  assert.equal(ordered.length, 2);
  assert.ok(log.some((l) => l.type === 'cycle-broken'));
});

// ── classification ───────────────────────────────────────────────────────

const classItems = (rows) =>
  rows.map((r, i) => ({ id: r.key, index: i, name: r.name || r.key, description: r.desc || '', internalKey: r.key, rarity: r.rarity ?? 50 }));

test('DLC key patterns classify as dlc on their own -- there is no store-metadata gate', () => {
  const items = classItems([{ key: 'DLC1_BOSS' }, { key: 'EP2_FINISH' }, { key: 'WIN_GAME' }]);
  const r = classifyAll(items).results;
  assert.equal(r.get('DLC1_BOSS').category, 'dlc');
  assert.equal(r.get('EP2_FINISH').category, 'dlc');
  assert.equal(r.get('WIN_GAME').category, 'base');
  // Unaffected by any (ignored) store info passed in the context.
  const withStale = classifyAll(items, { dlc: { status: 'ok', dlcCount: 0 } }).results;
  assert.equal(withStale.get('DLC1_BOSS').category, 'dlc');
});

test('online via key prefix and via keywords; base otherwise', () => {
  const items = classItems([
    { key: 'MP_WIN' },
    { key: 'COOP_CLEAR' },
    { key: 'A1', desc: 'Win a ranked match against other players' },
    { key: 'A2', name: 'GTA Online: Rank 10', desc: 'Reach rank 10' },
    { key: 'A3', desc: 'Defeat the final boss' },
  ]);
  const r = classifyAll(items).results;
  assert.equal(r.get('MP_WIN').category, 'online');
  assert.equal(r.get('COOP_CLEAR').category, 'online');
  assert.equal(r.get('A1').category, 'online');
  assert.equal(r.get('A2').category, 'online');
  assert.equal(r.get('A3').category, 'base');
});

test('DLC keyword alone is not enough without the rarity-cliff tail', () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({ key: `ACH_${i}`, rarity: 60 }));
  rows[3] = { key: 'ACH_3', desc: 'Finish the expansion story', rarity: 60 };
  const noTail = classifyAll(classItems(rows));
  assert.equal(noTail.results.get('ACH_3').category, 'base');

  const tailRows = Array.from({ length: 12 }, (_, i) => ({ key: `ACH_${i}`, rarity: i >= 10 ? 4 : 60 }));
  tailRows[11] = { key: 'ACH_11', desc: 'Finish the expansion story', rarity: 4 };
  const withTail = classifyAll(classItems(tailRows));
  assert.equal(withTail.results.get('ACH_11').category, 'dlc');
});

test('manual override beats every heuristic and works in BOTH directions (to base, and away from base)', () => {
  const items = classItems([{ key: 'WIN_GAME' }, { key: 'DLC1_X' }, { key: 'EP1_A' }, { key: 'MP_B' }]);
  const r = classifyAll(items, {
    overrides: new Map([['WIN_GAME', 'dlc'], ['DLC1_X', 'base'], ['EP1_A', 'base'], ['MP_B', 'base']]),
  }).results;
  assert.equal(r.get('WIN_GAME').category, 'dlc', 'promote a plain key to dlc');
  assert.equal(r.get('WIN_GAME').decidedBy, 'override');
  assert.equal(r.get('DLC1_X').category, 'base', 'force a DLC-pattern key back to base');
  assert.equal(r.get('EP1_A').category, 'base');
  assert.equal(r.get('MP_B').category, 'base', 'force an online-pattern key back to base');
  assert.equal(r.get('EP1_A').decidedBy, 'override');
});

// ── LLM output cannot influence sequence ─────────────────────────────────

test('schema exposes no ordering, phase or dependency fields', () => {
  const props = Object.keys(ENRICH_SCHEMA.properties.trophies.items.properties).sort();
  assert.deepEqual(props, ['categoryVote', 'confidence', 'id', 'steps']);
  assert.equal(ENRICH_SCHEMA.properties.trophies.items.additionalProperties, false);
});

test('LLM ordering fields are ignored and reported', () => {
  const { byId, ignoredKeys } = sanitizeEnrichment(
    {
      order: ['b', 'a'],
      phases: ['x'],
      trophies: [
        { id: 'a', steps: ['Do X', 'Do Y', 'Do Z'], categoryVote: 'base', confidence: 'high', order: 1, phase: 'dlc', dependsOn: ['b'] },
        { id: 'b', steps: ['ignored because low'], categoryVote: 'nonsense', confidence: 'low' },
        { id: 'ghost', steps: ['x'], categoryVote: 'base', confidence: 'high' },
      ],
    },
    new Set(['a', 'b'])
  );
  assert.deepEqual([...byId.keys()], ['a', 'b']);
  assert.deepEqual(byId.get('a'), { steps: ['Do X', 'Do Y'], categoryVote: 'base', confidence: 'high' });
  assert.deepEqual(byId.get('b'), { steps: [], categoryVote: 'base', confidence: 'low' });
  for (const k of ['order', 'phases', 'phase', 'dependsOn']) assert.ok(ignoredKeys.has(k), `${k} should be reported`);
});

test('applying enrichment never changes the sequence, even with hostile input', () => {
  const guide = buildDeterministicGuide([
    ach('First', 'Do a thing', 80),
    ach('Second', 'Do another thing', 40),
    ach('Third', 'Do a rare thing', 5),
  ]);
  const hostile = new Map([
    ['Third', { steps: ['a'], categoryVote: 'dlc', confidence: 'high', order: 0, phase: 'base' }],
    ['First', { steps: [], categoryVote: 'online', confidence: 'low' }],
  ]);
  const enriched = applyEnrichment(guide, hostile);
  assert.deepEqual(names(enriched), names(guide));
  assert.deepEqual(enriched.nodes.map((n) => n.phase), guide.nodes.map((n) => n.phase));
  assert.equal(enriched.nodes.find((n) => n.name === 'Third').suspectedCategory, 'dlc');
});

// ── determinism ──────────────────────────────────────────────────────────

test('same input twice => byte-identical output, and input order does not matter', () => {
  const data = [
    ach('Rookie', 'Complete 10 contracts', 60),
    ach('Pro', 'Complete 50 contracts', 30),
    ach('Boss', 'Complete 100 contracts', 10),
    ach('Solo', 'Finish the tutorial', 90),
    ach('Ghost', 'Find the secret', null),
    ach('Tie A', 'Something', 25),
    ach('Tie B', 'Something else', 25),
  ];
  const a = JSON.stringify(buildDeterministicGuide(data));
  const b = JSON.stringify(buildDeterministicGuide(data));
  assert.equal(a, b);
  const shuffled = [...data].reverse();
  assert.deepEqual(names(buildDeterministicGuide(shuffled)), names(buildDeterministicGuide(data)));
});

// ── key patterns against real Steam internal keys ─────────────────────────
// (keys taken from GetGlobalAchievementPercentagesForApp for real appids)

test('real Steam DLC/online keys match; plain base-game keys do not', () => {
  const { DLC_KEY_PATTERNS, ONLINE_KEY_PATTERNS } = require('../lib/guide/classify');
  const isDlc = (k) => DLC_KEY_PATTERNS.some((re) => re.test(k));
  const isOnline = (k) => ONLINE_KEY_PATTERNS.some((re) => re.test(k));

  for (const k of ['EP1_1', 'EP2_11', 'EP1_BEAT_MAINELEVATOR', 'DLC1_BOSS']) assert.ok(isDlc(k), k);
  for (const k of ['ACH.SPEED_RUN_COOP', 'ACH_GET_KILLED_BY_A_BANSHEE_IN_MULTIPLAYER', 'MP_WIN']) assert.ok(isOnline(k), k);
  for (const k of ['A31', 'ACH00', 'ACH_COMPLETE_10_CONTRACTS', 'HL2_GET_CROWBAR', 'LILAC', 'TheFool', 'FK_DEFEAT', 'EPIC_WIN', 'CAMPAIGN_DONE']) {
    assert.ok(!isDlc(k) && !isOnline(k), `${k} should be base`);
  }
});

// ── tense normalization, word tiers, Roman numerals ───────────────────────

test('verb inflection lookup: "Reached 10th level" joins "Reach 20th level" (whole tokens only)', () => {
  assert.equal(ladderKey('Reached 10th level.').key, ladderKey('Reach 20th level.').key);
  assert.equal(ladderKey('Won 3 games of Caravan').key, ladderKey('Win 30 games of Caravan').key);
  assert.equal(ladderKey('Collecting 5 coins').key, ladderKey('Collect 50 coins').key);
  // whole-token only: substrings are untouched, and unlisted words are not stemmed
  assert.equal(ladderKey('Undiscovered 5 places').key, 'undiscovered # places');
  assert.equal(ladderKey('Jumped 5 times').key, 'jumped # times');
});

test('FNV-style level ladder becomes one ladder 10 -> 20 -> 30', () => {
  const { ladders } = buildLadders([
    item('nk', 'Reached 10th level.', 45),
    item('uc', 'Reach 20th level.', 32),
    item('tb', 'Reach 30th level.', 21),
  ]);
  assert.equal(ladders.length, 1);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['10', '20', '30']);
});

test('bronze < silver < gold < platinum < diamond form an ordered tier ladder', () => {
  const { ladders } = buildLadders([
    item('g', 'Obtain the Gold Apocalypse Trophy', 1.3),
    item('b', 'Obtain the Bronze Apocalypse Trophy', 1.5),
    item('s', 'Obtain the Silver Apocalypse Trophy', 1.3),
  ]);
  assert.equal(ladders.length, 1);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['bronze', 'silver', 'gold']);
  assert.deepEqual(ladders[0].edges, [{ from: 'b', to: 's' }, { from: 's', to: 'g' }]);

  const more = buildLadders([
    item('d', 'Reach Diamond rank', 1),
    item('p', 'Reach Platinum rank', 5),
    item('g', 'Reach Gold rank', 20),
  ]);
  assert.deepEqual(more.ladders[0].tiers.map((t) => t.label), ['gold', 'platinum', 'diamond']);
});

test('a tier word never groups with a number, and currency amounts are not tiers', () => {
  assert.equal(buildLadders([item('a', 'Unlock 5 trophies', 10), item('b', 'Unlock gold trophies', 5)]).ladders.length, 0);
  assert.deepEqual(extractNumbers('Earn one million gold').values, [1000000]);
  assert.deepEqual(extractNumbers('Hold 1000 gold at once').values, [1000]);
});

test('Roman numerals: whole uppercase token, capped at X, ladder only when the rest of the key matches', () => {
  const { ladders } = buildLadders([
    item('p3', 'Reach Prestige III', 2),
    item('p2', 'Reach Prestige II', 3),
    item('p10', 'Reach Prestige X', 1),
  ]);
  assert.deepEqual(ladders[0].tiers.map((t) => t.label), ['II', 'III', 'X']);
  assert.deepEqual(ladders[0].edges.length, 2);
});

test('Roman numeral guards: the pronoun "I", "I\'m", sentence starts and lowercase/embedded tokens are not numerals', () => {
  assert.deepEqual(extractNumbers('I did it').values, []);
  assert.deepEqual(extractNumbers('Say that I\'m ready').values, []);
  assert.deepEqual(extractNumbers('Win. I choose you').values, []);
  assert.deepEqual(extractNumbers('Defeat the boss in Vietnam').values, []);
  assert.deepEqual(extractNumbers('Reach level xi').values, []);
  assert.deepEqual(extractNumbers('Reach Prestige XI').values, []); // capped at X
  assert.deepEqual(extractNumbers('Finish Part II').values, [2]);
});

test('Roman numeral and numeric thresholds never share a group', () => {
  assert.equal(buildLadders([item('a', 'Reach Prestige II', 3), item('b', 'Reach Prestige 5', 2)]).ladders.length, 0);
});

// ── contradiction tolerance ──────────────────────────────────────────────

test('rarity jitter under 0.5 points is not a contradiction; a real gap still is', () => {
  const jitter = buildLadders([item('a', 'Reach level 10', 45.1), item('b', 'Reach level 20', 45.2)]);
  assert.equal(jitter.contradictions.length, 0);
  const edge = buildLadders([item('a', 'Reach level 10', 45.0), item('b', 'Reach level 20', 45.5)]);
  assert.equal(edge.contradictions.length, 0, 'exactly 0.5 is still within tolerance');
  const real = buildLadders([item('a', 'Reach level 10', 45.0), item('b', 'Reach level 20', 46.0)]);
  assert.equal(real.contradictions.length, 1);
  // tolerance never changes the order, only whether it is reported
  assert.deepEqual(jitter.ladders[0].tiers.map((t) => t.label), ['10', '20']);
});

test('ladder stops are named by their real achievements, easiest tier first (not by the shared description)', () => {
  const g = buildDeterministicGuide([
    ach('New Kid', 'Reached 10th level.', 45),
    ach('Up and Comer', 'Reach 20th level.', 32),
    ach('The Boss', 'Reach 30th level.', 21),
  ]);
  assert.equal(g.nodes.length, 1);
  assert.equal(g.nodes[0].name, 'New Kid → Up and Comer → The Boss');
  const t = buildDeterministicGuide([ach('a', 'Finish 2nd run', 5), ach('b', 'Finish 3rd run', 4)]);
  assert.equal(t.nodes[0].name, 'a → b');
  // Red Dead Redemption 2 style: rank 50 listed before rank 10 in the input
  const rdr = buildDeterministicGuide([
    ach('Notorious', 'Red Dead Online: Reach Rank 50.', 4),
    ach('Getting Started', 'Red Dead Online: Reach Rank 10.', 20.9),
  ]);
  assert.equal(rdr.nodes.length, 1);
  assert.equal(rdr.nodes[0].name, 'Getting Started → Notorious');
});

test('ordinal suffixes are part of the number: 1st/2nd/3rd/10th share one ladder key', () => {
  assert.equal(extractNumbers('Reach 10th level').template, 'reach # level');
  assert.deepEqual(extractNumbers('Finish 2nd run').values, [2]);
  assert.equal(ladderKey('Finish 1st run').key, ladderKey('Finish 3rd run').key);
  assert.equal(ladderKey('Finish 2nd run').key, ladderKey('Finish 4th run').key);
  // plain words that merely start with those letters are untouched
  assert.deepEqual(extractNumbers('Defeat 3 thugs').values, [3]);
  assert.equal(extractNumbers('Defeat 3 thugs').template, 'defeat # thugs');
});
