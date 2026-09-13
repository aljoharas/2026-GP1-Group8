for (const id of sampleIds) {
  const r = await fetch(`https://api.rawg.io/api/games/${id}/achievements?key=${KEY}`);
  const { count, results = [] } = await r.json();
  console.log(id, count,
    results.filter(a => a.description?.trim()).length,  // usable descriptions
    results.filter(a => a.percent != null).length);     // rarity available
}