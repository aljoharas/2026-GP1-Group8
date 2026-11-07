# Player Archetypes — model card

| | |
|---|---|
| Model | K-Means, k = 6, frozen as JSON (`models/archetype_model.json`) |
| Version | 1.0.0 (trained 2026-11-07, seed 42) |
| Trained by | `notebooks/archetypes_training.ipynb` (runs locally or in Google Colab) |
| Served by | Python service, `GET /archetype?uid=...`, behind Node `GET /users/me/archetype` (Step 6) |
| Status | Trained on simulated players only. **Not yet validated on real players.** |

## What it does

Each Loadout user with at least 5 games in their manual logs gets one of six playstyle
archetypes, plus a match % for every archetype. The service computes the user's 8 features,
fills a missing trophy rate or genre diversity with the training mean, scales them with the
saved scaler, and measures the distance to each cluster centre. The nearest centre is the
archetype; the match % is a softmax over the negative distances.

The model is trained **once, offline**. The service only loads the JSON; it never retrains.

## The six archetypes

Centres in original units. Activity = ln(1 + hours per active month); games = ln(games played).

| Archetype | Shown in the app | Completion | Trophies | Genre div. | ln(1+h)/game | Top game | Activity | Online | Games | Training share |
|---|---|---|---|---|---|---|---|---|---|---|
| Completionist | You finish what you start and chase the trophies. | **0.78** | **0.63** | 0.80 | 2.03 | 0.40 | 2.44 | 0.27 | 2.14 (≈ 8) | 19.2% |
| Explorer | Always trying something new, across lots of genres. | 0.35 | 0.28 | **0.97** | 1.13 | **0.18** | 1.99 | 0.32 | **2.94 (≈ 19)** | 15.9% |
| Competitor | Online, competitive, and in it for the long sessions. | 0.46 | 0.30 | 0.80 | **2.65** | 0.39 | 3.06 | **0.79** | 2.13 (≈ 8) | 18.3% |
| The Main | One online game has most of your hours. | 0.45 | 0.29 | **0.31** | 1.71 | **0.92** | 3.73 | **0.96** | 2.00 (≈ 7) | 9.4% |
| Devotee | One game you keep coming back to, over and over. | 0.41 | 0.29 | **0.33** | 1.76 | **0.94** | **3.81** | **0.02** | 1.98 (≈ 7) | 16.5% |
| Casual | You play when life gives you time. | 0.37 | 0.29 | 0.78 | **0.94** | 0.37 | **1.42** | 0.32 | 1.85 (≈ 6) | 20.7% |

The Main and Devotee are the same "one dominant game" pattern, split by whether that game is
online. The team chose to keep them as two types.

## Features

