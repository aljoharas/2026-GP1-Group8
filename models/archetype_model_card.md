# Player Archetypes: model card

| | |
|---|---|
| Model | K-Means, k = 6, frozen as JSON (`models/archetype_model.json`) |
| Version | **2.0.0** (seed 42). Replaces 1.0.0, which is kept as `models/archetype_model_v1.json` for rollback. |
| Trained by | `notebooks/v2_core_final.py --write-model`. The analysis is in `notebooks/archetypes_training_v2.ipynb` and the `notebooks/sim_v2*` reports. |
| Served by | Python service, `GET /archetype?uid=...`, behind Node `GET /users/me/archetype` |
| Status | Trained on simulated players only. **Not yet validated on real players.** |

## What it does

Each Loadout user with at least 5 games in their manual logs gets one of six playstyle archetypes, plus a match %
for every archetype. The service:

1. computes the user's 8 features;
2. fills a missing trophy rate or genre diversity with the training mean;
3. scales the features with the saved scaler;
4. measures the distance to each cluster centre.

The nearest centre is the archetype. The match % is a softmax over the negative distances (temperature 0.75; see
[Match scores](#match-scores)).

Since 2.0.0 the response also carries:

- **`family`**: the top archetype's family (see [Families and blends](#families-and-blends)).
- **`blend`**: `{"primary", "secondary"}` when the top two archetypes are within 10 percentage points **and** in the
  same family, otherwise `null`. The app can then show, for example, "Competitor, with a Completionist streak".

The model is trained **once, offline**. The service only loads the JSON; it never retrains.

## The six archetypes

Centres are in original units. Activity is ln(1 + hours per active month); games is ln(games played).

| Archetype | Family | Shown in the app | Completion | Trophies | Genre div. | ln(1+h)/game | Top game | Activity | Online | Games | Training share |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Completionist | Committed | You see more of your games through than most players, and pick up trophies on the way. | **0.56** | **0.38** | 0.83 | 2.20 | 0.43 | 2.61 | 0.30 | 2.08 (≈ 8) | 14.9% |
| Competitor | Committed | Online, competitive, and in it for the long sessions. | 0.28 | 0.17 | 0.83 | **2.50** | 0.43 | 3.10 | **0.77** | 2.14 (≈ 8) | 18.0% |
| Explorer | Light | Always trying something new, across lots of genres. | 0.12 | 0.08 | **0.93** | 1.20 | **0.27** | 2.20 | 0.35 | **2.92 (≈ 18)** | 17.9% |
| Casual | Light | You play when life gives you time. | 0.08 | 0.07 | 0.81 | **1.07** | 0.46 | **1.52** | 0.34 | 1.86 (≈ 6) | 26.2% |
| Devotee | One-game | One game you keep coming back to, over and over. | 0.16 | 0.09 | **0.53** | 1.74 | **0.89** | **3.47** | **0.03** | 1.92 (≈ 7) | 13.6% |
| The Main | One-game | One online game has most of your hours. | 0.13 | 0.11 | **0.53** | 1.89 | **0.87** | **3.51** | **0.95** | 1.92 (≈ 7) | 9.5% |

**Names:**
- The six clusters were matched to 1.0.0's archetypes by centre distance (Hungarian matching, in 1.0.0's SD units),
  and the team confirmed the names.
- Match distances, in 1.0.0 SD units:

  | Archetype | Distance |
  |---|---|
  | Competitor | 1.13 |
  | Explorer | 1.58 |
  | Casual | 1.77 |
  | Devotee | 1.78 |
  | Completionist | 1.84 |
  | The Main | 1.88 |

- Five descriptions are unchanged from 1.0.0.
- **Completionist was reworded.** Its centre finishes 56% of games and unlocks 38% of trophies. That's the highest of
  the six by far, but it doesn't fit "finishes what it starts". Its centre is also slightly closer to 1.0.0's
  Competitor (1.67 SD) than to 1.0.0's Completionist (1.84 SD), so the description is now relative.

**Overall levels.** Completion and trophy rates are lower everywhere than in 1.0.0, because v2's simulation only
lets a game be finished, or its trophies be earned, with enough hours (see [Simulation rules](#simulation-rules)).

## Families and blends

| Family | Archetypes | What they share |
|---|---|---|
| **Light** | Casual, Explorer | Few hours per game, low completion; they differ in library size and genre range |
| **Committed** | Competitor, Completionist | Most hours per game and the highest completion and trophy rates; they differ in online share and finishing |
| **One-game** | Devotee, The Main | One game has about 90% of the hours; they differ only in whether that game is online |

A user between two archetypes of the same family is described better by a blend than by a near-coin-flip label.
So when the top two archetypes are within 10 points and share a family, the API returns `blend`. Across families
it never does, because those mixes aren't one coherent style.

Models without a `family` field (1.0.0) always return `family: null` and `blend: null`.

## Features

All features are computed by one shared function, `archetype_features.compute_features`, for simulated players,
the notebook and the API alike. Its input is one dict per game (all of a game's logs combined). A user with fewer
than 5 games gets no archetype. **Unchanged from 1.0.0.**

| # | Feature | Definition |
|---|---|---|
| 1 | completion_rate | games with at least one `completed` log ÷ games played |
| 2 | trophy_rate | Σ min(unlocked, available) ÷ Σ available, over games with an achievement count (see below). With none, it's missing and imputed with the training mean (**0.145**). |
| 3 | genre_diversity | Shannon entropy of genre shares ÷ ln 10, capped at 1. A game's hours are split equally over its genres (every game weighs 1 if total hours = 0), and games without genres are skipped. With none, it's missing and imputed (**0.774**). |
| 4 | log_hours_per_game | mean of ln(1 + hours) over games with hours > 0 |
| 5 | top_game_share | hours of the most-played game ÷ total hours (0 if no hours) |
| 6 | log_activity | ln(1 + total hours ÷ distinct active months) |
| 7 | online_share | hours in online games ÷ total hours. A game is online when its `game_modes` contains "multiplayer", "battle royale" or "co-operative" (case-insensitive). |
| 8 | log_games_played | ln(games played) |

**Real users' data:** only `library_entries` rows with `source = 'manual'` and a `logged_at` count; Steam rows are
ignored. Each row is one log, and `hours_played` NULL counts as 0.

**Trophies for real users:** unlocked = distinct ticked achievement names per game, across all its logs (case and
surrounding whitespace ignored). A game counts toward trophy_rate only if it has a RAWG count or an
achievements-table list:
- RAWG `games.achievements_count` > 0 → ticked ÷ count
- no count, list size > 0 → ticked ÷ max(list size, ticked)
- no count and no list → the game is left out, even if names were ticked

Each game's rate is capped at 1.

## Training data

**Simulated players, calibrated on real data.** There is no labelled real-world dataset of playstyles, so the
population is generated from five designed personas. Generator v2 (`archetype_sim_v2.py`, called as
`generate_players(version=2)`) draws **real games** and makes the features depend on each other. The v1 generator
still exists, unchanged, as `version=1`.

**Data sources** (neither is committed; both go in `data/`):
- **Steam 200k:** per-game hours and library sizes. Play rows with hours > 0 are summed per (user, game), hours are
  capped at the 99th percentile (908h), and users with ≥ 5 played games are kept.
- **Steam Store Games** (Kaggle, nikdavis; SteamSpy 2019, 27,075 games): the game catalogue
  (`archetype_catalogue.py`). Each game gets:
  - RAWG genres. 10 Steam genres map directly and Education becomes Educational. The 8 RAWG genres that aren't
    Steam genres come from SteamSpy tags.
  - An online flag.
  - A multiplayer-only flag (online, and no Single-player category).
  - An achievement count.
  - A typical length: median playtime clipped to 1–150h.
  - Popularity: distinct Steam 200k players. 2,460 of 3,600 played titles match (74% of plays, 84% of hours).
- **Drawable games:** 1,843, the ones with both a length and at least one Steam 200k player.
- **Lengths vs HowLongToBeat:** the median typical length is 3.8h (7.1h weighted by popularity). That's 24–33% below
  HowLongToBeat's main-story medians (5h for shorter games, 10.5h for full-price games; Bailey et al.,
  arXiv 2205.15163), because SteamSpy's median includes players who quit early.

**Population:**
- 500 players per persona plus 833 mixed players (25% of 3,333). The sample grew from 1.0.0's 100 per persona to
  reduce Monte Carlo noise in k selection, not to tune any result.
- A mixed player blends two random personas: each game comes from persona A with probability w ~ U(0.3, 0.7),
  else from B.

### Persona parameters

These are unchanged from 1.0.0:

| Persona | Library | Hours quantiles | P(completed) | Trophy fraction | Favourite genres | P(online) | Active months |
|---|---|---|---|---|---|---|---|
| completionist | 5–15 | 0.25–0.90 | Beta(8, 2) | Beta(6, 4) | 3–4, 70% | Beta(2, 5) | 6–12 |
| explorer | 10–40 | 0.05–0.60 | Beta(2.5, 4) | Beta(2, 6) | 12, 100% | Beta(2, 5) | 6–12 |
| devotee | 5–10 | one game 0.95–0.995, rest 0.05–0.50 | Beta(3, 4) | Beta(2, 6) | 1–2, 85% | Beta(2, 5) | 6–12 |
| competitor | 5–15 | 0.40–0.95 | Beta(3, 4) | Beta(2, 6) | 3–4, 70% | Beta(8, 2) | 6–12 |
| casual | 5–8 | 0.05–0.50 | Beta(2, 4) | Beta(2, 6) | 3–4, 70% | Beta(2, 5) | 2–5 |

How to read them:
- Library sizes are sampled from Steam users already inside the range (truncated sampling).
- Hours quantiles index a Steam hours distribution.
- P(completed) is the player's completion propensity p.
- The trophy Beta is drawn per game and acts as the trophy propensity.

### Simulation rules

No rule or parameter was tuned on the clusters. All are in `archetype_sim_v2.RULES`.

| Rule | What it does | Parameters | Source / logic |
|---|---|---|---|
| **A. Real games** | The persona's genre rule picks a genre and its P(online) picks online or offline. A game with that genre and flag is drawn, weighted by popularity, never twice per library. When no game is left, the online flag is relaxed first (6.2% of draws), then the genre (0.5%). | weight = Steam 200k players | Steam Store Games + Steam 200k |
| **Game hours** | A game with ≥ 20 Steam 200k players reads its hours from its *own* Steam 200k distribution at the persona's quantile u, capped at its own 99th percentile. Other games use the global distribution. 55% of draws use the game's own distribution. | ≥ 20 players, cap p99 | Hours depend on the game's length. Drawing them independently of the game made rule 1 inconsistent, e.g. 3h on a 40h RPG for a completionist. |
| **1. Finishing needs hours** | P(completed) = p · σ((ln r − ln r₀)/s), where r = hours ÷ typical length. | r₀ = √0.75 ≈ 0.87, s ≈ 0.187, so the factor is exactly 5% at r = 0.5 and 95% at r = 1.5 | Logic: you can't finish a game without playing it through. Lengths are from HowLongToBeat (Bailey et al.). |
| **2. Trophies follow hours** | The share of the list rises linearly to M by the end of the main story (r = 1). The remaining 1 − M rises over the extra E × length hours, which count only on completed games. The result is multiplied by the trophy propensity. 100% only when completed and r ≥ 1 + E. | E = 2, M = 0.6 | E: Bailey et al. report +8.6h after the main story for shorter games and +23.6h for full-price games, about 1.7–2.25× the main story. **M is a design parameter, to be checked against survey trophy rates.** |
| **3. Multiplayer-only has no ending** | P(completed) = 0.02, and status is playing or paused. | 0.02 | Logic: live-service games have no ending. The 2% covers campaigns the store categories don't show. |
| **4. Engagement** | Each player gets a hidden z ~ N(0, 1). It shifts the hours quantile by +0.05·z and active months by +1·z (both clipped to the persona's range), and the completion and trophy propensities by +0.3·z on the logit scale. | 0.05, 1 month, 0.3 | Logic: engaged players play more and also pursue more goals. |
| ~~5. Trophy hunters~~ | **Excluded from 2.0.0.** | | See below. |

**Why rule 5 is excluded.** Rule 5 made a random 10% of players trophy hunters: on every game with a list, their
trophy fraction was at least a Beta(4,4) draw. The bimodal trophy-completion pattern in Bailey et al. motivates
the idea, but **the 10% share has no empirical source**. With the rule on, those players formed their own 7th
cluster, so the archetypes depended on a guessed number. Trophy hunters will be re-added only if the survey supports
them, with the share taken from survey data.

### Plausibility checks (training population, 3,333 players, 32,888 games)

| Check | Result |
|---|---|
| Completed with r < 0.3 | 29 of 10,250. 27 are multiplayer-only games (rule 3's flat 2%), and **2 of 9,095** come from rule 1. |
| 100% trophies on an unfinished game | **0** of 18,180 |
| 100% trophies with r < 1 + E | **0** of 19,472 |
| Completed multiplayer-only games | 2.36% (77 of 3,268), within ±2 SE of 2% (1.51–2.49%) |
| Full trophy sets overall | 5 of 22,643 games with a list |

**Expected correlation signs** (Spearman, between players):

| Pair | Expected | Value |
|---|---|---|
| hours per game ↔ trophy rate | + | +0.64 ✓ |
| activity ↔ trophy rate | + | +0.31 ✓ |
| completion ↔ trophy rate | + | +0.66 ✓ |
| online share ↔ completion | − | **+0.02** pooled (see below) |

**Online share ↔ completion.** The pooled value is +0.02. Holding hours per game fixed (partial correlation) it is
**−0.19**, and within every persona it is negative (−0.01 to −0.19). At the game level:

| Game kind | Share completed |
|---|---|
| Multiplayer-only | 2.4% |
| Offline | 21.7% |
| Online with single-player | 22.1% |

The pooled sign is confounded by per-game hours. Competitors have both the highest online share and the longest
per-game hours, and rule 1 lets long play finish more often. No rule was added for online games that have a
single-player mode.

**Mean completion and trophy rate per persona:**

| Persona | Completion | Trophy rate |
|---|---|---|
| completionist | 0.49 | 0.36 |
| competitor | 0.29 | 0.15 |
| devotee | 0.13 | 0.08 |
| explorer | 0.10 | 0.08 |
| casual | 0.05 | 0.06 |

## Training and choosing k

Features → impute missing values with the training mean → StandardScaler → K-Means
(`n_init=20, random_state=42`) for k = 2..8.

**k rule** (pre-set, unchanged since 1.0.0): if the best silhouettes are within 0.01 of each other, choose the largest
of those k where every cluster (a) differs from every other by ≥ 0.5 SD in at least one feature and (b) holds ≥ 5% of
players; otherwise choose the highest silhouette.

**Silhouette on seed 42:**

| k | 2 | 3 | 4 | 5 | **6** | 7 | 8 |
|---|---|---|---|---|---|---|---|
| silhouette | 0.228 | **0.273** | 0.241 | 0.250 | **0.260** | 0.237 | 0.226 |

**k decision: k = 6, adopted by majority across seeds after seeing the seed-42 result.**
- Applied mechanically, the pre-set rule picked k = 6 on generator seeds 0–4.
- On seed 42 it picked k = 3: there k = 6 trails k = 3 by 0.0126, just outside the 0.01 window, so it wasn't a
  candidate.
- The rule did **not** choose k = 6 on the training seed. It's a judgement made after seeing that result.

Silhouette gap between k = 3 and k = 6, per seed:

| Seed | 42 | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|
| k = 3 − k = 6 | 0.0126 | 0.0085 | 0.0095 | 0.0030 | 0.0088 | 0.0041 |

**Larger-sample results** (500 per persona, seed 42 plus generator seeds 0–4):

| Generator | Rule k per seed (42; 0–4) | Seed-to-seed ARI |
|---|---|---|
| v1 (1.0.0's generator) | 6; 6, 6, 6, 6, 6 | 0.97–0.99 |
| v2 with rule 5 | 7; 7, 7, 7, 7, 6 (the 7th cluster is the trophy hunters) | 0.74–0.96 |
| **v2-core (rules 1–4; this model)** | **3; 6, 6, 6, 6, 6** | 0.91–0.97 at k = 6 |

At 100 per persona, v2's rule k varied between 3 and 7 across seeds. The larger sample settled v1 completely and
v2-core on five of six seeds.

## Quality

- **Silhouette 0.26** (1.0.0: 0.32). The overlap is larger than in v1. Once features depend on each other, players
  sit closer together. This is consistent with playstyle being a continuum.
- **Stability:** across 10 k-means restarts, the mean pairwise ARI is 0.999 (minimum 0.998). The k = 6 fits on seeds
  0–4 agree with this model at ARI 0.91–0.97. This shows the *pipeline* is stable, not that the archetypes are valid.
- **Sanity check:** the ARI between clusters and the generator's persona labels (pure players) is 0.58 (1.0.0: 0.85).
  This is a sanity check only: the personas are our own design.
- **Round trip:** loading the JSON alone and assigning each of the 3,333 training players to the nearest centre
  reproduces the fitted labels exactly.
- **Real users** (5 users with ≥ 5 manual games, 2026-11-17): none changes archetype between 1.0.0 and 2.0.0.

## Match scores

match % = softmax(−distance ÷ T) over the six centres, with distances in StandardScaler units. The result is shown
as whole-number percentages that add up to exactly 100 (largest-remainder rounding). **T = 0.75**, stored in the
model JSON as `scoring.temperature`.

Top match % for each temperature. Simulated = the 3,333 training players; real = the 5 users with ≥ 5 manual games
on 2026-11-17.

| T | Simulated pure (median, 10th–90th pct) | Simulated mixed (median) | Simulated at ≥ 90% | Real users |
|---|---|---|---|---|
| 0.5 | 88% (55–97) | 78% | 41% | 42–94% |
| 0.6 | 81% (50–94) | 70% | 23% | 39–89% |
| **0.75** | **72% (45–88)** | **61%** | **5.3%** | **35–81%** |
| 1.0 | 59% (38–76) | 50% | 0% | 31–68% |

Why 0.75 (the same criteria as for 1.0.0):
- **It doesn't overclaim.** 5.3% of players see a 90%+ match, close to 1.0.0's 6%. T = 0.6 would give 23% and
  T = 0.5 41%, which contradicts a silhouette of 0.26.
- **Mixed players stay visibly lower** than pure ones: 61% against 72%.
- **T = 1.0 is too flat:** real users' top type would show 31–68%.
- **Leads are smaller than in 1.0.0** (pure median 72% vs 79%; real users 35–81% vs 48–64%), because the clusters
  overlap more (silhouette 0.26 vs 0.32).
  - The real Competitors show 35–48%, so their mix matters more. That's partly why a same-family blend is now
    returned.
  - One real user (Competitor 35% / Completionist 25%) gets that blend.

The temperature only changes the displayed percentages, never the assigned archetype.

## Rollback

`models/archetype_model_v1.json` is the unchanged 1.0.0 model. Rolling back is a file swap: copy it over
`models/archetype_model.json` (or set `ARCHETYPE_MODEL_PATH`) and restart the service.

The code serves both versions. With 1.0.0, `family` and `blend` are `null` and everything else is as before. This
was checked on 2026-11-17 by serving both files locally.

## Changes from 1.0.0

- **Generator v2:** real catalogue games, game-specific hours, and rules 1–4 (see above). Rule 5 is excluded.
- **Population:** 500 per persona instead of 100.
- **k = 6 kept, by majority across seeds**, not by the rule on seed 42 (see above).
- **Completionist description reworded;** `family` added to each cluster.
- **API:** `family` and `blend` added to the response. Nothing was removed or renamed.

1.0.0's earlier review changes still apply: truncated library sampling, the 8th feature `log_games_played`, RAWG
trophy denominators, and the tightened trophy fallback.

## Limitations

- **Simulated training data.** The archetypes come from personas we designed. The model reproduces their structure,
  but nothing yet shows that real players fall into these six types.
- **k is not settled by the data.** k = 3 and k = 6 are within about 0.01 in silhouette on every seed. k = 6 was
  adopted by majority after seeing the seed-42 result.
- **Completion and trophy behaviour still rest on assumptions.**
  - The persona Betas, M = 0.6, the engagement strengths and rule 3's 2% are design choices.
  - In a sensitivity check, switching off rule 1 or rule 2 moved the clusters beyond seed noise, so the model
    depends on those two rules most.
  - Survey completion and trophy rates should be compared with the per-persona means above.
- **SteamSpy lengths run 24–33% below HowLongToBeat**, so r is somewhat overstated, which makes finishing a little
  easier than it would be with true main-story lengths.
- **The catalogue is a 2019 PC snapshot.** 26% of Steam 200k plays (16% of hours) don't match a store game and are
  left out. Family and Educational have only 4 drawable games each.
- **Steam 200k is PC-only** and skewed toward free-to-play online games (Dota 2 alone is 28% of hours). It has no
  dates, so activity and the active-month ranges are hand-designed.
- **RAWG achievement counts are mostly PC counts** and can differ from PlayStation trophy counts. Until the RAWG
  backfill runs, many games use the achievements-table fallback, which can overstate a game's trophy rate.
- **Imputation is untested in training.** No simulated player had a missing trophy rate or genre diversity, but real
  users without trophy data get the training mean (0.145).
- **The Main vs Devotee** depends on whether a single game is online, so one game's IGDB `game_modes` can flip a user
  between them.
- **The 25% mixed share and w ~ U(0.3, 0.7) are assumptions.**

## Validation plan

Real players, collected later through a survey form, are used **only to test the frozen model**: they are scored by
this JSON and compared with what they report about themselves. They are never used to retrain it. The survey should
also report completion and trophy rates (to check rule 2's M) and whether players chase trophies on every game (to
decide on rule 5).

## Reproducing

1. Put `steam-200k.csv` and `steam.csv` (Kaggle Steam Store Games) in `data/`.
2. Run `notebooks/archetypes_training_v2.ipynb` once to build `data/steam_catalogue.csv`.
3. Run `python notebooks/v2_core_final.py --write-model`. It writes `models/archetype_model.json` (2.0.0) and the
   tables in `notebooks/v2_core_final/`. Seed 42 reproduces every number here; only `trained_at` changes.
4. 1.0.0 is reproduced by `notebooks/archetypes_training.ipynb`, which now writes to `models/archetype_model_v1.json`.
