# Simulation rules (generator v2): model card section

> Ready to merge into `archetype_model_card.md` **if** v2 replaces v1. Until then this describes
> the candidate model `archetype_model_v2.json` (2.0.0-candidate) only; the served model is v1.0.0.
> Code: `backend/recommender/archetype_sim_v2.py` (`RULES`). No rule or parameter was tuned on the clusters.

Generator v2 keeps v1's personas, persona parameters, mix share (25%), truncated library-size sampling and
per-persona hours quantile ranges. v1 drew every feature independently. v2 draws real games and makes
features depend on each other:

| Rule | What it does | Parameters | Source / logic |
|---|---|---|---|
| **A. Real games** | The persona's genre rule picks a genre and its P(online) picks online or offline. A catalogue game with that genre and flag is drawn, weighted by popularity, never twice per library. When no game is left, the online flag is relaxed first, then the genre (6.2% and 0.2% of draws). The game supplies genres, online flag, achievement count and typical length. | weight = distinct Steam 200k players | Steam Store Games (Kaggle, SteamSpy 2019), 1,843 drawable games; Steam 200k |
| **Game hours** | A game with ≥ 20 Steam 200k players takes its hours from its own Steam 200k distribution, at the persona's quantile u and capped at its own 99th percentile. Other games use the global distribution, as in v1. 56% of draws use the game's own distribution. | min players 20, cap p99 | Hours depend on the game's length. Drawing hours independently of the game made rule 1 inconsistent, e.g. 3h on a 40h RPG for a completionist. |
| **1. Finishing needs hours** | P(completed) = p · σ((ln r − ln r₀)/s), where r = hours ÷ typical length and p is the completion propensity. | r₀ = √0.75 ≈ 0.866, s = ln 3 / (2 ln 19) ≈ 0.187, which puts the factor at exactly 5% at r = 0.5 and 95% at r = 1.5 | Logic: you can't finish without playing through. Lengths are from HowLongToBeat (Bailey et al., arXiv 2205.15163). |
| **2. Trophies follow hours** | Trophies rise linearly to a share M of the list at the end of the main story (r = 1). The remaining 1 − M rises over the extra E × length hours, which count only on completed games. The result is multiplied by the per-game trophy Beta draw. 100% only when completed and r ≥ 1 + E. | E = 2, M = 0.6 | E: Bailey et al. report +8.6h after the main story for shorter games and +23.6h for full-price games, about 1.7–2.25× the main story. **M is a design parameter, to be checked against survey trophy rates.** |
| **3. Multiplayer-only has no ending** | When the game is online and has no Single-player category: P(completed) = 0.02, and status is playing or paused. | 0.02 | Logic: live-service games have no ending. The 2% covers campaigns the store categories don't show. |
| **4. Engagement** | Each player gets a hidden z ~ N(0,1). It shifts the hours quantile by +0.05·z and active months by +1·z (both clipped to the persona's range), and both propensities by +0.3·z on the logit scale. | 0.05, 1 month, 0.3 | Logic: engaged players play more and also pursue more goals. |
| **5. Trophy hunters** | A random 10% of players, from any persona. On every game with a list, their trophy fraction is at least a Beta(4,4) draw, even when the game isn't completed, but never 100% unless rule 2 allows it. | 10%, Beta(4,4) | Bailey et al.: trophy completion rates are bimodal, and the easy trophies are attributed to players chasing profile scores. |

**Implementation notes.**
- Every random number is drawn whether or not a rule is on (common random numbers), so a sensitivity variant
  differs from v2 only through the rule it changes.
- The trophy propensity is v1's per-game Beta draw.
- `typical_length_h` is SteamSpy's median playtime, clipped to 1–150h. It runs 24–33% below HowLongToBeat's
  main-story medians, because it includes players who quit early.

**Known limits.**
- The catalogue is a 2019 snapshot.
- 26% of Steam 200k plays (16% of hours) belong to titles that didn't match and are left out.
- Family and Educational have only 4 drawable games each.
- Pooled online share ↔ completion comes out positive (+0.10). This is confounded by per-game hours: holding
  hours fixed it is −0.11, and multiplayer-only games finish 2.1% of the time against 20.7% for offline games.
