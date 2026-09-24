'use strict';

const { classifyAll } = require('./classify');
const { buildLadders } = require('./ladders');
const { orderEntries, PHASES } = require('./order');

const ALGO_VERSION = 'order-5';

function toItems(achievements) {
  const seen = new Set();
  return achievements.map((a, index) => {
    let id = String(a.externalId ?? index);
    if (seen.has(id)) id = `${id}~${index}`;
    seen.add(id);
    return {
      id,
      index,
      name: a.name || '',
      description: a.description || '',
      image: a.iconUrl || null,
      rarity: Number.isFinite(a.rarityPercent) ? a.rarityPercent : null,
      hidden: !!a.hidden,
      // Steam's internal key. Older cached payloads only have it as externalId.
      internalKey: a.internalKey ?? (a.source === 'steam' ? String(a.externalId) : null),
    };
  });
}

// A ladder stop is named after its real achievements, easiest tier first
// ("Getting Started → Notorious"), not the shared description. A tier holding
// several equal-value trophies is represented by its most common one.
function ladderName(ladder) {
  return ladder.tiers.map((t) => t.members[0].name).join(' → ');
}

function ladderKindIsNumeric(ladder) {
  return ladder.kinds[ladder.position] === 'num';
}

function pctStr(r) {
  return `${Number.isInteger(r) ? r : r.toFixed(1)}%`;
}

function trophyNode(item) {
  return {
    id: item.id,
    name: item.name,
    description: item.description || null,
    image: item.image,
    rarity: item.rarity,
    hidden: item.hidden,
    internalKey: item.internalKey,
    steps: [],
    confidence: null,
    categoryVote: null,
  };
}

// ctx: { overrides, schemaOrdered }. Pure and deterministic: same achievements + same
// ctx => byte-identical output. No LLM involvement.
function buildDeterministicGuide(achievements, ctx = {}) {
  const items = toItems(achievements);
  const byId = new Map(items.map((i) => [i.id, i]));

  const classification = classifyAll(items, ctx);
  for (const it of items) it.category = classification.results.get(it.id).category;

  const ladderResult = buildLadders(items);
  const entries = [];

  for (const ladder of ladderResult.ladders) {
    const firstTier = ladder.tiers[0];
    const first = firstTier.members[0];
    const rarities = firstTier.members.map((m) => m.rarity).filter((r) => r != null);
    entries.push({
      id: `ladder:${first.id}`,
      kind: 'ladder',
      phase: ladder.category,
      rarity: rarities.length ? Math.max(...rarities) : null,
      name: ladderName(ladder),
      dependsOn: [],
      ladder,
    });
  }
  for (const item of items) {
    if (ladderResult.memberIds.has(item.id)) continue;
    entries.push({ id: item.id, kind: 'trophy', phase: item.category, rarity: item.rarity, name: item.name, dependsOn: [], item });
  }

  const { ordered, log: orderingLog } = orderEntries(entries);
  const phaseName = new Map(PHASES.map((p) => [p.key, p.name]));

  const nodes = ordered.map((e, i) => {
    let node;
    if (e.kind === 'ladder') {
      const tiers = e.ladder.tiers.map((t, k) => ({
        value: ladderKindIsNumeric(e.ladder) && t.value !== Infinity ? t.value : t.label,
        label: t.label,
        dependsOn: k === 0 ? [] : e.ladder.tiers[k - 1].members.map((m) => m.id),
        trophies: t.members.map((m) => trophyNode(byId.get(m.id))),
      }));
      const lead = tiers[0].trophies[0];
      node = {
        id: e.id,
        name: e.name,
        description: lead.description,
        image: lead.image,
        rarity: e.rarity,
        hidden: tiers.some((t) => t.trophies.some((x) => x.hidden)),
        internalKey: null,
        steps: [],
        confidence: null,
        categoryVote: null,
        kind: 'ladder',
        tiers,
        reason:
          `Progression ladder: ${tiers.map((t) => t.label).join(' → ')}. Tiers must be earned in this order; ` +
          (e.rarity != null
            ? `placed by the first tier's earn rate (${pctStr(e.rarity)}).`
            : 'no earn-rate data, so placed after ladders/trophies with known rates in this phase.'),
      };
    } else {
      node = {
        ...trophyNode(e.item),
        kind: 'trophy',
        reason:
          e.rarity != null
            ? `${pctStr(e.rarity)} of players have earned this; placed by earn rate (most common first).`
            : 'No earn-rate data, so placed after trophies with known rates in this phase.',
      };
    }
    node.order = i + 1;
    node.phase = e.phase;
    node.phaseName = phaseName.get(e.phase);
    node.category = e.phase;
    node.percent = node.rarity;
    node.dependsOn = e.dependsOn;
    node.suspectedCategory = null;
    return node;
  });

  const phases = PHASES.map((p) => {
    const inPhase = nodes.filter((n) => n.phase === p.key);
    return { key: p.key, name: p.name, count: inPhase.length, startOrder: inPhase.length ? inPhase[0].order : null };
  }).filter((p) => p.count > 0);

  return {
    algoVersion: ALGO_VERSION,
    nodes,
    phases,
    logs: {
      ladders: ladderResult.log,
      contradictions: ladderResult.contradictions,
      classification: classification.log,
      tailStart: classification.tailStart,
      ordering: orderingLog,
    },
  };
}

// Merges LLM enrichment into an already-ordered guide. Only steps /
// confidence / categoryVote are copied, so order can never change here.
function applyEnrichment(guide, byId) {
  const nodes = guide.nodes.map((n) => {
    const copy = { ...n };
    const merge = (t) => {
      const e = byId.get(t.id);
      return e ? { ...t, steps: e.steps, confidence: e.confidence, categoryVote: e.categoryVote } : t;
    };

    if (n.kind === 'ladder') {
      copy.tiers = n.tiers.map((tier) => ({ ...tier, trophies: tier.trophies.map(merge) }));
      const enriched = copy.tiers.flatMap((t) => t.trophies).filter((t) => t.confidence);
      const lead = copy.tiers[0].trophies[0];
      copy.steps = lead.steps;
      copy.confidence = lead.confidence;
      copy.categoryVote = lead.categoryVote;
      const disagree = enriched.find((t) => t.categoryVote !== 'base');
      copy.suspectedCategory = n.category === 'base' && disagree ? disagree.categoryVote : null;
    } else {
      const m = merge(n);
      copy.steps = m.steps;
      copy.confidence = m.confidence;
      copy.categoryVote = m.categoryVote;
      copy.suspectedCategory = n.category === 'base' && m.categoryVote && m.categoryVote !== 'base' ? m.categoryVote : null;
    }
    return copy;
  });
  return { ...guide, nodes };
}

module.exports = { buildDeterministicGuide, applyEnrichment, toItems, ALGO_VERSION };
