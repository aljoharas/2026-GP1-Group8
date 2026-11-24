# v3: real features only

This is analysis only, on branch `feature/archetype-v3-real`.

**Setup:**
- The 2,408 real Steam players, clustered on the five real features alone: games played, hours per game, top-game
  share, genre diversity and online share. No simulated feature.
- Same pipeline as v3: StandardScaler, `KMeans(n_init=20, random_state=42)`, k = 2..8.
- The features don't depend on a simulation seed, so stability is measured across 10 k-means restarts.
- The run is repeated with Dota 2 removed from every library (2,338 players still have ≥ 5 games).
- Genre diversity and online share come from catalogue-matched games only. 13 players have none, so those two
  features are imputed for them (14 with Dota 2 removed).

Script: `real_only.py`. Outputs: this folder (`*_k_sweep.csv`, `*_centres_k*.csv`, `*_resemblance_k*.csv`,
`real_only_choose_k.png`, `results.json`).

## Result: three clear-ish groups, and only The Main matches a served archetype

| k | 2 | **3** | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| silhouette, all players | 0.267 | **0.282** | 0.255 | 0.245 | 0.224 | 0.222 | 0.212 |
| silhouette, Dota 2 removed | 0.263 | **0.274** | 0.255 | 0.246 | 0.228 | 0.227 | 0.211 |

- **The best k is 3 in both runs, and no other k is within 0.01.**
- The structure is clearer than in the v3 main run with simulated features (best 0.215 at k = 4). It's in the same
  range as v2-core (0.26).
- Restart stability at k = 3 is 0.998 (all players) and 1.000 (Dota 2 removed).
- On the players both runs share, the two k = 3 solutions agree at ARI 0.82. At k = 6 they agree at 0.71.

**The k = 3 groups (all players):**

| Group | Share | ≈ games | ≈ hours/game | Top-game share | Genre div. | Online share | Nearest served archetype |
|---|---|---|---|---|---|---|---|
| **One online game** | 45% | 9 | 8.2 | 0.65 | 0.46 | **0.96** | The Main, **1.15 SD → resembles** |
| **Big, varied library** | 39% | **32** | 6.6 | 0.31 | **0.72** | 0.78 | Explorer, 2.34 SD, mutual nearest but too far |
| **Mostly offline** | 16% | 10 | 7.1 | 0.45 | 0.52 | **0.25** | Completionist, 1.77 SD, mutual nearest but too far |

With Dota 2 removed the three groups are almost the same: 44% / 40% / 17%, with nearly identical centres.

**What separates the groups is online share and library size, not hours per game.** The three groups' average hours
per game are within about 2h of each other.

## Which served archetypes the groups resemble

The test is the same as before, restricted to these five features: the matched group must be the archetype's mutual
nearest **and** closer than half the gap to the archetype's nearest other archetype. Distances are in the served
model's SD units.

| Served archetype | k = 3 | k = 6 | k = 6, Dota 2 removed |
|---|---|---|---|
| The Main | **1.15 → yes** | **1.00 → yes** | **0.99 → yes** |
| Devotee | no group | 1.89, mutual, too far | 1.91, mutual, too far |
| Explorer | 2.34, mutual, too far | 2.91, not mutual | 2.83, not mutual |
| Casual | no group | 1.94, mutual, too far | 2.02, not mutual |
| Competitor | no group | 2.52, not mutual | 1.72, mutual, too far |
| Completionist | 1.77, mutual, too far | 2.66, not mutual | 3.47, not mutual |

- **Only The Main resembles a group in every run.**
- **On these five features, Competitor and Completionist are nearly the same point.** Each sits only 1.4 SD from the
  other, so their half gaps are 0.70 SD. What tells them apart in 2.0.0 is completion and trophies, which real data
  doesn't have.
- **At k = 6 (all players) there's a split v2-core doesn't have:** long-session online players (about 30h per game)
  and a large group of mid-library online players (about 20 games). Both sit nearest Competitor, but neither
  resembles it. A separate offline group (online share 0.19) sits nearest Devotee, but isn't one-game dominated (top
  share 0.49).

## Reading

- **Without simulated features, real players do form groups.** There are 3 of them, more clearly separated than with
  completion, trophies and activity added:
  - one online game;
  - big, varied library;
  - mostly offline.
- **The simulated features blurred the grouping.** Adding them lowered the silhouette from 0.28 to 0.22 and pushed
  the best k to 4.
- **Of the six archetypes, only The Main is directly supported by real Steam data.** Explorer and the offline group
  point in recognisable directions, but don't meet the match test.
- **Completionist versus Competitor, and Casual, can't be judged from these features.** They're separated mainly by
  completion, trophies and activity, which Steam 200k doesn't record.
- **Removing Dota 2 doesn't change the conclusion.**
