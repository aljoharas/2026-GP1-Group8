# v2-core: v2 without trophy hunters

**What v2-core is:** generator v2 with rule 5 (trophy hunters) switched off. Rules 1–4 and every other parameter
are unchanged.

**Why:** rule 5's 10% share has no empirical source. Trophy hunters will be re-added only if the survey supports
them, with the share taken from survey data.

**Setup:**
- 500 players per persona (3,333 players), seed 42 plus generator seeds 0–4.
- Same pipeline and k rule as before.
- Served model and model card untouched.

Script: `notebooks/sim_v2_core_experiment.py`. Results: `notebooks/sim_v2_core/`. Analysis-only model JSONs are
saved there too and aren't wired into the app.

## Is v2-core's k stable? No.

The rule picks **k = 3 on seed 42 and k = 6 on seeds 0–4**. The choice is on a knife edge. The silhouette at k = 3
is always the best, and k = 6 is close behind:

| Seed | 42 | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|
| silhouette k = 3 | 0.273 | 0.266 | 0.262 | 0.263 | 0.257 | 0.262 |
| silhouette k = 6 | 0.260 | 0.257 | 0.253 | 0.260 | 0.249 | 0.257 |
| gap | **0.0126** | 0.0085 | 0.0095 | 0.0030 | 0.0088 | 0.0041 |
| rule k | **3** | 6 | 6 | 6 | 6 | 6 |

The rule only considers k values within 0.01 of the best. On seed 42 the gap is 0.0126, so k = 6 isn't
considered at all.

**Silhouette by k** (mean over the 6 seeds, with the range):

| k | Silhouette |
|---|---|
| 2 | 0.224 (0.222–0.228) |
| 3 | **0.264** (0.257–0.273) |
| 4 | 0.235 (0.230–0.241) |
| 5 | 0.248 (0.241–0.253) |
| 6 | **0.256** (0.249–0.260) |
| 7 | 0.237 (0.233–0.243) |
| 8 | 0.230 (0.226–0.236) |

**Stability:**
- Within each population, the clusters are stable across k-means restarts (ARI 0.996–1.000).
- Seed to seed, the k = 3 solution agrees closely with seed 42 (ARI 0.94–0.98, 0.6–2.2% reassigned). The k = 6
  solution agrees reasonably (ARI 0.91–0.97).
- So both solutions are stable in themselves. Only the rule's choice between them flips.
- Persona ARI (pure players) is 0.41 at seed 42, k = 3.

## Does it recover v1's six archetypes?

**At the rule's k on seed 42 (k = 3): no.**

- Only three of v1's archetypes have a match: Competitor (0.83 SD away), Casual (2.00) and Devotee (2.20).
- Completionist, Explorer and The Main have no match. Their players merge into the other clusters.

| v2-core k = 3 cluster | Players | Completion | Trophy | Online | Top-game share | Matched v1 archetype |
|---|---|---|---|---|---|---|
| 0 | 1,459 | 0.09 | 0.08 | 0.36 | 0.38 | Casual (absorbs Explorer) |
| 1 | 1,083 | 0.42 | 0.27 | 0.54 | 0.43 | Competitor (absorbs Completionist) |
| 2 | 791 | 0.14 | 0.10 | 0.40 | 0.87 | Devotee (absorbs The Main) |

Agreement with the other models, assigning the same players with both:

| Compared with | Players assigned | ARI | Reassigned | Main moves |
|---|---|---|---|---|
| large v1 | v1's players | 0.32 | 51.8% | Completionist → Competitor 652, Explorer → Casual 362, Casual → Competitor 213, The Main → Devotee 201 |
| large v1 | v2-core's players | 0.40 | 41.4% | |
| full v2 (large) | v2's players | 0.44 | 49.5% | Explorer → Casual 514, Completionist → Competitor 471, The Main → Devotee 290 |
| full v2 (large) | v2-core's players | 0.49 | 45.8% | |

**At k = 6 (what seeds 0–4 pick; supplementary for seed 42): mostly yes.**

- On every seed, Hungarian matching pairs all six v1 archetypes with a v2-core cluster (distances 0.97–2.12 in
  large-v1 SD units).
- Each v1 archetype's nearest v2-core cluster is its own match.
- On every seed, 5 of the 6 are also mutual nearest. The exception is Completionist: the v2-core Completionist
  cluster (completion 0.56, trophy 0.38) sits slightly closer to v1's Competitor (1.73 SD) than to v1's
  Completionist (1.85 SD).
- On seed 42, at k = 6:

  | Players assigned | ARI vs large v1 | Reassigned |
  |---|---|---|
  | v1's | 0.49 | 21.5% |
  | v2-core's | 0.70 | 15.3% |

- The main moves into Completionist are Casual 237, Competitor 207 and Explorer 129.
- Centre shifts against large v1 look like full v2's: completion −0.5 to −1.1 SD and trophy rate −0.8 to −1.6 SD
  everywhere, and +0.7 to +0.8 SD of genre diversity for Devotee and The Main. Every other feature moves by
  0.32 SD or less.

## Real users

All 5 users with ≥ 5 manual-log games were assigned through a read-only session. Changes against the served v1:

| Model | Users who change |
|---|---|
| v2-core, rule k (k = 3, seed 42) | **2 of 5.** user 2 and user 5, both Completionist → Competitor (no completionist cluster exists at k = 3). The three Competitors are unchanged. |
| v2-core at k = 6 (supplementary) | **0 of 5.** |

Tables: `sim_v2_core/real_users_v2_core.csv`, `sim_v2_core/real_users_v2_core_k6.csv`.

## Reading

Removing the trophy hunters takes away the 7th cluster, as expected. But it leaves v2-core with two competing
solutions, k = 3 and k = 6, separated by about 0.01 in silhouette. Which one the pre-registered rule picks depends
on the generator seed. The k = 6 solution recovers v1's six archetypes in a recognisable form, with lower
completion and trophy levels and a weaker Completionist. The k = 3 solution merges them into
Casual / Competitor / Devotee.
