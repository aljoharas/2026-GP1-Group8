# Archetypes v3: real Steam players

This is an experiment on branch `feature/archetype-v3-real`. The served model (2.0.0), the model card, the endpoint,
the generators and `compute_features` are unchanged.

| What | Where |
|---|---|
| Notebook | `archetypes_v3_real.ipynb` |
| Code | `v3_real.py` |
| Tests | `test_v3_real.py`, 10 passing |
| Tables | `tables/` |
| Figures | `figures/` |
| All numbers | `results.json` |

Steam user IDs are replaced by sequential anonymous IDs (P0001…) in every output.

## Verdict

**1. Do real players form clear groups, and how many? No clear groups.**
- The best mean silhouette is **0.215, at k = 4**. Compare 0.26 for v2-core and 0.32 for v1.
- k = 4 is the best on every seed. k = 2 is within 0.01 on three seeds, and no other k comes close.
- So the data weakly prefers **4 broad groups**:

  | Group | Share of players |
  |---|---|
  | One online game | 39% |
  | Big, diverse library | 33% |
  | Long sessions, more completion | 15% |
  | Mostly offline | 13% |

- **At k = 6, silhouette drops to 0.185.** The six-way split is the least stable choice tested: restart ARI 0.93
  (minimum 0.85), and seed-to-seed ARI only 0.54–0.60.

**2. Do v2-core's six archetypes appear among real players? Only The Main clearly.**
- **The Main appears at both k = 4 and k = 6**, 0.97–1.02 SD from the served centre: one online game with most of the
  hours.
- **Devotee, Competitor and Explorer** have a mutual-nearest v3 group at k = 4, but 1.95–2.45 SD away. That's well
  beyond half the gap to their neighbours (about 1.2–1.3 SD), so they're similar directions, not the same groups.
- **Casual and Completionist don't appear.**
  - Casual is defined mostly by low activity, which the main run leaves out (Steam 200k has no dates).
  - Real players' completion is simulated, so a completionist group can only appear through simulated values.
- **Groups v2-core doesn't have:**
  - offline players whose hours aren't dominated by one game (online share 0.20–0.24, top game about 0.48);
  - an online "collector" with about 57 games.
- **The served model on real Steam players:**
  - It puts 34% in The Main and 30% in Competitor, against 9% and 18% in its training data.
  - It finds only 3% Completionists and 5% Devotees.
  - Its agreement with v3's own k = 6 clustering is low (ARI 0.34).

**3. Which results depend on the simulated parts? A lot.**
- **The simulated draws drive much of the grouping.** The real features are identical across seeds; only the
  simulated completion and trophies are re-drawn. Even so, seed-to-seed ARI is 0.54–0.60 at k = 6 and 0.62–0.69 at
  k = 4.
- **Simulated activity changes the answer most.** Adding it moves the best k to 2, puts k = 2–5 within 0.01, and gives
  ARI 0.52 against the main k = 6 fit, below seed noise.
- **Engagement strength matters.** At × 1.5, ARI is 0.64.
- **These don't change the preference for k = 4:** engagement 0 / × 0.5, propensity mean ± 0.1, the ≥ 80%-matched
  subset, and removing Dota 2. Only the activity variant moves it.
- **What is real and robust:** the One-game-online group (The Main) and the big-library vs small-library split.
- **What isn't:** anything about finishing or trophies, which is simulated by construction.

## 1. Real player base

| | |
|---|---|
| Users with ≥ 5 played titles | 2,436 |
| Users kept (≥ 5 games after merging titles that are the same store game) | **2,408** |
| Player × game rows | 57,210 |
| Games per user: median (p25–p75, p90) | 12 (7–25, 57) |
| Share of games matched to the catalogue | 71.8% |
| Share of hours matched | 79.5% |
| Users with < 50% of hours matched | 265 |
| Users with ≥ 80% of hours matched | 1,634 |

Cleaning is the same as before: play rows with hours > 0, summed per (user, title), capped at 908h (the 99th
percentile of all plays). Titles that map to the same store game ("X" and "X - Multiplayer") are merged per player.
That merge drops 28 users below 5 games.