Computed by one shared function, `archetype_features.compute_features`, for simulated players,
the notebook and the API alike. Input is one dict per game (all of a game's logs combined).
Fewer than 5 games → no archetype.

| # | Feature | Definition |
|---|---|---|
| 1 | completion_rate | games with at least one `completed` log ÷ games played |
| 2 | trophy_rate | Σ min(unlocked, available) ÷ Σ available, over games with an achievement count (see below); none → missing, imputed with the training mean (0.357) |
| 3 | genre_diversity | Shannon entropy of genre shares ÷ ln 10, capped at 1. A game's hours are split equally over its genres (every game weighs 1 if total hours = 0); games without genres are skipped; none → missing, imputed (0.700) |
| 4 | log_hours_per_game | mean of ln(1 + hours) over games with hours > 0 |
| 5 | top_game_share | hours of the most-played game ÷ total hours (0 if no hours) |
| 6 | log_activity | ln(1 + total hours ÷ distinct active months) |
| 7 | online_share | hours in online games ÷ total hours. Online = `game_modes` contains "multiplayer", "battle royale" or "co-operative" (case-insensitive) |
| 8 | log_games_played | ln(games played), added during review so library size, the explorer's defining trait, is visible to the model |

**Real users' data:** only `library_entries` rows with `source = 'manual'` and a `logged_at`;
Steam rows are ignored. Each row is one log; `hours_played` NULL = 0.

**Trophies for real users:** unlocked = distinct ticked achievement names per game across all
its logs (case and surrounding whitespace ignored); names are not matched to any list.
Available = `games.achievements_count` (RAWG game details). If that is missing or 0, the larger
of the achievements-table list size and the number of ticked names; if neither exists, the game
is left out of trophy_rate. Each game's rate is capped at 1.

## Training data

**Simulated players, calibrated on real hours data.** There is no labelled real-world dataset of
playstyles, so the population is generated (`archetype_sim.generate_players`) from five designed
personas, with per-game hours and library sizes drawn from the public **Steam 200k** dataset.

**Steam 200k preparation** (`data/steam-200k.csv`, not committed):
- keep `play` rows with hours > 0; sum hours per (user, game) → 70,477 plays by 11,350 users
- cap per-game hours at the 99th percentile (908 h; Steam counts idle time)
- keep users with ≥ 5 played games → 2,436 users, median 12 games
- confirmed: median per-game hours 4.5 h, 90th percentile 76 h; median user plays 1 game;
  Dota 2 has the most hours (28% of all) and the most players (free-to-play / online skew)

**Population:** 100 players per persona + 167 mixed players (25% of the 667 total). A mixed
player blends two random personas: each game comes from persona A with probability
w ~ U(0.3, 0.7), else from B. This keeps the clusters realistically messy.

**Per-game simulation:**
- hours: u ~ U(low, high), hours = Steam per-game hours quantile(u)
- status: completed with the player's completion probability; otherwise paused/playing 50/50
- trophies: 80% of games have a list (10–60 achievements); unlocked fraction ~ the persona's
  Beta, and completed games take the higher of two draws
- genres: 1–3 of RAWG's 19 genres; the first follows the persona's favourite-genre rule
- online: with the player's online probability
- active months: uniform in the persona's range, spread over the player's games

### Persona parameters

Ranges are inclusive. Quantiles index the Steam per-game hours distribution. Beta(a, b) is drawn
once per player. Library size is sampled from Steam users already inside the range.

| Persona | Parameter | Value | Reason |
|---|---|---|---|
| completionist | library size | 5–15 | finishes what it starts, so a moderate library |
| | hours quantiles | 0.25–0.90 | plays each game long enough to see it through |
| | P(completed) | Beta(8, 2) | finishes most games (mean 0.8) |
| | trophy fraction | Beta(6, 4) | hunts trophies (mean 0.6) |
| | favourite genres | 3–4, 70% of first genres | sticks to a few genres it likes, not exclusively |
| | P(online) | Beta(2, 5) | mostly single-player (mean 0.29) |
| | active months | 6–12 | plays through most of the year |
| explorer | library size | 10–40 | samples many games |
| | hours quantiles | 0.05–0.60 | tries a game, moves on |
| | P(completed) | Beta(2.5, 4) | finishes some (mean 0.38) |
| | trophy fraction | Beta(2, 6) | trophies are incidental (mean 0.25) |
| | favourite genres | 12, 100% of first genres | spreads evenly over ~12 genres |
| | P(online) | Beta(2, 5) | mostly single-player |
| | active months | 6–12 | plays through most of the year |
| devotee | library size | 5–10 | few games besides the main one |
| | hours quantiles | one game 0.95–0.995, rest 0.05–0.50 | one game from the top 5% of Steam hours; side games get little time |
| | P(completed) | Beta(3, 4) | average finisher (mean 0.43) |
| | trophy fraction | Beta(2, 6) | trophies are incidental |
| | favourite genres | 1–2, 85% of first genres | narrow taste around the main game |
| | P(online) | Beta(2, 5) | mostly single-player |
| | active months | 6–12 | plays through most of the year |
| competitor | library size | 5–15 | a moderate library |
| | hours quantiles | 0.40–0.95 | long sessions in the games it plays |
| | P(completed) | Beta(3, 4) | average finisher |
| | trophy fraction | Beta(2, 6) | trophies are incidental |
| | favourite genres | 3–4, 70% of first genres | a few favourite genres |
| | P(online) | Beta(8, 2) | mostly online/multiplayer (mean 0.8) |
| | active months | 6–12 | plays through most of the year |
| casual | library size | 5–8 | a small library |
| | hours quantiles | 0.05–0.50 | short play per game |
| | P(completed) | Beta(2, 4) | finishes few games (mean 0.33) |
| | trophy fraction | Beta(2, 6) | trophies are incidental |
| | favourite genres | 3–4, 70% of first genres | a few favourite genres |
| | P(online) | Beta(2, 5) | mostly single-player |
| | active months | 2–5 | plays in a few months of the year only |

## Training and choosing k

Features → impute missing values with the training mean → StandardScaler → K-Means
(`n_init=20, random_state=42`) for k = 2..8.

**k rule** (fixed before the final run, applied mechanically): if the best silhouettes are within
0.01 of each other, choose the largest of those k where every cluster (a) differs from every
other by ≥ 0.5 SD in at least one feature and (b) holds ≥ 5% of players; otherwise the highest
silhouette.

| k | 2 | 3 | 4 | 5 | **6** | 7 | 8 |
|---|---|---|---|---|---|---|---|
| silhouette | 0.269 | 0.288 | 0.315 | 0.309 | **0.320** | 0.286 | 0.261 |

k = 4 and k = 6 are within 0.01; both pass; the rule takes **k = 6**. It also picks 6 on all five
other generator seeds (the highest silhouette alone would pick 4 on two of them).
**The 0.5 SD condition never decided anything for this data**: every closest pair of centres,
for every candidate k on every seed, is ≥ 1.75 SD apart in some feature. The choice came down
to "largest k" and the 5% size check.

## Quality

- **Silhouette 0.32: moderate overlap.** That is consistent with playstyle being a continuum,
  not separate boxes. The app shows this to users through match scores (a % per archetype),
  not only a single label.
- **Stability:** refitting with 10 other seeds gives a mean pairwise Adjusted Rand Index of
  1.000. This shows the *pipeline* is stable, not that the archetypes are valid.
- **Sanity check:** ARI 0.845 between clusters and the generator's persona labels (pure players).
  This is a sanity check only, not validation: the personas were designed by us, so agreement
  only shows the pipeline recovers structure we put in.
- **Round trip:** loading the JSON alone and assigning each training player to the nearest
  centre reproduces the fitted model's labels for all 667 players.

## Changes during review

- **Library sizes: clipping replaced with truncated sampling; clipping distorted the Steam
  distribution.** With clipping, about half of the simulated explorers had exactly 10 games (the
  lower limit) and looked like casuals.
- **8th feature `log_games_played`** added so library size is visible to the model.
- **Trophy rate no longer matches ticked names to a list**: many lists in the achievements table
  are incomplete, so matching dropped real unlocks. The denominator is now RAWG's
  achievements_count, with the fallbacks above.

## Limitations

- **Simulated training data.** The archetypes come from personas we designed. The model
  reproduces their structure, but nothing yet shows real players fall into these six types.
- **Steam 200k is PC-only** and skewed toward free-to-play online games (Dota 2 alone is 28% of
  hours). Console players' hours may be distributed differently.
- **Steam 200k has no dates**, so activity (hours per active month) and the active-month ranges
  are hand-designed, not calibrated.
- **Completion and trophy behaviour are hand-designed.** Steam 200k has neither; the Betas for
  completion and trophy fraction are our assumptions.
- **RAWG achievement counts are mostly PC achievement counts and can differ from PlayStation
  trophy counts.** A player logging a PlayStation game may tick names from a trophy list whose
  size differs from the RAWG count, so their trophy rate for that game is approximate.
- **Trophy fallback is generous**: for a game with no RAWG count and no list, the denominator is
  the number of ticked names, so that game counts as fully unlocked.
- **Imputation is untested in training**: no simulated player had a missing trophy rate or genre
  diversity, but real users without trophy data get the training mean (0.357).
- **The Main vs Devotee** depends on whether a single game is online, so one game's IGDB
  `game_modes` can flip a user between them.
- **The 25% mixed share and w ~ U(0.3, 0.7) are assumptions**; more or messier mixing would lower
  the silhouette further.

## Validation plan

Real players, collected later through a survey form, are used **only to test the frozen model**:
they are scored by this JSON and compared with what they report about themselves. They are
never used to retrain it.

## Reproducing

1. Put `steam-200k.csv` in `data/` (or set `USE_DRIVE=True` in the notebook's first cell).
2. Run `notebooks/archetypes_training.ipynb` top to bottom. It writes the figures to
   `notebooks/figures/` and the model to `models/archetype_model.json`.
3. Seed 42 reproduces every number in this card; only `trained_at` changes.
