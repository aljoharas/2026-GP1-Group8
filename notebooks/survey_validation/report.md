# Survey validation of the served archetype model (2.0.0)

**What was tested:** the served model, **frozen**. Nothing was retrained, re-weighted or renamed, and neither the
temperature nor the blend rule changed because of these results.

**Data:** 20 anonymous respondents, all consented, used only as a test set. IDs are R01–R20 and outputs have no
timestamps. The CSV stays in `data/` (gitignored).

**Files:**
- `match_games.py`, `survey_names.py`, `lookup_games.js`: game matching (Step 1)
- `survey_features.py`: conversion and scoring (tests: `test_survey_features.py`, 10 passing)
- `validate.py`: Steps 2–4
- `tables/` and `results.json`: the outputs

## Verdict

**The served model does not agree with how respondents describe themselves. On 20 respondents it does no better
than chance.**

| Model | Top-1 agreement | Chance (permutation) | p | Top-2 agreement | Chance | p |
|---|---|---|---|---|---|---|
| **2.0.0 (served)** | **4 / 20 = 20%** (95% CI 8–42%) | 25% | **0.81** | 10 / 20 = 50% (30–70%) | 41% | 0.19 |
| 1.0.0 (v1, comparison only) | 6 / 20 = 30% (15–52%) | 21% | 0.17 | 10 / 20 = 50% (30–70%) | 41% | 0.21 |

**The model uses only three of its six archetypes on these respondents:** Completionist 10, Competitor 6, The Main 4.
It never gives Explorer, Casual or Devotee, although 7 respondents describe themselves as "many games & genres" or
"now and then".

**Two reasons are visible in the features:**
1. **The respondents are far more engaged than the simulated training players.**

   | Survey median | Survey | v2-core training players |
   |---|---|---|
   | ln(1+h) per game | 3.78 (≈ 43h) | 1.59 (≈ 4h) |
   | Trophy rate | 0.55 | 0.10 |
   | Activity | 3.71 | 2.42 |
   | Online share | 0.92 | 0.38 |

   Most respondents land in the high-engagement corner the model calls Completionist or Competitor.
2. **The form caps the list at 5 games.** Games played, the Explorer's defining feature, is unknown and filled with
   the training mean. Low activity, Casual's defining feature, doesn't occur in a sample where 13 of 20 play daily.

The sensitivities change nothing: games played = 5, activity = training mean, the alternative matches, and without
R13. Agreement stays at 4 / 20 (or 4 / 19), and no respondent's agreement result changes.

With n = 20, **the test can't show the model is right, and it gives no evidence that it is.** v1's 6 / 20 isn't
significantly better (p = 0.17). The two models' intervals overlap almost entirely.

## Step 1: game matching (approved at the checkpoint)

| | |
|---|---|
| Survey entries | 100 (20 × 5); 76 distinct names, case-insensitive |
| Matched in the app's games table | 51, plus 1 by pinned slug |
| Matched with the app's RAWG search, modes from the app's IGDB lookup | 44 |
| Not found (left unmatched) | 4: Meccha / Mecha chameleon ×3, Burglin gnomes |
| Low-confidence decisions (reviewed and approved) | 22 entries |

**Pinned corrections** (the plain-name entries were wrong or empty):
- Fortnite → Fortnite Battle Royale, with modes from IGDB's `fortnite`
- Fall Guys → Fall Guys: Ultimate Knockout
- God of War → the 2018 game

**Override:** GTA VI (R16, R19) is **offline and not multiplayer-only**, because its online mode hasn't launched.

Every decision and its reason is in `survey_names.py` and `survey_game_matches.csv`.

## Step 2: conversion (rules fixed in the task)

- **Hours:** geometric midpoints (< 2 → 1, 2–5 → 3.2, …, > 200 → 280).
- **Status:** Finished → completed. Paused and Still Playing → not completed.
- **Trophy share:** midpoints. "None" and "Don't know" are left out of the trophy rate. A respondent's trophy rate is
  the **unweighted** mean over games with a known share. The app instead uses ticked ÷ total, which weights big lists
  more. (To get the unweighted mean through the shared `compute_features`, every known game is given the same
  denominator.)
- **Games played:** missing in the main run, filled with the training mean. A sensitivity uses 5.
- **Activity:** total hours ÷ Q1 months. A sensitivity uses the training mean.
- **Unmatched games:** no genres, so they're left out of genre diversity. They count as offline hours in online
  share, because that's what the app's `compute_features` does with a game without modes. There are only 4 such
  entries, all with short play.
- **Scoring:** the served code path at T = 0.75. A test confirms the scorer reproduces `/archetype`'s percentages and
  blend exactly for complete features.

## Step 3: scoring (fixed before looking)

**Mapping from self-description to archetypes:**

| Self-description | Agrees with |
|---|---|
| "finish games and collect trophies" | Completionist |
| "trying lots of different games and genres" | Explorer |
| "sink a lot of hours into a few favourite games" | Devotee or The Main |
| "mostly play online or multiplayer games" | Competitor or The Main |
| "play now and then" | Casual |

