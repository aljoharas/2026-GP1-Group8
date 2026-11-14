# Simulation v2: report

Branch `feature/archetype-sim-v2`. Notebook: `notebooks/archetypes_training_v2.ipynb`. Figures:
`notebooks/figures/v2/`. Tables and `results.json`: `notebooks/sim_v2/`. Candidate model:
`models/archetype_model_v2.json` (2.0.0-candidate, **not wired into the app**). Rules section for the model card:
`models/archetype_sim_v2_rules.md`.

Model v1.0.0, the served endpoint, the shared feature function and the k rule are unchanged.
`generate_players()` still defaults to v1 and still reproduces model 1.0.0 exactly (same k, scaler, centres,
labels), and all 242 recommender tests pass (15 of them new). Every number below comes from seed 42 unless stated.

## Verdict

v2 removes the impossible players and gives the expected dependencies between features. It also makes the
clusters noticeably weaker and less certain, and v2's k is not stable across generator seeds.

- **Plausibility: pass.**
  - No game was completed below 0.3 × its length, apart from rule 3's flat 2%.
  - There are no 100% trophy sets on unfinished games.
  - Three of the four expected correlation signs hold. The fourth (online ↔ completion) is explained by hours confounding.
- **The clusters mostly survive.**
  - The rule picks k = 7. Six clusters match v1's six archetypes, and one new cluster consists of **trophy hunters**
    (32 of its 39 players are rule-5 hunters).
  - All five real users keep their archetype.
  - About 20% of simulated players are reassigned (ARI 0.56–0.65).
  - Every archetype's completion and trophy centres drop by 0.5–1.6 v1 SD, because v2 players finish and
    collect much less overall.
- **The structure is weaker.**

  | | silhouette | k-means stability (mean pairwise ARI) | persona ARI |
  |---|---|---|---|
  | v1 | 0.32 | 1.00 | 0.85 |
  | v2 | 0.25 | 0.92 | 0.47 |

  On other generator seeds, the same pre-registered rule picks **k = 3, 3, 7, 6, 3**. On v2 the silhouette curve is
  almost flat (0.239–0.256 for k = 3–8).
- **Sensitivity.**
  - The pre-registered verdict calls 12 of the 13 variants "Substantial effect", but that verdict can't separate
    real effects from seed noise here: v2's own seed noise already changes k and has an ARI below 0.8.
  - Compared with the seed-noise ARI range instead, only **rule 1 (finishing needs hours) and rule 2 (trophies
    follow hours)** move the clusters beyond seed noise.
  - E is irrelevant: E = 2.5 gives identical clusters.
  - The 7th cluster depends on rule 5's design guess.

**My recommendation:** don't replace v1 with this candidate as it stands. The v2 rules are better grounded than
v1's independent draws, but a model whose k flips between 3 and 7 depending on the generator seed isn't ready to
name or serve. To strengthen the case for a later decision, I'd simulate more players per persona so that seed
noise can be told apart from real structure. I didn't do that, because it changes the training setup. The
decision is yours.

## 1. Catalogue

| | |
|---|---|
| Store games (`steam.csv`; all expected columns present, playtime in minutes) | 27,075 |
| With at least one RAWG genre | 26,879 |
| With a typical length (SteamSpy median > 0) | 6,128 |
| **Drawable** (has a length and ≥ 1 Steam 200k player) | **1,843** |
| Steam 200k titles matched | 2,460 of 3,600 (74% of plays, 84% of hours) |
| Games with their own hours distribution (≥ 20 players) | 411. These cover 56% of the draws. |
| Drawable games that are online / multiplayer-only / have no achievement list | 35% / 7% / 34% |

**Genre mapping:**
- Ten Steam genres keep their names: Action, Adventure, Casual, Indie, Massively Multiplayer, Racing, RPG,
  Simulation, Sports, Strategy.
- Education becomes Educational.
- Dropped: Early Access and Free to Play (business models), Violent, Gore, Nudity and Sexual Content (content
  descriptors), and the software genres.
- Eight RAWG genres aren't Steam genres, so they come from `steamspy_tags`:
  - FPS, Shooter, Shoot 'Em Up and Third-Person Shooter → Shooter
  - Puzzle → Puzzle
  - Arcade → Arcade
  - Platformer → Platformer
  - Fighting → Fighting
  - Family Friendly → Family
  - Board Game → Board Games
  - Card Game → Card

