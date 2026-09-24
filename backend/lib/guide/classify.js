'use strict';

// Deterministic category: 'base' | 'dlc' | 'online'. The LLM is never the
// source of truth here.
//
// KNOWN LIMITATION: Steam store metadata cannot reliably distinguish content
// DLC from cosmetic DLC (soundtracks and artbooks), so classification relies on
// achievement key patterns and rarity distribution, with a manual override
// table for the cases those miss.
// (Evidence, audited across 17 games: a DLC app never has achievements of its
// own -- DLC trophies live in the parent app's schema; `type` is wrong in both
// directions -- Hollow Knight's free content DLC is typed "music" while
// Undertale's soundtrack is typed "dlc"; `categories` and `pc_requirements` are
// inherited from the parent; and the parent's `dlc` array does not reliably
// list the real expansions -- Witcher 3's omits Hearts of Stone and Blood and
// Wine. A store-`dlc`-array "gate" therefore carries no signal and was removed.)
//
// Precedence: manual override (any category, including 'base') > DLC > online > base.
// Signals (most to least reliable):
//   a) Steam's internal achievement key (DLC1_, EP2_, MP_, COOP_ ...)
//   b) schema position + rarity cliff -- SUPPORTING ONLY: a keyword DLC guess
//      additionally requires it, and it is never decisive alone
//   c) keywords in displayName/description
// Known misses/false positives are fixed permanently in
// achievement_category_overrides, not by adding heuristics: e.g. Fallout: New
// Vegas keys are unprefixed (A01-A75) so its DLC is overridden, and Half-Life
// 2's EP1_/EP2_ keys match the DLC pattern but Episodes One/Two are separate
// Steam apps, so they are overridden back to 'base'.

const DLC_KEY_PATTERNS = [
  /^(?:dlc|ep|exp|expansion|addon|add_on)[\s_-]?\d*(?:[_\-.]|$)/i,
  /^dlc\d+/i,
  /(?:^|[_\-.])(?:dlc|expansion|addon)\d*(?:[_\-.]|$)/i,
];

const ONLINE_KEY_PATTERNS = [
  /^(?:mp|coop|co_op|pvp|online|multi|multiplayer|mult)[\s_-]?\d*(?:[_\-.]|$)/i,
  /(?:^|[_\-.])(?:mp|coop|co_op|pvp|online|multiplayer)\d*(?:[_\-.]|$)/i,
];

const ONLINE_KEYWORD_RE =
  /\b(?:online|multi-?player|co-?op|cooperative|versus|ranked|matchmaking|pvp|(?:other|another|fellow)\s+players?|other\s+people)\b/i;

const DLC_KEYWORD_RE = /\b(?:dlc|expansion|downloadable content|add-?on|season pass)\b/i;

function median(nums) {
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

// Steam lists achievements in the order they were added, so DLC tends to form
// a contiguous, much rarer tail. Returns the tail's start index or -1.
// Requires known rarity for the whole tail and a >=2x median drop.
function findTailStart(rarities) {
  const n = rarities.length;
  if (n < 10) return -1;
  let best = -1;
  let bestRatio = Infinity;
  const minTail = 1;
  const maxTail = Math.floor(n * 0.4);
  for (let len = minTail; len <= maxTail; len++) {
    const s = n - len;
    const tail = rarities.slice(s);
    const head = rarities.slice(0, s);
    if (tail.some((r) => r == null) || head.some((r) => r == null)) return -1;
    const ratio = median(tail) / (median(head) || 1);
    if (ratio < 0.5 && ratio < bestRatio) {
      bestRatio = ratio;
      best = s;
    }
  }
  return best;
}

function matchesAny(patterns, str) {
  return patterns.some((re) => re.test(str));
}

// items: [{ id, name, description, internalKey, rarity, index }] in schema order.
// ctx: { overrides: Map<key, category>, schemaOrdered }
function classifyAll(items, ctx = {}) {
  const overrides = ctx.overrides || new Map();
  // Tail/cliff only means something when the list is in Steam's schema order.
  const tailStart = ctx.schemaOrdered === false ? -1 : findTailStart(items.map((i) => i.rarity));

  const results = new Map();
  const log = [];

  for (const item of items) {
    const key = item.internalKey || '';
    const text = `${item.name || ''} ${item.description || ''}`;
    const signals = {
      dlcKey: !!key && matchesAny(DLC_KEY_PATTERNS, key),
      onlineKey: !!key && matchesAny(ONLINE_KEY_PATTERNS, key),
      dlcKeyword: DLC_KEYWORD_RE.test(text),
      onlineKeyword: ONLINE_KEYWORD_RE.test(text),
      tail: tailStart !== -1 && item.index >= tailStart,
    };

    let category = 'base';
    let decidedBy = 'none';

    const override = key ? overrides.get(key) : undefined;
    if (override) {
      category = override;
      decidedBy = 'override';
    } else {
      const dlcCandidate = signals.dlcKey || (signals.dlcKeyword && signals.tail);
      if (dlcCandidate) {
        category = 'dlc';
        decidedBy = signals.dlcKey ? 'key' : 'keyword+tail';
      } else if (signals.onlineKey) {
        category = 'online';
        decidedBy = 'key';
      } else if (signals.onlineKeyword) {
        category = 'online';
        decidedBy = 'keyword';
      }
    }

    results.set(item.id, { category, decidedBy, signals });
    if (category !== 'base') {
      log.push({
        id: item.id,
        name: item.name,
        key: key || null,
        category,
        decidedBy,
        signals: Object.keys(signals).filter((s) => signals[s]),
      });
    }
  }

  return { results, log, tailStart };
}

module.exports = { classifyAll, findTailStart, DLC_KEY_PATTERNS, ONLINE_KEY_PATTERNS };