**Metrics:**
- **Top-1:** the model's top archetype is in the mapped set.
- **Top-2:** either of its top two is.
- **Interval:** Wilson 95% CI.
- **Chance and p-value:** 10,000 shuffles of the self-labels across respondents. Chance is the mean agreement under
  shuffling; p is one-sided.

**Confusion table, 2.0.0** (rows: self-description; columns: model top archetype):

| | Completionist | Explorer | Competitor | Casual | Devotee | The Main |
|---|---|---|---|---|---|---|
| finish & trophies (5) | **2** | 0 | 2 | 0 | 0 | 1 |
| many games & genres (4) | 3 | **0** | 1 | 0 | 0 | 0 |
| hours in a few favourites (5) | 1 | 0 | 3 | 0 | **0** | **1** |
| online / multiplayer (3) | 2 | 0 | **0** | 0 | 0 | **1** |
| now and then (3) | 2 | 0 | 0 | **0** | 0 | 1 |

**Confusion table, 1.0.0** (comparison only):

| | Completionist | Explorer | Competitor | Casual | Devotee | The Main |
|---|---|---|---|---|---|---|
| finish & trophies | **2** | 0 | 2 | 0 | 0 | 1 |
| many games & genres | 0 | **0** | 3 | 1 | 0 | 0 |
| hours in a few favourites | 0 | 0 | 4 | 0 | **0** | **1** |
| online / multiplayer | 0 | 0 | **2** | 0 | 0 | **1** |
| now and then | 2 | 0 | 1 | **0** | 0 | 0 |

**Per respondent, 2.0.0** (✓ = agrees with the self-description):

| ID | Self-description | Top 3 | Blend | Top-1 | Top-2 |
|---|---|---|---|---|---|
| R01 | online / multiplayer | The Main 55, Competitor 23, Devotee 11 | | ✓ | ✓ |
| R02 | many games & genres | Completionist 61, Competitor 31, The Main 3 | | | |
| R03 | finish & trophies | The Main 34, Completionist 26, Competitor 23 | The Main + Completionist | | ✓ |
| R04 | now and then | The Main 40, Competitor 37, Devotee 12 | The Main + Competitor | | |
| R05 | online / multiplayer | Completionist 60, Competitor 23, The Main 11 | | | ✓ |
| R06 | many games & genres | Completionist 59, Casual 13, Competitor 12 | | | |
| R07 | hours in a few favourites | Completionist 45, Competitor 36, The Main 12 | Completionist + Competitor | | |
| R08 | hours in a few favourites | Competitor 50, Completionist 37, The Main 7 | | | |
| R09 | finish & trophies | Competitor 50, Completionist 34, The Main 9 | | | ✓ |
| R10 | finish & trophies | Completionist 82, Competitor 12, Devotee 2 | | ✓ | ✓ |
| R11 | hours in a few favourites | Competitor 46, Completionist 30, The Main 16 | | | |
| R12 | hours in a few favourites | Competitor 49, The Main 29, Completionist 11 | | | ✓ |
| R13 | online / multiplayer | Completionist 42, Competitor 27, The Main 21 | | | ✓ |
| R14 | many games & genres | Completionist 62, Competitor 19, Devotee 10 | | | |
| R15 | finish & trophies | Completionist 77, Competitor 13, The Main 5 | | ✓ | ✓ |
| R16 | now and then | Completionist 74, Competitor 10, Devotee 9 | | | |
| R17 | hours in a few favourites | The Main 54, Competitor 18, Devotee 11 | | ✓ | ✓ |
| R18 | now and then | Completionist 86, Competitor 8, Devotee 2 | | | |
| R19 | finish & trophies | Competitor 35, Completionist 28, The Main 26 | Competitor + Completionist | | ✓ |
| R20 | many games & genres | Competitor 33, Completionist 31, The Main 24 | Competitor + Completionist | | |

5 of 20 respondents get a blend.

**Sensitivities** (served model):

| Variant | n | Top-1 | p | Top-2 | p | Respondents whose top archetype changes |
|---|---|---|---|---|---|---|
| main | 20 | 4 (20%) | 0.81 | 10 (50%) | 0.19 | – |
| games played = 5 | 20 | 4 (20%) | 0.81 | 10 (50%) | 0.19 | none |
| activity = training mean | 20 | 4 (20%) | 0.79 | 10 (50%) | 0.18 | R04 (The Main → Competitor), R20 (Competitor → Completionist); agreement unchanged |
| alternative matches (R03 Wolfenstein: Youngblood; R02, R15 The Last of Us Remastered; R02 FNAF Security Breach) | 20 | 4 (20%) | 0.81 | 10 (50%) | 0.19 | none |
| without R13 | 19 | 4 (21%) | 0.71 | 9 (47%) | 0.21 | – |

## Step 4: descriptive comparisons (reporting only)

Feature distributions, median (IQR):

