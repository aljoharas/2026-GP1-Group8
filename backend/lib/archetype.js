// Player Archetypes — what Node returns from the Python service's /archetype.
//
// Python computes everything from the uid it is given and has no auth of its
// own, so routes take the uid only from the verified token (or from the path
// once friendship is checked). These helpers decide what each viewer sees:
//   ownArchetype    — the user themself: everything, scores always summing to 100
//   friendArchetype — an accepted friend: name and description only, never
//                     scores, reasons or anything else Python adds later

const RECOMMENDER_URL = process.env.RECOMMENDER_URL || 'http://localhost:8000';
const ARCHETYPE_TIMEOUT_MS = 10000;

// Whole-number percentages that add up to exactly `total`: floor every share,
// then hand the leftover points to the largest remainders (ties: the larger
// share, then the earlier entry). Same rule as the Python service.
function largestRemainder(values, total = 100) {
  const sum = values.reduce((a, b) => a + b, 0);
  if (!(sum > 0)) return values.map((_, i) => (i === 0 ? total : 0));
  const raw = values.map((v) => (v * total) / sum);
  const floors = raw.map(Math.floor);
  const order = raw
    .map((r, i) => i)
    .sort((a, b) => (raw[b] - floors[b]) - (raw[a] - floors[a]) || raw[b] - raw[a] || a - b);
  let left = total - floors.reduce((a, b) => a + b, 0);
  for (const i of order) {
    if (left <= 0) break;
    floors[i] += 1;
    left -= 1;
  }
  return floors;
}

// Highest first, re-rounded only if the parts don't already make exactly 100
function normaliseScores(scores) {
  const items = scores.map((s) => ({
    archetype: s.archetype,
    description: s.description,
    percent: Number(s.percent) || 0,
  }));
  const ints = items.every((s) => Number.isInteger(s.percent));
  if (!ints || items.reduce((a, s) => a + s.percent, 0) !== 100) {
    const fixed = largestRemainder(items.map((s) => s.percent));
    items.forEach((s, i) => { s.percent = fixed[i]; });
  }
  return items.sort((a, b) => b.percent - a.percent);
}

function notEnoughGames(body) {
  return {
    archetype: null,
    reason: 'not_enough_games',
    games_played: body.games_played ?? 0,
    min_games: body.min_games ?? 5,
  };
}

function ownArchetype(body) {
  if (!body.archetype) return notEnoughGames(body);
  const scores = normaliseScores(body.scores || []);
  return {
    archetype: body.archetype,
    description: body.description,
    scores,
    reasons: (body.reasons || []).slice(0, 2),
    games_played: body.games_played,
    model_version: body.model_version,
  };
}

// Built field by field on purpose: nothing from Python passes through by default
function friendArchetype(body) {
  if (!body || !body.archetype) return { archetype: null, description: null };
  return { archetype: body.archetype, description: body.description ?? null };
}

// GET {RECOMMENDER_URL}/archetype?uid=... → { status, body }; throws when the
// service is unreachable or times out.
async function fetchArchetype(uid) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), ARCHETYPE_TIMEOUT_MS);
  try {
    const pyRes = await fetch(
      `${RECOMMENDER_URL}/archetype?${new URLSearchParams({ uid })}`,
      { signal: controller.signal }
    );
    const body = await pyRes.json().catch(() => ({}));
    return { status: pyRes.status, body };
  } finally {
    clearTimeout(timeoutId);
  }
}

module.exports = { largestRemainder, normaliseScores, ownArchetype, friendArchetype, fetchArchetype };