Thin genres: Family (4 drawable games), Educational (4), Board Games (13), Card (14).

**Titles:** matching uses a key that ignores case, accents and symbols, then retries with client suffixes removed
("- Multiplayer", "Beta"). I rejected token-set matching because it produced wrong matches such as
"The Ultimate DOOM" → DOOM (2016).

**typical_length_h vs HowLongToBeat (Bailey et al.):**

| | p25 | median | p75 | p90 | Compared with HLTB main story |
|---|---|---|---|---|---|
| All games with a length | 1.3h | **3.8h** | 6.2h | 14.4h | 24% below 5h (shorter games) |
| Drawable, popularity-weighted | 3.5h | **7.1h** | 13.4h | 31.3h | 33% below 10.5h (full-price) |

The values are lower than HLTB, as expected, because SteamSpy's median includes players who quit early. They are
not wildly off. Clipping moved 22% of games up to 1h and 36 games down to 150h.

## 2. Rules

See `models/archetype_sim_v2_rules.md` for every rule with its parameters, reason and source. These are the
changes since the Step 3 stop:
- **Rule 2** now uses a story share M = 0.6 of the list by the end of the main story, with the remaining 0.4 over
  the extra E × length hours on completed games only.
- **Game-specific hours** (≥ 20 players) were added.
- **Popularity** now counts distinct users per game, so "X" and "X - Multiplayer" count a player once.

New tests (`tests/test_archetype_sim_v2.py`) cover:
- the trophy curve: monotone, M at r = 1, 100% only when completed and r ≥ 1 + E;
- rule 1's 5% and 95% edges;
- the generator's hard constraints;
- determinism;
- that v1 stays the default;
- common random numbers.

## 3. Plausibility checks

