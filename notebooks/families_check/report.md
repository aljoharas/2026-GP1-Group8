# Are the three families supported by model 2.0.0?

This is an analysis only. The served model, the families and the blend rule are unchanged.

- Script: `notebooks/families_check.py`
- Tables: this folder
- Dendrogram: `notebooks/figures/v2/families_dendrogram.png`

**Decision rule** (fixed before running). The families are confirmed only if all three hold:
- **(a)** For every archetype, its nearest centre is its family partner.
- **(b)** For every archetype, its family partner is the most common second-highest archetype among its players.
- **(c)** More than 60% of close calls (top two within 10 points) are same-family.

**Setup:**
- Seed 42 is the served JSON, scored on its own 3,333 training players.
- Seeds 0–4 are each seed's own k = 6 fit, with clusters named by Hungarian match to the served centres.
- Scoring is the served code at T = 0.75.

## Verdict: not confirmed

**(c) fails on every seed.** Only 33–41% of close calls are same-family. (a) and (b) hold on the served model, but
not on every other seed.

| Seed | First 3 Ward merges = families | (a) nearest = partner | (b) top second = partner | (c) close calls same-family | Confirmed |
|---|---|---|---|---|---|
| **42 (served)** | yes | all 6 | all 6 | **39.8%** (of 294) | **no** |
| 0 | yes | all 6 | all 6 | 40.5% (of 353) | no |
| 1 | yes | all 6 | fails: The Main | 36.3% (of 347) | no |
| 2 | yes | fails: Competitor | fails: Competitor, The Main | 41.3% (of 315) | no |
| 3 | yes | all 6 | all 6 | 33.2% (of 388) | no |
| 4 | yes | all 6 | all 6 | 37.5% (of 328) | no |

## 1. Centre distances (served model)

Euclidean distance between centres, in SD units of the 2.0.0 scaler (the scaled space is the SD units):

| | Casual | Explorer | Competitor | Completionist | Devotee | The Main |
|---|---|---|---|---|---|---|
| Casual | 0 | **2.48** | 3.16 | 3.84 | 3.28 | 3.64 |
| Explorer | **2.48** | 0 | 3.15 | 3.93 | 4.24 | 4.49 |
| Competitor | 3.16 | 3.15 | 0 | **2.57** | 3.54 | 2.81 |
| Completionist | 3.84 | 3.93 | **2.57** | 0 | 4.03 | 4.33 |
| Devotee | 3.28 | 4.24 | 3.54 | 4.03 | 0 | **2.58** |
| The Main | 3.64 | 4.49 | 2.81 | 4.33 | **2.58** | 0 |

The largest single-feature gap per pair is in `seed42_maxgap.csv`. Every pair differs by at least 1.66 SD in some
feature.

- **Nearest centres:** each archetype's nearest centre is its family partner.
- **Competitor is the exception in the margins.** Its two nearest are close together: Completionist at 2.57 and The
  Main at 2.81. On seed 2 the order flips and The Main is nearest.

## 2. Ward linkage (served model)

| Merge | Clusters joined | Height |
|---|---|---|
| 1 | Casual + Explorer | 2.48 |
| 2 | Competitor + Completionist | 2.57 |
| 3 | Devotee + The Main | 2.58 |
| 4 | Light + Committed | 4.32 |
| 5 | + One-game | 4.93 |

**The first three merges are exactly the three families**, on all six seeds. The families are well separated as
groups: the merges between families come at 4.3–4.9, against about 2.5 within a family.

## 3. Second choice (served scoring, T = 0.75, 3,333 players)

Second-highest archetype, as a % of each primary archetype's players:

| Primary ↓ / second → | Casual | Explorer | Competitor | Completionist | Devotee | The Main |
|---|---|---|---|---|---|---|
| Casual | – | **62.6** | 11.4 | 2.9 | 16.5 | 6.7 |
| Explorer | **78.3** | – | 18.0 | 2.4 | 1.0 | 0.3 |
| Competitor | 11.8 | 18.3 | – | **39.5** | 2.5 | 27.8 |
| Completionist | 7.2 | 1.8 | **86.5** | – | 4.4 | 0.0 |
| Devotee | 23.3 | 0.9 | 3.1 | 4.6 | – | **68.1** |
| The Main | 12.7 | 0.3 | 36.5 | 0.6 | **49.8** | – |

Counts are in `seed42_counts.csv`.

Every archetype's most common runner-up is its partner. Two are narrow:
- **Competitor:** Completionist 39.5% against The Main 27.8%.
- **The Main:** Devotee 49.8% against Competitor 36.5%.

On seeds 1–2, The Main's runner-up flips to Competitor.

**Close calls:** 294 players (8.8%) have their top two within 10 points. Only **39.8%** of them are same-family.

The most common cross-family close calls:

| Pair | Players |
|---|---|
| Casual / Competitor | 36 |
| Competitor / The Main | 29 |
| Competitor / Explorer | 27 |
| Casual / Devotee | 22 |
| Casual / The Main | 16 |

On seeds 0–4 the same pairs lead, with Competitor / The Main first on four of them (45–58 players).

## Reading

The families are real as **groupings of centres**: Ward linkage recovers them on every seed, and each centre's
nearest neighbour is its partner. But they don't describe **where players are undecided**.

Most close calls sit across families:
- around **Competitor**, which borders The Main through online play and Casual and Explorer through hours;
- around **Casual**, the largest cluster and the most central one.

So under the fixed rule, the families are not confirmed. The failing parts:
- **(c), on every seed.** This is the main failure.
- **Competitor** under (a) on seed 2.
- **The Main**, and on seed 2 **Competitor**, under (b) on seeds 1–2.

The current blend rule (same family, within 10 points) fires for about 117 of 3,333 training players (3.5%).
