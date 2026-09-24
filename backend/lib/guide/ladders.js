'use strict';

const { ladderKey, formatValue } = require('./numbers');

// Description contains a comparator => the SMALLER number is the harder tier
// ("under 10 min" is easier than "under 5 min"), so the ladder sorts descending.
const COMPARATOR_RE =
  /\b(?:under|less than|fewer than|within|below|faster than|quicker than|at most|no more than)\b/i;

// Rarity gaps below this many percentage points are rounding/sampling noise,
// not a real disagreement with the ladder order (45.1% vs 45.2%).
const RARITY_TOLERANCE = 0.5;

function cmpStr(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

// Rarity descending (common first), nulls last (never coerced to 0), then
// name, then id -- a total order, so results never depend on input order.
function compareByRarityName(a, b) {
  const ra = a.rarity;
  const rb = b.rarity;
  if (ra == null && rb != null) return 1;
  if (ra != null && rb == null) return -1;
  if (ra != null && rb != null && ra !== rb) return rb - ra;
  return (
    cmpStr(String(a.name).toLowerCase(), String(b.name).toLowerCase()) ||
    cmpStr(String(a.name), String(b.name)) ||
    cmpStr(String(a.id), String(b.id))
  );
}

// Ascending by value, Infinity ("all"/"every") always last; inverted ladders
// sort descending (larger threshold = easier = first) but still keep "all" last.
function compareTierValues(inverted) {
  return (a, b) => {
    if (a === Infinity && b === Infinity) return 0;
    if (a === Infinity) return 1;
    if (b === Infinity) return -1;
    return inverted ? b - a : a - b;
  };
}

const fmtValue = formatValue;

function tierBestRarity(tier) {
  const rs = tier.members.map((m) => m.rarity).filter((r) => r != null);
  return rs.length ? Math.max(...rs) : null;
}

// items: [{ id, name, description, category, rarity }]
// Trophies only group when they share a category, so a ladder never spans
// base-game and DLC/online phases.
//
// Returns { ladders, memberIds, log, contradictions }.
function buildLadders(items) {
  const groups = new Map();
  for (const item of items) {
    if (!item.description) continue;
    const { key, values, kinds } = ladderKey(item.description);
    const hashCount = (key.match(/#/g) || []).length;
    if (hashCount === 0 || values.length !== hashCount) continue;
    if (!/\p{L}{2,}/u.test(key)) continue; // "#" alone is too generic to be a ladder
    // kinds are part of the group key: a tier word ("gold") never groups with a number.
    const gk = `${item.category}\u0000${kinds.join(',')}\u0000${key}`;
    if (!groups.has(gk)) groups.set(gk, { key, category: item.category, members: [] });
    groups.get(gk).members.push({ ...item, values, kinds });
  }

  const ladders = [];
  const log = [];
  const contradictions = [];
  const memberIds = new Set();

  const sortedGroups = [...groups.values()].sort(
    (a, b) => cmpStr(a.category, b.category) || cmpStr(a.key, b.key)
  );

  for (const group of sortedGroups) {
    if (group.members.length < 2) continue;

    const width = group.members[0].values.length;
    const varying = [];
    for (let j = 0; j < width; j++) {
      const distinct = new Set(group.members.map((m) => m.values[j]));
      if (distinct.size > 1) varying.push(j);
    }

    const base = {
      key: group.key,
      category: group.category,
      members: group.members.map((m) => ({ id: m.id, name: m.name, numbers: m.values.map((v, j) => fmtValue(v, m.kinds[j])), rarity: m.rarity })),
    };

    if (varying.length === 0) {
      log.push({ ...base, verdict: 'collision', note: 'identical numbers -- key collision, grouped but not chained' });
      continue;
    }
    if (varying.length > 1) {
      log.push({ ...base, verdict: 'skipped', note: 'more than one number varies -- ambiguous, not chained' });
      continue;
    }

    const pos = varying[0];
    const kinds = group.members[0].kinds;
    const inverted = COMPARATOR_RE.test(group.members[0].description);
    const cmp = compareTierValues(inverted);

    const byValue = new Map();
    for (const m of group.members) {
      const v = m.values[pos];
      if (!byValue.has(v)) byValue.set(v, []);
      byValue.get(v).push(m);
    }
    const tiers = [...byValue.keys()].sort(cmp).map((value) => ({
      value,
      label: fmtValue(value, kinds[pos]),
      members: byValue.get(value).sort(compareByRarityName),
    }));

    const edges = [];
    for (let k = 1; k < tiers.length; k++) {
      for (const lower of tiers[k - 1].members) {
        for (const higher of tiers[k].members) edges.push({ from: lower.id, to: higher.id });
      }
    }

    const found = [];
    for (let k = 1; k < tiers.length; k++) {
      const prev = tierBestRarity(tiers[k - 1]);
      const next = tierBestRarity(tiers[k]);
      if (prev != null && next != null && next - prev > RARITY_TOLERANCE) {
        const c = {
          ladder: group.key,
          lower: tiers[k - 1].label,
          higher: tiers[k].label,
          lowerRarity: prev,
          higherRarity: next,
          resolution: 'ladder order wins',
        };
        contradictions.push(c);
        found.push(c);
      }
    }

    ladders.push({ key: group.key, category: group.category, inverted, position: pos, kinds, tiers, edges });
    for (const m of group.members) memberIds.add(m.id);
    log.push({
      ...base,
      verdict: 'ladder',
      direction: inverted ? 'descending (comparator: smaller = harder)' : 'ascending',
      order: tiers.map((t) => t.label),
      contradictions: found.length,
    });
  }

  return { ladders, memberIds, log, contradictions };
}

function formatLadderLog(entry) {
  const members = entry.members
    .map((m) => `${m.name} [${m.numbers.join(',')}]${m.rarity != null ? ` ${m.rarity}%` : ''}`)
    .join(' | ');
  const head = `[${entry.verdict}] key="${entry.key}" category=${entry.category}`;
  if (entry.verdict === 'ladder') {
    return `${head} order=${entry.order.join(' -> ')} dir=${entry.direction}${entry.contradictions ? ` contradictions=${entry.contradictions}` : ''}\n      ${members}`;
  }
  return `${head} (${entry.note})\n      ${members}`;
}

module.exports = { buildLadders, formatLadderLog, compareByRarityName, fmtValue, COMPARATOR_RE, RARITY_TOLERANCE };
