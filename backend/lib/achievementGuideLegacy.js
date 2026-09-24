// achievementGuide.js
//
// Sends a game's achievement list to OpenAI and gets back a suggested
// completion order, one achievement per line with a short reason for its
// placement -- e.g. "First Steps — most players get this in the tutorial,
// so it goes first." The prompt mirrors trophy_order.py.

const OpenAI = require('openai');

let _client = null;
function getClient() {
  if (!_client) {
    if (!process.env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not set');
    _client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return _client;
}

function buildPrompt(achievements) {
  const lines = achievements.map((a) => {
    const name = a.name || a.display_name;
    const desc = a.description || '(hidden achievement, no description given)';
    const percent = a.percent;
    const percentStr = percent != null ? `${percent}% of players have earned it` : 'earn rate unknown';
    return `- ${name}: ${desc} (${percentStr})`;
  });

  const achievementsBlock = lines.join('\n');

  return (
    'You are given a list of achievements for a video game, each with a name, ' +
    'a description, and the percentage of players who have earned it. Use both ' +
    'signals together: the description may imply one achievement must be ' +
    'completed before another (a dependency), while the earn percentage is a ' +
    'real-world difficulty signal - a low percentage means the achievement is ' +
    'rare/hard even if its description sounds simple, and a high percentage ' +
    'means most players get it easily (often early or story-related).\n\n' +
    `Achievements:\n${achievementsBlock}\n\n` +
    'Return the achievement names in the order a player should try to ' +
    'complete them in - easier/more common ones generally first, harder/rarer ' +
    'ones later, and any clear dependency between achievements respected ' +
    'regardless of percentage - one per line, formatted exactly like this:\n' +
    'Achievement Name — one short sentence explaining why it goes at this point ' +
    'in the order, referencing the earn percentage or the dependency, whichever drove the decision\n\n' +
    'Keep each reason to one short sentence. Do not add numbering, bullet ' +
    'points, headers, or any text before the first line or after the last.'
  );
}

// Splits "Name — reason" into [name, reason]. The prompt asks for an em dash;
// fall back to " - " in case the model doesn't follow that exactly.
function splitNameReason(line) {
  let idx = line.indexOf('—');
  let sepLen = 1;
  if (idx === -1) {
    idx = line.indexOf(' - ');
    sepLen = 3;
  }
  if (idx === -1) return [line.trim(), ''];
  return [line.slice(0, idx).trim(), line.slice(idx + sepLen).trim()];
}

function parseGuideResponse(text, achievements) {
  const byName = new Map();
  for (const a of achievements) {
    const name = a.name || a.display_name;
    if (name) byName.set(name.trim().toLowerCase(), a);
  }

  const lines = text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  return lines.map((line, i) => {
    const [rawName, reason] = splitNameReason(line);
    const match = byName.get(rawName.trim().toLowerCase());
    return {
      order: i + 1,
      id: match?.id ?? null,
      name: match ? (match.name || match.display_name) : rawName,
      description: match?.description ?? null,
      image: match?.image ?? null,
      percent: match?.percent ?? null,
      reason,
    };
  });
}

async function generateAchievementGuide(achievements) {
  const client = getClient();
  const prompt = buildPrompt(achievements);

  const response = await client.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: 'You are a helpful game completion assistant.' },
      { role: 'user', content: prompt },
    ],
    temperature: 0.2,
  });

  /*const response = await client.responses.create({
    model: 'gpt-4o-mini',
    instructions: 'You are a helpful game completion assistant.',
    input: prompt,
    tools: [{ type: 'web_search' }],
    temperature: 0.2,
  });*/

  const text = response.output_text.trim();
  return parseGuideResponse(text, achievements);
}

module.exports = { buildPrompt, parseGuideResponse, generateAchievementGuide };
