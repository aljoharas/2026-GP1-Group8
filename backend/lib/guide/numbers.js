'use strict';

// Extracts ordered thresholds from an achievement description and builds the
// "ladder key": lowercase, every threshold -> '#', punctuation stripped,
// verb inflections normalized, whitespace collapsed. "Finish 50 contracts" and
// "Finish 100 contracts" both become "finish # contracts".
//
// A threshold is one of (kind):
//   num    digits or written numbers (one-twenty, fifty, hundred, thousand, million)
//   tier   bronze < silver < gold < platinum < diamond
//   roman  a whole-token uppercase Roman numeral I..X (heavily guarded)

const UNITS = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9,
  ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16,
  seventeen: 17, eighteen: 18, nineteen: 19,
};
const TENS = { twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };
const MULTS = { hundred: 100, thousand: 1000, million: 1000000 };

const TIER_WORDS = ['bronze', 'silver', 'gold', 'platinum', 'diamond'];
const ROMAN_VALUES = { I: 1, II: 2, III: 3, IV: 4, V: 5, VI: 6, VII: 7, VIII: 8, IX: 9, X: 10 };
const ROMAN_NAMES = Object.fromEntries(Object.entries(ROMAN_VALUES).map(([k, v]) => [v, k]));

// Explicit, small lookup -- NOT a stemmer. Whole-token matches only, applied
// during key normalization so "Reached 10th level" and "Reach 20th level" share
// a key. Extend by adding entries; anything not listed is left untouched.
const VERB_INFLECTIONS = {
  reached: 'reach', reaches: 'reach', reaching: 'reach',
  completed: 'complete', completes: 'complete', completing: 'complete',
  discovered: 'discover', discovers: 'discover', discovering: 'discover',
  won: 'win', wins: 'win', winning: 'win',
  earned: 'earn', earns: 'earn', earning: 'earn',
  collected: 'collect', collects: 'collect', collecting: 'collect',
  killed: 'kill', kills: 'kill', killing: 'kill',
  defeated: 'defeat', defeats: 'defeat', defeating: 'defeat',
  finished: 'finish', finishes: 'finish', finishing: 'finish',
  unlocked: 'unlock', unlocks: 'unlock', unlocking: 'unlock',
  crafted: 'craft', crafts: 'craft', crafting: 'craft',
  caught: 'catch', catches: 'catch', catching: 'catch',
  found: 'find', finds: 'find', finding: 'find',
  obtained: 'obtain', obtains: 'obtain', obtaining: 'obtain',
  acquired: 'acquire', acquires: 'acquire', acquiring: 'acquire',
  purchased: 'purchase', purchases: 'purchase', purchasing: 'purchase',
  spent: 'spend', spends: 'spend', spending: 'spend',
  destroyed: 'destroy', destroys: 'destroy', destroying: 'destroy',
  learned: 'learn', learns: 'learn', learning: 'learn',
};

const WORD_ALT = [...Object.keys(UNITS), ...Object.keys(TENS), ...Object.keys(MULTS)]
  .sort((a, b) => b.length - a.length)
  .join('|');
const WORD_RUN = `(?:${WORD_ALT})(?:[\\s-]+(?:and[\\s-]+)?(?:${WORD_ALT}))*`;

const DIGITS = '\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?|\\d{1,3}(?:\\.\\d{3})+(?!\\d)|\\d+(?:\\.\\d+)?';
const NUMBER_RE = new RegExp(
  `(?<![a-z0-9])(?:(?<digits>${DIGITS})(?<k>k\\b)?(?:(?:st|nd|rd|th)\\b)?` +
    `|(?<words>${WORD_RUN})\\b` +
    `|(?<tier>${TIER_WORDS.join('|')})\\b` +
    `|\\u0001(?<roman>\\d+)\\u0002)`,
  'g'
);

// Whole-token, UPPERCASE Roman numeral I..X only. Not at the start of the
// description or of a sentence, and never before an apostrophe -- so the
// pronoun "I" ("I'm", "...! I") is not read as 1.
const ROMAN_RE = /(?<![A-Za-z0-9'’])(X|IX|VIII|VII|VI|IV|V|III|II|I)(?![A-Za-z0-9'’])/g;

const ALL_RE = /\b(?:all|every)\b\s+(?:of\s+)?(?:the\s+)?/;

function markRomanNumerals(text) {
  return text.replace(ROMAN_RE, (m, tok, offset, whole) => {
    const before = whole.slice(0, offset);
    if (before.trim() === '' || /[.!?]\s*$/.test(before)) return m;
    return `\u0001${ROMAN_VALUES[tok]}\u0002`;
  });
}

