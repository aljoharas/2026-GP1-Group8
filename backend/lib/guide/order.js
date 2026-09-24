'use strict';

const { compareByRarityName } = require('./ladders');

// Base-game phases first: a user may not own the DLC.
const PHASES = [
  { key: 'base', name: 'Base game' },
  { key: 'online', name: 'Online & multiplayer' },
  { key: 'dlc', name: 'DLC' },
];

// Fixed precedence inside a phase:
//   1. ladder position / 2. explicit dependency edges -> hard constraints
//      (an entry is only eligible once everything it dependsOn is placed)
//   3. rarity descending, nulls last  4. name  (5. id, so the order is total)
// Rarity is only ever a tiebreaker among eligible entries.
//
// entries: [{ id, phase, rarity, name, dependsOn: [entryId] }]
// Returns { ordered, log } -- ordered is grouped by phase in PHASES order.
function orderEntries(entries) {
  const log = [];
  const ordered = [];

  for (const phase of PHASES) {
    const inPhase = entries.filter((e) => e.phase === phase.key);
    const ids = new Set(inPhase.map((e) => e.id));
    const phaseIndex = new Map(PHASES.map((p, i) => [p.key, i]));

    const deps = new Map();
    for (const e of inPhase) {
      const kept = [];
      for (const d of e.dependsOn || []) {
        if (ids.has(d)) {
          kept.push(d);
        } else {
          const target = entries.find((x) => x.id === d);
          const note = target && phaseIndex.get(target.phase) > phaseIndex.get(phase.key)
            ? 'dependency sits in a later phase'
            : 'dependency not found in this phase';
          log.push({ type: 'edge-ignored', entry: e.id, dependsOn: d, note });
        }
      }
      deps.set(e.id, kept);
    }

    const placed = new Set();
    let remaining = [...inPhase];
    while (remaining.length > 0) {
      const ready = remaining.filter((e) => deps.get(e.id).every((d) => placed.has(d)));
      let pick;
      if (ready.length === 0) {
        // Cycle: place the best remaining entry anyway rather than dropping it.
        pick = [...remaining].sort(compareByRarityName)[0];
        log.push({ type: 'cycle-broken', entry: pick.id, note: 'dependency cycle; placed by rarity/name' });
      } else {
        pick = ready.sort(compareByRarityName)[0];
      }
      placed.add(pick.id);
      ordered.push(pick);
      remaining = remaining.filter((e) => e !== pick);
    }
  }

  return { ordered, log };
}

module.exports = { orderEntries, PHASES };