| Feature | Survey (20) | v2-core training (3,333) | v1 training (667) | Real Steam, v3 (2,408) |
|---|---|---|---|---|
| completion rate | 0.40 (0.20–0.60) | 0.17 (0.00–0.33) | 0.45 (0.25–0.68) | – (simulated) |
| trophy rate | 0.55 (0.44–0.69) | 0.10 (0.05–0.19) | 0.31 (0.25–0.40) | – (simulated) |
| genre diversity | 0.49 (0.37–0.62) | 0.81 (0.67–0.91) | 0.77 (0.54–0.92) | 0.59 (0.43–0.72) |
| ln(1+h) per game | 3.78 (3.10–4.13) | 1.59 (1.13–2.18) | 1.64 (1.08–2.20) | 2.06 (1.59–2.58) |
| top-game share | 0.55 (0.32–0.65) | 0.45 (0.32–0.68) | 0.39 (0.27–0.79) | 0.46 (0.31–0.65) |
| activity | 3.71 (3.26–4.01) | 2.42 (1.77–3.17) | 2.62 (1.74–3.42) | – (simulated) |
| online share | 0.92 (0.61–0.99) | 0.38 (0.07–0.78) | 0.32 (0.04–0.74) | 0.92 (0.64–1.00) |
| ln games played | 1.61 (form cap: 5) | 2.08 (1.79–2.40) | 2.08 (1.79–2.40) | 2.48 (1.95–3.22) |

The real-Steam column comes from the v3 branch's committed table (`feature/archetype-v3-real`, `05c7daa`).

**Which simulation is closer?** On all three simulated behaviours, **v1 is closer** to the survey than v2-core:

| Feature | Survey | v1 | v2-core |
|---|---|---|---|
| completion | 0.40 | 0.45 | 0.17 |
| trophy rate | 0.55 | 0.31 | 0.10 |
| activity | 3.71 | 2.62 | 2.42 |

On the real features, the survey looks like the **real Steam players**, not like either simulation:
- online share 0.92 vs 0.92 (simulations 0.32–0.38);
- genre diversity 0.49 vs 0.59 (simulations 0.77–0.81).

The survey's hours per game are higher still. These are probably lifetime hours (see limitations).

**Trophy-hunter check:**
- 14 of 56 unfinished games have ≥ 51% of their trophies.
- 13 of those 14 are online: 10 online with a single-player mode, 3 multiplayer-only.
- **1 is offline.**
- **No respondent has ≥ 2 offline unfinished games at ≥ 51%.**

The survey gives no support for offline trophy hunting on unfinished games. High trophy shares on unfinished games
are mostly live online games, which have no ending to finish.

**Completionist vs Competitor** (16 respondents assigned one of the two), medians:

| Model top | n | Completion | Trophy rate | Online share |
|---|---|---|---|---|
| Completionist | 10 | 0.60 | 0.69 | 0.59 |
| Competitor | 6 | 0.20 | 0.52 | 0.98 |

The two separate on completion (0.6 vs 0.2) and on online share (0.59 vs 0.98), and less on trophies. But the
Completionists include three respondents who play almost only online (R05 0.96, R07 0.93, R13 0.99). Their high
trophy rates put them there, and two of them describe themselves as online / multiplayer players.

## Limitations

- **n = 20.** The CIs are wide: top-1 is 8–42%. Only a large effect could be detected.
- **A very engaged sample.** 13 of 20 play daily, and 11 played all 12 months. The model's light archetypes (Casual,
  and Explorer through library size) can hardly appear.
- **The 5-game form cap.** Games played isn't a real value; it's filled with the training mean in the main run. The
  Explorer type depends mainly on library size, so the survey can't test it.
- **Self-reported ranges.** Hours, trophies and months are ranges converted to midpoints. The trophy rate is an
  unweighted mean of range midpoints, not the app's ticked ÷ total.
- **Lifetime hours.** Hours are probably lifetime, not past-year, which inflates activity (hours ÷ months). The
  activity = training-mean sensitivity changes no agreement result.
- **Mapping 5 descriptions to 6 archetypes.** Two descriptions map to two archetypes each. Devotee and The Main share
  "hours in a few favourites", and The Main also counts for "online". That makes chance agreement higher for those
  respondents. The permutation test accounts for it.
- **R13 is implausible.** R13 reports finishing Spider-Man and Detroit in under 2 hours, probably a misread hour
  range. R13 is kept as answered in the main analysis. Without R13: top-1 4 / 19, top-2 9 / 19, conclusions
  unchanged.
- **"Co-operative" counts as online.** Under the app's IGDB definition this includes local co-op (for example
  Cuphead), which inflates online share.
- **4 entries are unmatched:** Meccha / Mecha chameleon ×3 and Burglin gnomes. They have no genres and count as
  offline hours.
- **GTA VI was overridden to offline**, because its online mode isn't available yet.
- **This is a test of the model as built.** It doesn't separate "the archetypes are wrong" from "the training
  simulation's levels are wrong". The feature comparison points at the second as a large part of the miss: survey
  respondents sit far outside v2-core's trophy, hours and online ranges. **Nothing was changed because of it.**
