# v2-core final model: steps 1–4 (awaiting confirmation)

**What was trained:** v2-core, meaning generator v2 with rules 1–4 and rule 5 (trophy hunters) off. 500 players
per persona (3,333 players), seed 42, k = 6, StandardScaler, `KMeans(n_init=20, random_state=42)`.

**How k = 6 was chosen:** by majority across generator seeds. The pre-set k rule picked k = 6 on seeds 0–4 and
k = 3 on seed 42 (gap 0.0126 vs the 0.01 window). This choice was made after seeing the seed-42 result.

**Status at the time (steps 1–4):** nothing in `models/` had changed yet. The names, descriptions and temperature
were then confirmed and the model served as 2.0.0, later 2.0.1. Script: `notebooks/v2_core_final.py`. The draft
model JSON and the real-user script (`v2_core_real_users.py`) are archived in `archetypes dataset/archive_2026-11-25`
and at Git tag `archetypes-experiments-archive`.

## 1. Final training

| | v2-core k = 6 | v1.0.0 |
|---|---|---|
| Silhouette | 0.260 | 0.320 |
| Stability across 10 k-means restarts (mean pairwise ARI) | 0.999 (min 0.998) | 1.000 |
| Agreement with the k = 6 fits on seeds 0–4 (ARI, both player sets) | 0.909–0.970 | (not measured) |
| Persona ARI (pure players) | 0.584 | 0.845 |

Agreement per seed: seed 0 0.97, seed 1 0.91–0.92, seed 2 0.97, seed 3 0.96–0.97, seed 4 0.95–0.96.

## 2. Proposed names (Hungarian match to v1.0.0)

Distances are in v1.0.0 SD units. Nearest v1 is the v1 archetype closest to the cluster's centre.

| Cluster | Proposed name | Family | Share | Distance to v1 | Nearest v1 |
|---|---|---|---|---|---|
| 0 | Devotee | One-game | 13.6% | 1.78 | Devotee |
| 1 | Competitor | Committed | 18.0% | 1.13 | Competitor |
| 2 | Explorer | Light | 17.9% | 1.58 | Explorer |
| 3 | Casual | Light | 26.2% | 1.77 | Casual |
| 4 | The Main | One-game | 9.5% | 1.88 | The Main |
| 5 | Completionist | Committed | 14.9% | 1.84 | **Competitor (1.67)** |

**Centres, v1 → v2-core** (original units):

| | Completion | Trophies | Genre div. | ln(1+h)/game | Top game | Activity | Online | ln games |
|---|---|---|---|---|---|---|---|---|
| Completionist | 0.78 → **0.56** | 0.63 → **0.38** | 0.80 → 0.83 | 2.03 → 2.20 | 0.40 → 0.43 | 2.44 → 2.61 | 0.27 → 0.30 | 2.14 → 2.08 |
| Explorer | 0.35 → 0.12 | 0.28 → 0.08 | 0.97 → 0.93 | 1.13 → 1.20 | 0.18 → 0.27 | 1.99 → 2.20 | 0.32 → 0.35 | 2.94 → 2.92 |
| Competitor | 0.46 → 0.28 | 0.30 → 0.17 | 0.80 → 0.83 | 2.65 → 2.50 | 0.39 → 0.43 | 3.06 → 3.10 | 0.79 → 0.77 | 2.13 → 2.14 |
| The Main | 0.45 → 0.13 | 0.29 → 0.11 | 0.31 → 0.53 | 1.71 → 1.89 | 0.92 → 0.87 | 3.73 → 3.51 | 0.96 → 0.95 | 2.00 → 1.92 |
| Devotee | 0.41 → 0.16 | 0.29 → 0.09 | 0.33 → 0.53 | 1.76 → 1.74 | 0.94 → 0.89 | 3.81 → 3.47 | 0.02 → 0.03 | 1.98 → 1.92 |
| Casual | 0.37 → 0.08 | 0.29 → 0.07 | 0.78 → 0.81 | 0.94 → 1.07 | 0.37 → 0.46 | 1.42 → 1.52 | 0.32 → 0.34 | 1.85 → 1.86 |

**Do the descriptions still fit?**

- **Completionist: flagged.**
  - Current description: "You finish what you start and chase the trophies."
  - The cluster finishes 56% of its games and unlocks 38% of the trophies. That's still by far the highest of the
    six (next is Competitor at 0.28 and 0.17), but it isn't "finishes what it starts".
  - Its centre is also slightly nearer v1's Competitor than v1's Completionist.
  - The description should be relative, not absolute. A proposal for you to edit: *"You see more of your games
    through than most players, trophies included."*
- **Competitor: fits.** "Online, competitive, and in it for the long sessions." Online share is 0.77 and hours per
  game are the highest (about 11h).
- **Explorer: fits.** "Always trying something new, across lots of genres." Genre diversity is 0.93, and the
  library holds about 18 games.
- **The Main: fits.** "One online game has most of your hours." Top-game share is 0.87, online 0.95.
- **Devotee: fits.** "One game you keep coming back to, over and over." Top-game share is 0.89, online 0.03.
  Genre diversity rose from 0.33 to 0.53 for both one-game types, but they still have the lowest.
- **Casual: fits.** "You play when life gives you time." It has the lowest activity and hours per game.

## 3. Temperature

Top match % for each temperature. Simulated players are the 3,333 training players; real users are the 5 users
below.

| T | Simulated pure (median, 10th–90th) | Simulated mixed (median) | Simulated at ≥ 90% | Real users' top % |
|---|---|---|---|---|
| 0.5 | 88% (55–97) | 78% | 41% | 42–94% |
| 0.6 | 81% (50–94) | 70% | 23% | 39–89% |
| **0.75** | **72% (45–88)** | **61%** | **5.3%** | **35–81%** |
| 1.0 | 59% (38–76) | 50% | 0% | 31–68% |

**Recommendation: T = 0.75, unchanged from v1.**

- **It's the only option that doesn't overclaim.** 5.3% of players at 90%+ is close to v1's 6%. T = 0.6 puts 23%
  there, and T = 0.5 puts 41%, both with a silhouette of only 0.26.
- **Mixed players stay visibly lower** than pure players: 61% against 72%.
- **The cost is that real users' leads shrink.** The three Competitors show 35–48% at T = 0.75, against 48–64%
  under v1. User 1 reads closest to undecided (Competitor 35% / Completionist 25%), and stays that way at any T
  except 0.5.
- The Completionists show a clear lead: 75% and 81%.
- The temperature never changes which archetype a user is assigned.

## 4. Real users: v1 vs v2-core

All 5 users were assigned through a read-only session. Each cell shows the top type and the runner-up.

| User | Games | v1 (T = 0.75) | v2-core (T = 0.75) | Changed? |
|---|---|---|---|---|
| user 1 | 12 | Competitor 48% / Devotee 22% | Competitor 35% / Completionist 25% | no |
| user 2 | 12 | Completionist 49% / Competitor 31% | Completionist 75% / Competitor 16% | no |
| user 3 | 9 | Competitor 57% / The Main 27% | Competitor 44% / The Main 31% | no |
| user 4 | 10 | Competitor 64% / Devotee 11% | Competitor 48% / Completionist 33% | no |
| user 5 | 5 | Completionist 64% / Devotee 17% | Completionist 81% / Competitor 7% | no |

The other temperatures are in `real_users.csv`.
