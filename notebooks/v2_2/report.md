# v2.2: recalibrated engagement levels (reported finding, not served)

**Branch and status:** `feature/archetype-v2-2`. The served model stays **2.0.1**. v2.2 is **calibrated to the 20
survey responses' engagement levels and not independently validated**: those 20 responses are calibration data now,
and there is no new test set.

**Files:**
- `calibrate.py`: method and search (log in `calibration_log.txt`)
- `train_v2_2.py`: steps 3–6 (log in `train_log.txt`)
- `results.json`, `tables/`
- `archetype_model_v2_2_draft.json`: the draft model, not in `models/`

## Serve decision under the fixed rule: not served, pending your decision on (b)

| Condition | Result |
|---|---|
| (a) k = 6 within 0.01 of the best silhouette on most seeds | **Pass.** 6 of 6 seeds; the best k is 5 on five seeds and 6 on one |
| (b) six archetypes matched one-to-one, descriptions still fit | **Not met as it stands.** Matched one-to-one, but **Devotee isn't a mutual-nearest match**, and its description doesn't fit the cluster (below) |
| (c) plausibility | **Pass** (one judgement call, accepted; below) |

**Decision, 2026-11-24:** keep 2.0.1 served and don't serve v2.2. v2.2 is recorded in the model card under
"Experiments not adopted", and `models/` is unchanged.

**Why (b) fails: the cluster matched to Devotee is "the offline group", not "one game".**
- Its centre has an online share of 0.25. It's the only offline cluster; every other is 0.88–0.98.
- Its top-game share is 0.64. In 2.0.1 Devotee's was 0.89, and in v2.2 The Main has the highest (0.76).
- On real app users this shows directly. v2.2 labels **4 of 5 users Devotee**, and three of those four have top-game
  shares of only 0.22–0.37. They land there because they're less online than the recalibrated population, not
  because one game dominates their play.
- "One game you keep coming back to, over and over" would be wrong for them. A rewording such as "Mostly offline
  play" would describe a different archetype, not a small wording edit. That's for you to decide.

**Judgement call on (c), accepted as a pass.** One completion below 0.3 × length came from rule 1 out of 797 games
(0.13%). The automated check used a 0.1% bar, so it reported a fail. But that is within rule 1's design rate (up to
about 0.34% at r = 0.3), which is the same standard v2-core was held to (2 of 9,095 accepted as "near 0"). Decision,
2026-11-24: (c) is a pass. Everything else in (c) passes outright:
- no 100% trophy sets on unfinished games, and none with r < 3;
- multiplayer-only completion at 2.07%;
- all four correlation signs as expected. Online ↔ completion is now −0.10.

## 1–2. Calibration

**Targets** (20 responses, survey_validation conversion), median (IQR):

| Feature | Target | v2-core (2.0.x training) | v2.2 (500 per persona, seed 42) |
|---|---|---|---|
| ln(1+h) per game | **3.78** (1.03) | 1.59 (1.05) | **3.41** (1.01) |
| trophy rate | **0.551** (0.248) | 0.100 (0.139) | **0.555** (0.210) |
| online share | **0.921** (0.376) | 0.376 (0.708) | **0.985** (0.148) |
| completion rate | **0.400** (0.400) | 0.167 (0.333) | **0.375** (0.371) |
| activity | **3.71** (0.75) | 2.42 (1.40) | **4.09** (1.52) |

The objective (squared median gaps scaled by the target IQR) falls from **13.29 to 0.43**.

**Fitted shifts**, each one common shift across personas, so the persona ordering is kept:

| Shift | Value |
|---|---|
| hours quantile ranges | **+0.45** |
| completion propensity | **+0.25** logit |
| trophy propensity | **+2.5** logit |
| P(online) | **+3.25** logit |
| active months | **+7** (clipped to 12) |

**Search details:**
- coordinate descent on fixed grids, 100 per persona, seed 42, common random numbers;
- 308 evaluations;
- it stopped at the fixed 4 rounds while still improving slightly (0.30 → 0.27).

**Fit problems:**
- **Online share overshoots** (0.985 against 0.92) **and loses its spread** (IQR 0.15 against 0.38). Nearly every
  simulated player becomes an online player.
- **Activity overshoots**, because longer hours and more months both raise it.

## 3. Plausibility

