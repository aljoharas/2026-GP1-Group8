# Player Archetypes: model card

| | |
|---|---|
| Model | K-Means, k = 6, frozen as JSON (`models/archetype_model.json`) |
| Version | **2.0.1** (seed 42): 2.0.0 plus the [atypical check](#atypical-check), with scoring otherwise identical. Replaces 1.0.0, which is kept as `models/archetype_model_v1.json` for rollback. |
| Trained by | `notebooks/v2_core_final.py --write-model` (2.0.0), then `notebooks/v2_core_final/atypical_threshold.py` (2.0.1). The v2 analysis notebook and the `sim_v2*` reports are archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`. |
| Served by | Python service, `GET /archetype?uid=...`, behind Node `GET /users/me/archetype` |
| Status | **Prototype. Not validated on real users.** It was trained on simulated players only, and a first survey (n = 20) found no agreement with self-descriptions beyond chance. See [Survey validation](#survey-validation). |

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
- **`blend`**: `{"primary", "secondary"}` when the top two archetypes are within 10 percentage points, whatever their
  families; otherwise `null`. The app shows it as "*primary*, with a touch of *secondary*", for example "Competitor,
  with a touch of The Main". There's never a blend for an atypical user.
- **`atypical`** (2.0.1): `true` when the user's distance to their nearest centre is beyond what 95% of training
  players have. The app then says "Closest match: *archetype*" instead of claiming a match. See
  [Atypical check](#atypical-check).
- **`distance_percentile`** (2.0.1): where that distance falls among the training players, from 0 to 100. Python
  returns it; Node doesn't pass it to the app.

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

The families are an interpretation layer: they group the six archetypes for display and don't change how a user
is assigned. Models without a `family` field (1.0.0) return `family: null`.

### Families check

Before relying on the families, they were tested against the model with a rule fixed in advance. The families
would count as confirmed only if all three held:
- **(a)** for every archetype, its nearest centre is its family partner;
- **(b)** for every archetype, its family partner is the most common second-highest archetype among its players;
- **(c)** more than 60% of close calls (top two within 10 points) are same-family.

The pre-set fallback was: if the check failed, keep the families (if the dendrogram supports them) but make the
blend family-agnostic.

The check ran on the served model (seed 42, its own 3,333 training players, served scoring at T = 0.75) and on the
k = 6 fits for generator seeds 0–4.

| Seed | First 3 Ward merges = families | (a) nearest = partner | (b) top second = partner | (c) close calls same-family | Confirmed |
|---|---|---|---|---|---|
| **42 (served)** | yes | all 6 | all 6 | **39.8%** (of 294) | **no** |
| 0 | yes | all 6 | all 6 | 40.5% (of 353) | no |
| 1 | yes | all 6 | fails: The Main | 36.3% (of 347) | no |
| 2 | yes | fails: Competitor | fails: Competitor, The Main | 41.3% (of 315) | no |
| 3 | yes | all 6 | all 6 | 33.2% (of 388) | no |
| 4 | yes | all 6 | all 6 | 37.5% (of 328) | no |

**The dendrogram supports the families.** Ward linkage on the six centres merges Casual + Explorer (height 2.48),
Competitor + Completionist (2.57) and Devotee + The Main (2.58) first, on every seed. The merges between families
come much later, at 4.32 and 4.93. The figure is
`docs/archetypes/figures/families_dendrogram.png`.

**Where players are undecided doesn't follow the families.** Only 33–41% of close calls are same-family, so
condition (c) fails on every seed. The most common cross-family close calls on the served model:

| Pair | Players |
|---|---|
| Casual / Competitor | 36 |
| Competitor / The Main | 29 |
| Competitor / Explorer | 27 |
| Casual / Devotee | 22 |
| Casual / The Main | 16 |

On four of the other five seeds, Competitor / The Main is the most common.

**Competitor is a hub.** Its two nearest centres are almost equally close: Completionist at 2.57 SD and The Main at
2.81 SD. It borders The Main through online play, and Casual and Explorer through hours per game. Its players'
runner-up splits Completionist 39.5% and The Main 27.8%. On seed 2 The Main becomes its nearest centre. Casual, the
largest and most central cluster, is the other common side of a close call.

The full analysis (`families_check/report.md`, tables, `families_check.py`) is archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`.

### Blend rule

**The blend rule was changed to family-agnostic because condition (c) failed, as decided in advance.** A blend is
returned whenever the top two archetypes are within 10 points, whatever their families. The families, the model and
the temperature are unchanged.

The first version of 2.0.0 blended only same-family near-ties, which would have covered fewer than half of the
players who are actually undecided.

Because the blend no longer uses families, it works with any model file. A rollback to 1.0.0 returns
`family: null`, but still returns a blend for near-ties.

**Blend rate.** These were measured through the served code path (`archetype_response` with this model); the script
(`blend_rate.py`) is archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`.

- **Training players:** 294 of 3,333 blend (**8.8%**). 117 are same-family and 177 cross-family. The same-family rule
  would have given 117 (3.5%).
- **By group:** mixed players blend most (14.4%), against 2.4–12.6% for each pure persona.
- **By top archetype:**

  | Archetype | Blend rate |
  |---|---|
  | Competitor | 13.3% |
  | Completionist | 9.9% |
  | Explorer | 8.9% |
  | Casual | 7.8% |
  | The Main | 7.6% |
  | Devotee | 4.4% |

- **Most common blends:**

  | Blend | Players |
  |---|---|
  | Completionist → Competitor | 32 |
  | Explorer → Casual | 31 |
  | Competitor → Completionist | 30 |
  | Casual → Explorer | 24 |
  | Competitor → Casual | 18 |
  | Casual → Competitor | 18 |

- **Real users** (5 with ≥ 5 manual games, 2026-11-23): **1 of 5** blends: "Competitor, with a touch of
  Completionist" (35% / 25%). The others lead by 13–74 points.

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
  - The real Competitors show 35–48%, so their mix matters more. That's partly why a blend is returned for
    near-ties.
  - One real user (Competitor 35% / Completionist 25%) gets a blend.

The temperature only changes the displayed percentages, never the assigned archetype.

## Atypical check

**Why it exists.** The softmax always gives some archetype the biggest share. Even a user far from every centre gets
a confident-looking "48% match". The survey showed this is common: real players are much more engaged than the
simulated training players, so many sit far outside the training cloud. The check makes that visible instead of
overstating the match.

**How the threshold is computed** (`notebooks/v2_core_final/atypical_threshold.py`):
- For each of the 3,333 training players, take the distance to their nearest centre in the scaled space, exactly as
  the service scores. The script first checks the feature table reproduces the model's own training shares.
- `atypical_distance_threshold` is the **95th percentile** of those distances: **2.641 SD**. It flags 5.0% of
  training players by construction.
- `training_distance_quantiles` (the 0th–100th percentiles) gives `distance_percentile`.
- Nothing else changed from 2.0.0. A test pins 2.0.0's scoring fields (scaler, imputation, centres, names, families,
  descriptions and temperature) by hash.

**Effect:** an atypical user keeps the same scores and nearest archetype, but gets `atypical: true` and no blend.
The app shows "Closest match: *archetype*" with no %, and a line saying the playstyle doesn't closely match any type
yet. A model file without a threshold (1.0.0) always returns `atypical: false`.

| Who | Flagged atypical |
|---|---|
| Training players (3,333) | 5.0% (by construction) |
| **Survey respondents (20)** | **17 (85%)**; median distance percentile 100 |
| **Real app users (5, ≥ 5 manual games, 2026-11-24)** | **3** (two Completionists and one Competitor) |

**Most real players are flagged.** The flag is honest about that, but it also shows the model's training population
doesn't cover the players it's meant for. See below.

## Survey validation

The frozen model (2.0.0, which scores identically to 2.0.1) was tested on **20 survey respondents**. All consented;
they were used only as a test set, and nothing was retrained or renamed. Each listed 5 games with hours, status and
trophy share, plus active months and a self-description. Rules were fixed before scoring. The full report (`survey_validation/report.md`) is
archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`.

**Result: no evidence of agreement beyond chance.**

| Model | Top-1 agreement with self-description | Chance (permutation) | p | Top-2 agreement | Chance | p |
|---|---|---|---|---|---|---|
| **2.0.0** | **4 / 20 = 20%** (95% CI 8–42%) | 25% | **0.81** | 10 / 20 = 50% | 41% | 0.19 |
| 1.0.0 | 6 / 20 = 30% (15–52%) | 21% | 0.17 | 10 / 20 = 50% | 41% | 0.21 |

- **v1 was not significantly better** (30% vs 21% chance, p = 0.17).
- **No sensitivity changed an agreement result:** games played = 5, activity = training mean, alternative game
  matches, and without an implausible respondent.

**The model gives only three archetypes to these respondents:** Completionist 10, Competitor 6, The Main 4. Explorer,
Casual and Devotee never appear.

**The calibration gap**, survey median vs v2-core training players:

| Feature | Survey | Training players |
|---|---|---|
| Hours per game | ≈ 43h | ≈ 4h |
| Trophy rate | 0.55 | 0.10 |
| Online share | 0.92 | 0.38 |

The simulation's engagement levels are far below real players', so real users land in a corner of the space the
training data barely covers. That's why the atypical check flags most of them.

**Form limitations:**
- **5-game cap.** Games played isn't observed, and it's Explorer's defining feature.
- **Very engaged sample.** 13 of 20 play daily, so Casual can hardly appear.
- **Self-reported ranges** converted to midpoints.
- **Hours are probably lifetime.**
- **5 self-descriptions mapped to 6 archetypes.**
- **n = 20**, so the confidence intervals are wide.

**Next step:** recalibrate the simulation's engagement levels (hours per game, trophy rate, online share, activity)
on real data, then test on **new** survey responses. These 20 have been seen and can't serve as an independent test
of a recalibrated model.

## Rollback

`models/archetype_model_v1.json` is the unchanged 1.0.0 model. Rolling back is a file swap: copy it over
`models/archetype_model.json` (or set `ARCHETYPE_MODEL_PATH`) and restart the service.

The code serves both versions. With 1.0.0, `family` is `null`, `atypical` is `false` (there's no threshold), and
`blend` follows the same family-agnostic rule (within 10 points). Everything else is as before. Serving both files locally was checked on 2026-11-17, before the
blend rule changed. The rollback with the new rule is covered by `test_rollback_to_v1_is_a_file_swap`.

## Changes from 1.0.0

- **Generator v2:** real catalogue games, game-specific hours, and rules 1–4 (see above). Rule 5 is excluded.
- **Population:** 500 per persona instead of 100.
- **k = 6 kept, by majority across seeds**, not by the rule on seed 42 (see above).
- **Completionist description reworded;** `family` added to each cluster.
- **API:** `family` and `blend` added to the response. Nothing was removed or renamed.
- **Blend rule made family-agnostic** after the families check failed condition (c) (see
  [Families check](#families-check)). Model, families and temperature unchanged.
- **2.0.1: atypical check added** (`atypical_distance_threshold`, `training_distance_quantiles`). Scoring is identical
  to 2.0.0. The API adds `atypical` and `distance_percentile`, and there's no blend when the user is atypical.

1.0.0's earlier review changes still apply: truncated library sampling, the 8th feature `log_games_played`, RAWG
trophy denominators, and the tightened trophy fallback.

## Experiments not adopted

These were run, reported and kept on their own branches. None changed the served model.

**v3: clustering real Steam players** (branch `feature/archetype-v3-real`; archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`, folder `v3_real/`)
- 2,408 real Steam 200k players, with no personas.
- **The structure is weak.** With simulated completion and trophies added, the best silhouette is 0.215, at k = 4. On
  the five real features alone it's 0.282, at k = 3.
- **Only The Main is confirmed**, about 1 SD from its served centre.
- **Real players split mainly by online share and library size:**
  - one online game (45%);
  - a big, varied library (39%);
  - mostly offline (16%).

**Survey validation of 2.0.0** (n = 20; [Survey validation](#survey-validation))
- Top-1 agreement with self-descriptions was **20%, against 25% by chance** (p = 0.81).
- The calibration gap is large. Respondents average about 43h per game against the simulation's 4h, a trophy rate of
  0.55 against 0.10, and an online share of 0.92 against 0.38.

**v2.2: v2-core recalibrated to the survey** (branch `feature/archetype-v2-2`; archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`, `v2_2/report.md`)
- Five common level shifts fit the survey's medians, and the targets were met.
- **But online share overshot** (median 0.985, IQR 0.15), so almost every simulated player became an online player.
- **The cluster matched to Devotee became an offline group** (online share 0.25), not a one-game group.
- **4 of the 5 app users would have been labelled Devotee**, three of them with no dominant game.
- Its 7 / 20 agreement on the survey is in-sample: those are the calibration responses, so it's **not validation**.
- **Not adopted**, because the calibration sample is very online and doesn't represent the app's users. The app users'
  online share was 0.00–0.39 for four of the five.

**Common finding: online vs offline is the dominant real-world axis.** It separates real Steam players, it's where the
survey and the simulation differ most, and it's what moved real app users between clusters in v2.2. Any future
recalibration should treat online share separately, and calibrate on data that looks like Loadout's own users.

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

Real players from a survey form are used **only to test a frozen model**: they're scored by the JSON and compared with
what they report about themselves, never used to retrain it.

The first round (n = 20) is reported in [Survey validation](#survey-validation). It found no agreement beyond chance.
It also showed that real trophy rates (median 0.55) are far above the simulation's, and that high trophy shares on
unfinished games are almost all online games: no respondent had 2 or more offline ones, so the survey gives no
support for rule 5.

The next round should test a model recalibrated on real engagement levels, with **new** respondents and a form that
allows more than 5 games.

## Reproducing

1. Put `steam-200k.csv` and `steam.csv` (Kaggle Steam Store Games) in `data/`.
2. Run `python notebooks/v2_core_final.py --build-catalogue` once to build `data/steam_catalogue.csv` with
   `backend/recommender/archetype_catalogue.py`.
3. Run `python notebooks/v2_core_final.py --write-model`. It writes `models/archetype_model.json` (2.0.0), the
   tables in `notebooks/v2_core_final/` and the training players' features (`v2core_training_features.csv`). Seed 42 reproduces every number here; only `trained_at` changes.
4. Run `python notebooks/v2_core_final/atypical_threshold.py` to turn 2.0.0 into 2.0.1. It reads
   `notebooks/v2_core_final/v2core_training_features.csv`, the same 3,333 players.
5. The report figures in `docs/archetypes/figures/` are drawn by `python notebooks/v2_core_final/figures.py`.
6. 1.0.0 was trained by `archetypes_training.ipynb`, now archived in `archetypes dataset/archive_2026-11-25` and at Git tag `archetypes-experiments-archive`; it writes
   `models/archetype_model_v1.json`, which stays in the repo as the rollback file.
