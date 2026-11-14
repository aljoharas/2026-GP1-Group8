# Population-size experiment: 500 players per persona

v1 and v2 were each generated with 500 pure players per persona and the mix share unchanged at 0.25, which gives
3,333 players per population. Each was run on seed 42 and generator seeds 0–4, with k = 2..8, the same k rule,
`KMeans(n_init=20, random_state=42)`, and no rule or parameter changes. The reason for the larger population is to
reduce Monte Carlo noise in k selection; it was not tuned to any result. The served model and the model card are
untouched.

Script: `notebooks/sim_size_experiment.py`. Results: `notebooks/sim_v2_size/` (`results.json`, silhouettes, k-rule
checks, movement tables).

## Does k stabilise?

- **v1: yes.** The rule picks **k = 6 on all 6 seeds**. At n = 100 the frozen model was also k = 6, so v1's
  choice holds up.
- **v2: mostly, but no.** The rule picks **k = 7 on 5 of the 6 seeds** and k = 6 on seed 4. At n = 100 it picked
  3, 3, 7, 6, 3 (other seeds) and 7 (seed 42).

## Details

| | v1 (n = 3,333) | v2 (n = 3,333) |
|---|---|---|
| Rule k by seed (42, 0, 1, 2, 3, 4) | 6, 6, 6, 6, 6, 6 | 7, 7, 7, 7, 7, **6** |
| k-means stability (mean pairwise ARI over 10 seeds, per population) | 0.999–1.000 | 0.992–1.000 |
| Seed-to-seed ARI vs seed 42, at seed 42's k | 0.970–0.988 (0.5–1.2% reassigned) | 0.913–0.959 on seeds 0–3; **0.735–0.741 on seed 4** (1.8–17.4% reassigned overall) |
| Persona ARI (pure players, seed 42) | 0.875 | 0.518 |

**Silhouette by k** (mean over the 6 seeds, with the range):

| k | v1 | v2 |
|---|---|---|
| 2 | 0.259 (0.243–0.265) | 0.214 (0.213–0.214) |
| 3 | 0.297 (0.293–0.299) | **0.245** (0.240–0.254) |
| 4 | **0.326** (0.321–0.331) | 0.224 (0.220–0.230) |
| 5 | 0.319 (0.313–0.326) | 0.231 (0.226–0.234) |
| 6 | **0.326** (0.321–0.331) | 0.239 (0.233–0.243) |
| 7 | 0.299 (0.289–0.304) | 0.239 (**0.220**–0.247) |
| 8 | 0.274 (0.265–0.281) | 0.225 (0.220–0.232) |

- **v1:** the top three candidates (k = 4, 5, 6) are within 0.01 on every seed, and the rule takes the largest
  passing one, k = 6, every time.
- **v2:** the curve is still flat, with k = 3, 6 and 7 within 0.01 of each other. k = 7 is the largest that passes
  on five seeds. On seed 4, k-means at k = 7 lands on a worse solution (silhouette 0.220), so k = 7 drops out of
  the candidates and the rule takes k = 6.

## v2: does the trophy-hunter cluster still appear?

**Yes, on the five seeds where the rule picks k = 7.** There, one cluster of 200–226 players is 80–89% trophy
hunters and holds 49–53% of all hunters.

On seed 4 (k = 6) it does **not** appear: the cluster with the most hunters is only 23% hunters. Even when that
population is fitted at k = 7, the most-hunter cluster is only 21% hunters. So on seed 4 the hunter cluster is
missing whichever k is used.

## v2 vs v1 at the larger size (seed 42)

Large v1 (k = 6) reproduces the frozen v1.0.0: ARI 0.96 on both populations. Its clusters are named by matching
them to v1.0.0.

| Players assigned | ARI | Reassigned |
|---|---|---|
| v1's 3,333 | 0.565 | 21.6% |
| v2's 3,333 | 0.640 | 19.9% |

- **Matching:** v2's clusters match all six v1 archetypes. Distances in large-v1 SD units: Competitor 0.88,
  Explorer 1.66, Completionist 1.70, Casual 1.73, The Main 1.77, Devotee 1.78. The 7th cluster, the hunter
  cluster, is left unmatched.
- **Main moves on v1's players:**
  - Competitor → v2 Completionist: 173
  - Casual → hunter cluster: 157
  - Casual → v2 Completionist: 138

These are almost exactly the n = 100 results (ARI 0.56 / 0.65, 22.0% / 19.9% reassigned).

## Reading

The extra players took out v1's residual noise; v1's k = 6 is robust. For v2 they cut the noise a lot (from 3
distinct k across 6 seeds to 2), and they confirm the trophy-hunter cluster as a regular result. But v2 still has
one seed in six where k-means misses the hunter cluster and the rule picks a different k. The v1 ↔ v2 disagreement
(about 20% reassigned) is a real difference between the generators, not noise: it doesn't shrink with 5× the
players.