## 2. Features

**Real features:**
- games played, hours per game and top-game share come from every game;
- genre diversity and online share come from matched games only.

`compute_features` computes everything, with one exception. **online_share is recomputed over matched games only**,
as specified. The app counts a game with no modes as offline instead. The difference is large: median 0.92 with
matched games only, against 0.74 under the app rule (mean difference +0.13). 13 players have no matched hours, so
their online share and genre diversity are imputed.

**Simulated features** (no personas):

| Propensity | Beta | Mean | Variance |
|---|---|---|---|
| Completion | Beta(1.66, 1.84) | 0.475 | 0.0554 |
| Trophy | Beta(1.39, 2.96) | 0.320 | 0.0406 |

- Each matches the mean and variance of the equal-weight mixture of the five persona Betas.
- Engagement is z = standardised ln(total real hours), adding +0.3·z to both logits.
- Rules 1–3 are as in v2-core (M = 0.6, E = 2, 2% for multiplayer-only).
- 17,108 games (30%) have no typical length and use the catalogue median of 3.8h for rule 1. 16,118 of them are
  unmatched, and those also have no trophy list.
- Every draw is a hash of (seed, player, game, purpose). Variants that change the population leave every other draw
  unchanged.

## 3. Plausibility (seed 42)

| Check | Count | Out of |
|---|---|---|
| Completed with r < 0.3, not multiplayer-only (rule 1) | **4** | 14,285 |
| Completed with r < 0.3, multiplayer-only (rule 3's flat 2%) | 63 | 2,826 |
| 100% trophies on an unfinished game | **0** | 23,816 |
| 100% trophies with r < 3 | **0** | 23,773 |
| Completed multiplayer-only games | 187 (2.1%) | 8,838 |

All checks pass.

**How real players differ from v2-core's simulated players** (medians):

| Feature | Real (v3) | v2-core |
|---|---|---|
| online share | **0.92** | 0.38 |
| genre diversity | **0.59** | 0.81 |
| ln(1+h) per game | **2.06** (≈ 7h) | 1.59 (≈ 4h) |
| ln games | **2.49** (≈ 12) | 2.08 (≈ 8) |
| activity (variant) | **4.06** | 2.42 |
| top-game share | 0.46 | 0.45 |
| completion (simulated in both) | 0.17 | 0.17 |
| trophy rate (simulated in both) | 0.11 | 0.10 |

Steam 200k players are far more online, play fewer genres, and own more games than the personas assume. Dota 2, TF2
and CS dominate.

**Correlations that differ most from v2-core** (Spearman):

| Pair | Real (v3) | v2-core |
|---|---|---|
| top-game share ↔ online | **+0.42** | −0.04 |
| online ↔ games | −0.34 | +0.04 |
| genre diversity ↔ online | −0.26 | +0.05 |
| completion ↔ trophy | +0.30 | +0.66 |

The full table is `tables/spearman_v3_v2core.csv`.

## 4. Clustering (main run, 7 features)

Silhouette (seeds 42, 0–4):

| k | 2 | 3 | **4** | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| mean | 0.205 | 0.202 | **0.215** | 0.180 | 0.185 | 0.171 | 0.161 |
| range | 0.203–0.208 | 0.196–0.206 | 0.212–0.219 | 0.176–0.182 | 0.178–0.189 | 0.165–0.177 | 0.151–0.174 |

k values within 0.01 of the best: **k = 4** on all seeds, plus **k = 2** on seeds 1, 3 and 4. No final k is picked.

| k | Restart ARI (mean / min) | Seed-to-seed ARI |
|---|---|---|
| 3 | 0.96 / 0.93 | 0.59–0.63 |
| 4 | 0.99 / 0.97 | 0.62–0.69 |
| 6 | 0.93 / 0.85 | 0.54–0.60 |

Centres for k = 3, 4 and 6 are in `tables/centres_k*.csv`. Figures: `figures/03_choose_k.png` and
`figures/02_distributions_v3_v2core.png`.

## 5. Compare with the served model

**Matching to the served archetypes** (7 shared features, served SD units). An archetype "appears" if its matched v3
group is its mutual nearest and lies closer than half the gap to its nearest other archetype. I set that criterion
before reading the result.

| Served archetype | k = 4: distance (mutual?) | k = 6: distance (mutual?) |
|---|---|---|
| The Main | **1.02 (yes) → appears** | **0.97 (yes) → appears** |
| Devotee | 1.95 (yes) | 1.84 (yes) |
| Competitor | 2.39 (yes) | 2.72 (no) |
| Explorer | 2.45 (yes) | 2.94 (no) |
| Casual | unmatched | 2.40 (no) |
| Completionist | unmatched | 3.02 (no) |

**Real Steam players assigned by the served 2.0.0 model** (activity variant, 8 features):

| Archetype | Players | Share | 2.0.0 training share |
|---|---|---|---|
| The Main | 815 | **33.8%** | 9.4% |
| Competitor | 714 | **29.7%** | 18.0% |
| Explorer | 446 | 18.5% | 17.8% |
| Casual | 245 | 10.2% | 26.2% |
| Devotee | 117 | 4.9% | 13.6% |
| Completionist | 71 | 2.9% | 14.9% |

ARI between this assignment and v3's own k = 6 clustering of the same players: **0.34**.

**Real Loadout users** (read-only), served 2.0.0 against the v3 k = 6 model (7 features, refitted scaler):

| User | Games | Served 2.0.0 | v3 k = 6 | Differs |
|---|---|---|---|---|
| user 1 | 12 | Competitor 35% | Competitor | no |
| user 2 | 9 | Competitor 44% | Competitor | no |
| user 3 | 10 | Competitor 48% | Completionist (near-tie: 2.44 vs 2.49 SD) | **yes** |
| user 4 | 5 | Completionist 81% | Competitor (6.9 SD from every v3 centre) | **yes** |
| user 5 | 12 | Completionist 75% | Completionist | no |

v3 group names are their Hungarian match to 2.0.0. User 4 lies far outside the real-player cloud, so their v3 label
isn't meaningful.

## 6. Sensitivity (seed 42)

Seed-to-seed noise at k = 6 is ARI **0.54–0.60**.

| Variant | Players | Best k | Within 0.01 | ARI vs main k = 6 |
|---|---|---|---|---|
| activity (8 features) | 2,408 | **2** | 2, 3, 4, 5 | **0.52** |
| engagement × 0 | 2,408 | 4 | 3, 4 | 0.84 |
| engagement × 0.5 | 2,408 | 4 | 4 | 0.89 |
| engagement × 1.5 | 2,408 | 4 | 4 | 0.64 |
| propensity mean +0.1 | 2,408 | 4 | 2, 4 | 0.69 |
| propensity mean −0.1 | 2,408 | 4 | 4 | 0.81 |
| users ≥ 80% hours matched | 1,634 | 4 | 4 | 0.57 |
| Dota 2 removed | 2,338 | 4 | 2, 3, 4 | 0.75 |

**Comparing variants with seed noise:**
- Variants reuse the same random draws (common random numbers), while seed noise re-draws everything. So a variant
  ARI above the noise range doesn't by itself mean "no effect".
- Below the noise range, the activity variant clearly changes the grouping.
- The ≥ 80%-matched subset sits within the noise range.

**On the ≥ 80% subset:** it uses the main run's features, not a re-simulation, so it tests the player set only.

## Caveats

- **Completion, trophies and activity are simulated even here.** v3 can't show whether real players have
  completionist or casual-activity groups.
- **Steam 200k is a PC sample dominated by free-to-play online games** (Dota 2 alone is 28% of hours). It is not
  Loadout's audience.
- **The archetype-match criterion (half the nearest-neighbour gap) is mine**, stated before looking, but not
  pre-registered by you.

**Follow-up, run:** clustering on the five real features alone (`real_only/report.md`) gives a clearer best k = 3
(silhouette 0.28): one online game, a big varied library, and mostly offline players. Only The Main matches a
served archetype.