| Check | Count | Out of |
|---|---|---|
| Completed with r < 0.3 | 2 | 2,111 |
|   of which multiplayer-only (rule 3's flat 2%) | 2 | 244 |
|   of which not multiplayer-only (rule 1) | **0** | 1,867 |
| 100% trophies on an unfinished game | **0** | 3,724 |
| 100% trophies on hunters' unfinished games | **0** | 410 |
| 100% trophies with r < 1 + E | **0** | 4,011 |
| Completed multiplayer-only games | 14 (2.11%) | 664. Within ±2 SE of 2% (0.91–3.09%). |
| Full sets overall | 2 | 4,628 |

**Expected correlation signs** (Spearman, v1 → v2):

| Pair | Expected | v1 | v2 | |
|---|---|---|---|---|
| hours per game ↔ trophy rate | + | +0.30 | +0.55 | ✓ |
| activity ↔ trophy rate | + | −0.01 | +0.27 | ✓ |
| completion ↔ trophy rate | + | +0.52 | +0.56 | ✓ |
| online share ↔ completion | − | −0.01 | **+0.10** | explained, see below |

**Online share ↔ completion.** The pooled value is **+0.10**. Holding log hours per game fixed (partial
correlation) it is **−0.11**. Within personas it ranges from −0.09 to +0.11:

| Persona | ρ |
|---|---|
| casual | +0.11 |
| competitor | −0.04 |
| completionist | −0.00 |
| devotee | −0.09 |
| explorer | +0.08 |
| mixed | +0.01 |

At the game level:

| Game kind | Share completed |
|---|---|
| Multiplayer-only | 2.1% |
| Online with a single-player mode | 24.2% |
| Offline | 20.7% |

The pooled sign is confounded by per-game hours. Competitors have both the highest online share (0.80) and the
longest per-game hours, and rule 1 lets long play finish more often, so online share and completion rise together
across personas. As you decided, I didn't add any rule for online games with a single-player mode.

The other large correlation changes:
- completion ↔ hours per game: +0.30 → +0.60
- activity ↔ online share: +0.06 → +0.26
- top-game share ↔ activity: +0.55 → +0.35

Full table: `sim_v2/spearman_v1_v2.csv`, `figures/v2/03_spearman_v1_v2.png`.

**Mean completion rate and trophy rate per persona:**

| Persona | Completion v1 | Completion v2 | Trophy v1 | Trophy v2 |
|---|---|---|---|---|
| completionist | 0.79 | 0.46 | 0.67 | 0.38 |
| explorer | 0.35 | 0.11 | 0.28 | 0.13 |
| devotee | 0.44 | 0.10 | 0.28 | 0.12 |
| competitor | 0.48 | 0.30 | 0.30 | 0.19 |
| casual | 0.35 | 0.07 | 0.28 | 0.09 |
| mixed | 0.46 | 0.24 | 0.34 | 0.18 |

Nothing was tuned to hit any of these values. The ordering is kept: completionists finish and collect the most.
Levels fall because v1's hours quantile ranges often give r < 1. For example, the median r is 0.25 for casual
players and 0.41 for explorers. These are the numbers to check against the survey.

## 4. Training v2

I used the same pipeline and the same pre-registered k rule as v1.

- **k sweep:** silhouettes for k = 2–8 are 0.217, **0.256**, 0.243, 0.239, 0.243, **0.247**, 0.241. Only k = 3 and
  k = 7 are within 0.01 of the best, and both pass (a) and (b), so the rule picks **k = 7** (silhouette 0.247).
- **Stability over 10 k-means seeds:** mean pairwise ARI 0.92, minimum 0.77. v1 had 1.00.
- **Persona sanity ARI (pure players):** 0.47. v1 had 0.85.

Centres in original units. Names are **not** assigned; "nearest v1" is the Hungarian match.

| v2 cluster | Players | Completion | Trophy | Genre div. | log h/game | Top-game share | log activity | Online | log games | Suggested (nearest persona) | Nearest v1 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 182 | 0.09 | 0.07 | 0.81 | 1.07 | 0.46 | 1.50 | 0.33 | 1.92 | casual | Casual |
| 1 | 53 | 0.09 | 0.10 | 0.52 | 1.75 | 0.90 | 3.64 | 0.95 | 1.91 | devotee | The Main |
| 2 | 76 | 0.14 | 0.11 | 0.50 | 1.71 | 0.90 | 3.54 | 0.04 | 1.94 | devotee | Devotee |
| 3 | 120 | 0.32 | 0.20 | 0.83 | 2.55 | 0.43 | 3.31 | 0.82 | 2.25 | competitor | Competitor |
| 4 | 98 | 0.55 | 0.39 | 0.81 | 2.29 | 0.48 | 2.65 | 0.32 | 1.97 | completionist | Completionist |
| 5 | 39 | 0.11 | **0.51** | 0.82 | 1.27 | 0.48 | 1.81 | 0.33 | 2.08 | completionist | none (new: 32 of 39 are trophy hunters) |
| 6 | 99 | 0.14 | 0.12 | 0.95 | 1.26 | 0.25 | 2.41 | 0.38 | 3.03 | explorer | Explorer |

Figures: `06_choose_k.png`, `07_pca_v2.png`, `05_v2_features_by_persona.png`.

## 5. v1 vs v2

- **k:** v1 = 6, v2 = 7.
- **Match distances** (v1 SD units):

  | v1 archetype | Distance to matched v2 centre |
  |---|---|
  | Competitor | 0.94 |
  | Explorer | 1.43 |
  | Devotee | 1.71 |
  | Casual | 1.79 |
  | Completionist | 1.89 |
  | The Main | 1.97 |

- **Centre differences:** the biggest are completion (−0.5 to −1.3 SD) and trophy rate (−0.6 to −1.6 SD) in every
  archetype. Devotee and The Main also gain +0.6 to +0.8 SD of genre diversity. Every other feature moves by
  0.4 SD or less. See `08_centres_v1_v2.png` and `sim_v2/centres_v1_v2.csv`.
- **Agreement between the two models:**

  | Players assigned | ARI | Reassigned |
  |---|---|---|
  | v1's 667 | 0.56 | 22.0% |
  | v2's 667 | 0.65 | 19.9% |

  Main moves among v1's players:
  - Casual → v2 Completionist: 35
  - Casual → trophy-hunter cluster: 36
  - Competitor → v2 Completionist: 38

  Among v2's players:
  - Competitor → Completionist: 39
  - Casual → trophy-hunter cluster: 20
  - Casual → Completionist: 15
- **v2's own seed noise** (generator seeds 0–4, each fitted at k = 7 and compared with seed 42):
  - The rule picks k = 3, 3, 7, 6, 3.
  - ARI is 0.64–0.87, with 6.7–23.7% of players reassigned.
  - So the v1 ↔ v2 difference on v2's players (ARI 0.65) is about the size of v2's seed-to-seed difference.
- **Real users:** 5 users have ≥ 5 manual-log games. I read them through a read-only database session on the
  endpoint's own data path. **None changes archetype.**

  | User | Games | v1 | v2 (≈ v1) |
  |---|---|---|---|
  | user 1 | 12 | Competitor 48% | Competitor 39% |
  | user 2 | 12 | Completionist 49% | Completionist 52% |
  | user 3 | 9 | Competitor 57% | Competitor 48% |
  | user 4 | 10 | Competitor 64% | Competitor 47% |
  | user 5 | 5 | Completionist 64% | Completionist 68% |

  v2's percentages use v1's temperature (0.75) as a placeholder; the temperature hasn't been reviewed for v2.

## 6. Sensitivity

**Method:**
- Each variant regenerates the seed-42 population, re-runs the k sweep and the rule, fits at v2's k = 7, and is
  compared with v2.
- The verdict is the robustness check's rule:
  - "Substantial effect" when the rule's k differs or the lower ARI is below 0.8.
  - "No meaningful effect" when the lower ARI is at or above the seed-noise minimum.
  - Otherwise "Small effect".
- The last column is **supplementary**, not pre-registered. It compares the ARI with the seed-noise range only,
  because v2's own seed noise already fails both of the verdict's criteria (k changes, ARI < 0.8).

Seed-noise reference: rule k 3/3/7/6/3; ARI 0.64–0.87; 6.7–23.7% reassigned.

| Variant | Rule k | ARI (v2 players) | ARI (variant players) | % reassigned (v2 / variant players) | Verdict | ARI vs seed noise |
|---|---|---|---|---|---|---|
| rule 1 off | 6 | 0.79 | 0.63 | 12.3 / 21.7 | Substantial effect | **below** |
| rule 2 off (v1 trophies) | 6 | 0.71 | 0.56 | 24.9 / 34.3 | Substantial effect | **below** |
| rule 3 off | 3 | 0.88 | 0.89 | 6.1 / 5.7 | Substantial effect | within |
| rule 4 off | 7 | 0.84 | 0.80 | 7.3 / 9.3 | Substantial effect* | within |
| rule 5 off | 3 | 0.76 | 0.81 | 24.6 / 20.8 | Substantial effect | within |
| engagement × 0.5 | 8 | 0.81 | 0.83 | 8.7 / 8.1 | Substantial effect | within |
| engagement × 1.5 | 6 | 0.70 | 0.66 | 18.4 / 22.0 | Substantial effect | within |
| E = 1.5 | 3 | 0.78 | 0.77 | 16.2 / 16.3 | Substantial effect | within |
| E = 2.5 | 7 | 1.00 | 1.00 | 0 / 0 | No meaningful effect | within |
| M = 0.4 | 8 | 0.88 | 0.88 | 6.3 / 6.1 | Substantial effect | within |
| M = 0.8 | 3 | 0.94 | 0.94 | 2.8 / 2.7 | Substantial effect | within |
| hunters 5% | 3 | 0.74 | 0.77 | 23.4 / 22.3 | Substantial effect | within |
| hunters 20% | 3 | 0.93 | 0.92 | 3.1 / 3.7 | Substantial effect | within |

\* Rule 4 off keeps k = 7. Its lower ARI is 0.7997, just under 0.8.

**What the results depend on:**
- **Rules 1 and 2** are the design choices that matter most. Each one, switched off, moves the clusters beyond
  seed noise.
- **k** depends on almost everything (rule 3, rule 5, E = 1.5, M, hunter share and engagement strength all flip
  it), but so does the generator seed. **k is not identified in v2**: k = 3 and k = 7 sit within 0.01 of each
  other in silhouette.
- **The trophy-hunter cluster** exists because of rule 5. With 5% hunters, or with rule 5 off, the rule picks k = 3.
- **E** hardly matters: under rule 2 it only shapes trophies after the main story on completed games. **M** and the
  **engagement strengths** change k but stay within seed noise on ARI.