| Check | Result |
|---|---|
| Rule 1 completion with r < 0.3 | 1 of 797 |
| Multiplayer-only completions (rule 3) | 3 of 109 at r < 0.3; 2.07% overall (129 / 6,219) |
| 100% trophies on unfinished games | 0 of 14,096 |
| 100% trophies with r < 3 | 0 of 10,199 |
| Full trophy sets | 896 of 22,976 games with a list (3.9%; v2-core 5) |
| hours ↔ trophy | +0.46 ✓ |
| activity ↔ trophy | +0.26 ✓ |
| completion ↔ trophy | +0.67 ✓ |
| online ↔ completion | −0.10 ✓ |

## 4. Training (3,333 players, seeds 42 and 0–4, k = 2..8)

| k | 2 | 3 | 4 | **5** | **6** | 7 | 8 |
|---|---|---|---|---|---|---|---|
| mean silhouette | 0.180 | 0.190 | 0.197 | **0.212** | **0.210** | 0.193 | 0.183 |

**k:** the best k is 5 on seeds 42, 0, 2, 3 and 4, and 6 on seed 1. k = 6 is within 0.01 of the best on all six
seeds.

**Quality at k = 6** (seed 42):

| | v2.2 | 2.0.x |
|---|---|---|
| silhouette | **0.210** | 0.260 |
| k-means stability (10 restarts) | 0.987 | |
| seed-to-seed ARI | 0.80–0.91 | |
| persona ARI | 0.27 | 0.58 |

## 5. Match to the six archetypes

Matching uses each model's own standardised units. v2.2's levels moved on purpose, so the match compares relative
profiles. Matching in 2.0.1's units gives the same one-to-one assignment.

| Archetype | Distance (own units) | Mutual nearest | Description fits? |
|---|---|---|---|
| Casual | 0.49 | yes | yes: lowest hours and activity |
| Explorer | 0.93 | yes | yes: most games and genres |
| The Main | 1.13 | yes | yes: highest top-game share (0.76) and online (0.98) |
| Competitor | 1.31 | yes | mostly: the most hours per game and activity, but online (0.91) no longer sets it apart |
| Completionist | 1.52 | yes | yes: highest completion (0.64) and trophies (0.72) |
| **Devotee** | **2.48** | **no** | **no:** the offline cluster (online 0.25), top game 0.64 |

Centres in original units are in `tables/centres_side_by_side.csv`, and feature ranks in `feature_ranks_v2_2.csv`.

**Temperature** (as for 2.0.x):

| T | Pure median | Mixed median | ≥ 90% |
|---|---|---|---|
| 0.5 | 79% | 75% | 30% |
| 0.6 | 71% | 67% | 17% |
| **0.75** | **62%** | **58%** | **1.4%** |
| 1.0 | 50% | 48% | 0% |

- T = 0.75 still avoids overclaiming.
- Mixed players are now only 4 points below pure ones, so that criterion is weakly met at every T.

**Real app users** (T = 0.75; `tables/real_users.csv`):
- 4 of 5 are Devotee, and user 2 is Casual 34% / Devotee 33%.
- 4 of 5 are atypical. Under 2.0.1 it was 3 of 5.

**Atypical threshold:** 2.852 (95th percentile; 2.0.1's was 2.641).

## 6. In-sample check: the calibration responses (NOT validation)

| Model | Top-1 agreement | Chance | p | Top-2 | Chance | p | Atypical | Top archetypes given |
|---|---|---|---|---|---|---|---|---|
| 2.0.1 | 4 / 20 (20%) | 25% | 0.81 | 10 / 20 | 41% | 0.19 | 17 / 20 | Completionist 10, Competitor 6, The Main 4 |
| v2.2 | 7 / 20 (35%) | 29% | 0.33 | 10 / 20 | 50% | 0.63 | **7 / 20** | The Main 10, Competitor 4, Devotee 3, Casual 2, Completionist 1 |

- v2.2 uses five of the six types and flags far fewer respondents atypical. That's expected, since it was fitted to
  them.
- Its agreement still isn't above chance.
- None of this is evidence of validity: these are the calibration responses.

## Reading

Recalibrating on 20 very online, very engaged respondents moved the simulated population to them. But the app's own
users are less online (0.00–0.39 for four of five), so v2.2 serves them worse than 2.0.1: most of them become
"Devotee" through low online share alone.

The survey is a biased calibration sample:
- respondents listed their favourite games, which raises hours per game;
- 13 of 20 play daily;
- 5 games each;
- self-reported lifetime hours.

Calibrating on it exchanges one mismatch for another.

**My recommendation: keep 2.0.1.** Before trying v2.2 again:
- calibrate on a sample that looks like Loadout's users (their own logs, once there are enough);
- or calibrate online share and hours separately, not with one fitted level.
