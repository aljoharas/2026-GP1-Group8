"""v2-core final training (steps 1-3): generator v2 with rules 1-4 (rule 5 off), 500 players per
persona, seed 42, k = 6, KMeans(n_init=20, random_state=42), same scaler.

k = 6 is adopted by majority across generator seeds: the pre-set k rule picked k = 6 on seeds 0-4
and k = 3 on seed 42 (gap 0.0126 vs the 0.01 window). This choice was made after seeing the
seed-42 result.

Writes notebooks/v2_core_final/ (results.json, tables, a DRAFT model JSON with v1's names and
descriptions as proposals plus a family field). Nothing in models/ is touched; names,
descriptions and temperature await confirmation.

    python notebooks/v2_core_final.py
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score, silhouette_score

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archetype_v2_lib as L  # noqa: E402

sys.path.insert(0, str(L.REPO / "backend" / "recommender"))
from archetypes import largest_remainder, match_probabilities  # noqa: E402

N, K = 500, 6
TEMPERATURES = [0.5, 0.6, 0.75, 1.0]
FAMILY = {"Casual": "Light", "Explorer": "Light", "Competitor": "Committed", "Completionist": "Committed",
          "Devotee": "One-game", "The Main": "One-game"}
OUT = L.REPO / "notebooks" / "v2_core_final"
OUT.mkdir(exist_ok=True)
FN = L.FN
CORE = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})

plays, cal, CAT, _, _ = L.load_inputs(L.REPO / "data" / "steam-200k.csv", L.REPO / "data" / "steam_catalogue.csv")


def population(seed):
    return L.population(L.sim2.generate_players(cal, CAT, N, L.MIX_SHARE, seed, CORE))


# --- 1. Final training --------------------------------------------------------------
run = population(L.SEED)
model = KMeans(n_clusters=K, n_init=L.N_INIT, random_state=L.SEED).fit(run["Z"])
run.update(k=K, model=model)
sil = float(silhouette_score(run["Z"], model.labels_))
stab = L.stability(run)  # KMeans random_state 1..10 at k = 6
A = L.Assigner.from_run(run)

agree = {}
for s in L.NOISE_SEEDS:
    r = population(s)
    m = KMeans(n_clusters=K, n_init=L.N_INIT, random_state=L.SEED).fit(r["Z"])
    other = L.Assigner(r["impute"], r["scaler"].mean_, r["scaler"].scale_, m.cluster_centers_)
    agree[s] = {"seed 42 players": float(adjusted_rand_score(A.assign(run["raw"]), other.assign(run["raw"]))),
                f"seed {s} players": float(adjusted_rand_score(A.assign(r["raw"]), other.assign(r["raw"])))}
agree_vals = [v for d in agree.values() for v in d.values()]
print(f"players {len(run['players'])}, silhouette {sil:.4f}")
print(f"stability over 10 restarts: mean pairwise ARI {stab['mean_pairwise']:.4f} (min {stab['min_pairwise']:.4f})")
print(f"agreement with k = 6 fits on seeds 0-4: ARI {min(agree_vals):.3f}-{max(agree_vals):.3f}")
for s, d in agree.items():
    print("  seed", s, {p: round(v, 3) for p, v in d.items()})

# --- 2. Names by Hungarian match to v1.0.0 ---------------------------------------------
other = L.in_units_of(L.V1, A)
mapping, dist = L.match(L.V1.c, other)
name_of = {j: L.V1_NAMES[i] for i, j in mapping.items()}
D = pd.DataFrame(np.linalg.norm(L.V1.c[:, None, :] - other[None, :, :], axis=2),
                 index=[f"v1 {n}" for n in L.V1_NAMES], columns=[f"v2-core {j} ({name_of[j]})" for j in range(K)])
D.round(3).to_csv(OUT / "distance_v1_to_v2core_v1sd.csv")
desc_v1 = {c["name"]: c["description"] for c in L.MODEL_V1["clusters"]}
c1 = {c["name"]: c["centre"] for c in L.MODEL_V1["clusters"]}
c2 = A.centres_original()
shares = np.bincount(model.labels_, minlength=K) / len(model.labels_)
rows = []
for j in range(K):
    n = name_of[j]
    i = L.V1_NAMES.index(n)
    rows.append({"cluster": j, "proposed name": n, "family": FAMILY[n], "share": shares[j],
                 "match distance (v1 SD)": dist[i],
                 "nearest v1 to this cluster": L.V1_NAMES[int(D.iloc[:, j].to_numpy().argmin())],
                 **{f"{f} v1": c1[n][f] for f in FN}, **{f"{f} v2": c2[j, fi] for fi, f in enumerate(FN)}})
names_tab = pd.DataFrame(rows).set_index("cluster")
names_tab.round(4).to_csv(OUT / "names_and_centres.csv")
side = pd.concat({"v1": pd.DataFrame({n: c1[n] for n in L.NAME_ORDER}).T[FN],
                  "v2-core": pd.DataFrame(c2, columns=FN, index=[name_of[j] for j in range(K)]).loc[L.NAME_ORDER]}, axis=1)
side = side.swaplevel(axis=1)[[(f, v) for f in FN for v in ("v1", "v2-core")]]
side.round(3).to_csv(OUT / "centres_side_by_side.csv")
print(D.round(2).to_string())
print(names_tab[["proposed name", "family", "share", "match distance (v1 SD)", "nearest v1 to this cluster"]].round(3).to_string())
print(side.round(2).to_string())

# Composition by persona
comp = pd.crosstab(run["group"], pd.Series([name_of[c] for c in model.labels_], name="cluster"))[L.NAME_ORDER]
comp.to_csv(OUT / "composition.csv")
print(comp.to_string())

# Draft model JSON: v1's names and descriptions as proposals, with a family field
draft = OUT / "archetype_model_v2_core_draft.json"
names = {j: name_of[j] for j in range(K)}
L.export_model(run, names, {j: desc_v1[name_of[j]] for j in range(K)}, "2.0.0-draft", draft, stab,
               L.persona_ari(run), extra_training={
                   "n_per_persona": N, "generator": "archetype_sim_v2, rules 1-4 (rule 5 off): v2-core",
                   "k_decision": "k = 6 by majority across generator seeds: the pre-set rule picked 6 on seeds "
                                 "0-4 and 3 on seed 42 (gap 0.0126 vs the 0.01 window); chosen after seeing "
                                 "the seed-42 result",
                   "status": "DRAFT: names, descriptions and temperature not confirmed"})
m = json.loads(draft.read_text())
for c in m["clusters"]:
    c["family"] = FAMILY[c["name"]]
draft.write_text(json.dumps(m, indent=2) + "\n")
assert (L.Assigner.from_json(m).assign(run["raw"]) == model.labels_).all()

# --- 3. Temperature: simulated players ---------------------------------------------------
pure = run["is_pure"]
temp = {}
for T in TEMPERATURES:
    top = np.array([max(largest_remainder(match_probabilities(z, model.cluster_centers_, T))) for z in run["Z"]])
    temp[T] = {"pure median": float(np.median(top[pure])), "pure p10": float(np.percentile(top[pure], 10)),
               "pure p90": float(np.percentile(top[pure], 90)), "mixed median": float(np.median(top[~pure])),
               "at >= 90%": float((top >= 90).mean())}
temp_tab = pd.DataFrame(temp).T.rename_axis("T")
temp_tab.round(3).to_csv(OUT / "temperature_simulated.csv")
print(temp_tab.round(3).to_string())

json.dump({
    "players": len(run["players"]), "silhouette": sil, "stability": stab, "persona_ari": L.persona_ari(run),
    "agreement_k6_seeds_0_4": agree, "agreement_range": [min(agree_vals), max(agree_vals)],
    "cluster_names_by_match": {int(j): n for j, n in name_of.items()}, "match_distance_v1_sd": {name_of[mapping[i]]: float(dist[i]) for i in mapping},
    "shares": {name_of[j]: float(shares[j]) for j in range(K)}, "temperature_simulated": temp,
}, open(OUT / "results.json", "w"), indent=2)
print("wrote", OUT.relative_to(L.REPO))