function parseDigits(str) {
  if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(str)) return parseFloat(str.replace(/,/g, ''));
  if (/^\d{1,3}(\.\d{3})+$/.test(str)) return parseFloat(str.replace(/\./g, ''));
  return parseFloat(str);
}

// Evaluates a run of number words ("twenty five", "two hundred and fifty").
// Returns null when the run isn't a well-formed single number ("two three").
function evaluateWords(words) {
  let total = 0;
  let current = 0;
  let last = 'none';
  for (const w of words) {
    if (w === 'and') continue;
    if (w in UNITS) {
      if (last === 'unit') return null;
      if (last === 'tens' && UNITS[w] >= 10) return null;
      current += UNITS[w];
      last = 'unit';
    } else if (w in TENS) {
      if (last === 'unit' || last === 'tens') return null;
      current += TENS[w];
      last = 'tens';
    } else if (w === 'hundred') {
      current = (current || 1) * 100;
      last = 'mult';
    } else {
      total += (current || 1) * MULTS[w];
      current = 0;
      last = 'big';
    }
  }
  return total + current;
}

// "one" is usually a pronoun, not a quantity ("no one", "one of the bosses").
function isPronounOne(words, before, after) {
  if (words.length !== 1 || words[0] !== 'one') return false;
  return /\b(?:no|any|every|some|the)\s*$/.test(before) || /^\s+(?:of|another|who|that|else|thing)\b/.test(after);
}

function normalizeTemplate(str) {
  return str
    .replace(/['’`]/g, '')
    .replace(/[^\p{L}\p{N}#\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .split(' ')
    .map((tok) => VERB_INFLECTIONS[tok] ?? tok)
    .join(' ');
}

// Returns { template, values, kinds } -- values/kinds are parallel arrays in
// order of appearance.
function extractNumbers(text) {
  const src = markRomanNumerals(String(text || '')).toLowerCase();
  const values = [];
  const kinds = [];
  const push = (v, k) => {
    values.push(v);
    kinds.push(k);
  };

  const replaced = src.replace(NUMBER_RE, (...args) => {
    const match = args[0];
    const groups = args[args.length - 1];
    const offset = args[args.length - 3];
    const whole = args[args.length - 2];

    if (groups.digits) {
      push(parseDigits(groups.digits) * (groups.k ? 1000 : 1), 'num');
      return ' # ';
    }
    if (groups.tier) {
      // "1000 gold" / "one million gold" is a resource amount, not a rank.
      const before = whole.slice(0, offset);
      if (new RegExp(`(?:\\d|\\b(?:${WORD_ALT})|\\dk)[\\s-]*$`).test(before)) return match;
      push(TIER_WORDS.indexOf(groups.tier) + 1, 'tier');
      return ' # ';
    }
    if (groups.roman) {
      push(parseInt(groups.roman, 10), 'roman');
      return ' # ';
    }

    const words = groups.words.split(/[\s-]+/).filter(Boolean);
    const before = whole.slice(0, offset);
    const after = whole.slice(offset + match.length);
    if (isPronounOne(words, before, after)) return match;

    const value = evaluateWords(words);
    if (value !== null) {
      push(value, 'num');
      return ' # ';
    }
    return words
      .filter((w) => w !== 'and')
      .map((w) => {
        push(w in UNITS ? UNITS[w] : w in TENS ? TENS[w] : MULTS[w], 'num');
        return '#';
      })
      .join(' ');
  });

  return { template: normalizeTemplate(replaced), values, kinds };
}

// Ladder key + values + kinds. A description with no threshold but an
// "all"/"every" quantifier ("Collect all coins") is keyed as if the number were
// there, with value Infinity so it sorts last in its ladder.
function ladderKey(description) {
  const { template, values, kinds } = extractNumbers(description);
  if (values.length > 0) return { key: template, values, kinds };

  const lowered = String(description || '').toLowerCase();
  const replaced = lowered.replace(ALL_RE, '# ');
  if (replaced === lowered) return { key: template, values: [], kinds: [] };
  return { key: normalizeTemplate(replaced), values: [Infinity], kinds: ['num'] };
}

// Human label for a threshold value of a given kind.
function formatValue(v, kind = 'num') {
  if (v === Infinity) return 'all';
  if (kind === 'tier') return TIER_WORDS[v - 1] || String(v);
  if (kind === 'roman') return ROMAN_NAMES[v] || String(v);
  return Number.isInteger(v) ? v.toLocaleString('en-US') : String(v);
}

module.exports = { extractNumbers, ladderKey, normalizeTemplate, formatValue, VERB_INFLECTIONS };
