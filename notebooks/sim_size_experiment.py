"""Population-size experiment: v1 and v2 with 500 players per persona (mix share 0.25, 3,333 players).

Reason: reduce Monte Carlo noise in k selection; not tuned to any result. No rule or parameter
changes; the served model and the model card are not touched. Same pipeline and k rule as the
v2 notebook (archetype_v2_lib). Seeds: 42 plus generator seeds 0-4.

Run from the repo root (needs matplotlib-free deps only):
    python notebooks/sim_size_experiment.py
Writes notebooks/sim_v2_size/results.json and tables.
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import adjusted_rand_score

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archetype_v2_lib as L  # noqa: E402

N = 500
SEEDS = [L.SEED] + L.NOISE_SEEDS
REPO = L.REPO
OUT = REPO / "notebooks" / "sim_v2_size"
OUT.mkdir(exist_ok=True)

plays, cal, CAT, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")


def generate(version, seed):
    if version == 1:
        return L.sim.generate_players(cal, n_per_persona=N, mix_share=L.MIX_SHARE, seed=seed)
    return L.sim2.generate_players(cal, CAT, N, L.MIX_SHARE, seed)


def hunter_cluster(run, k=None):
    """The cluster with the highest share of trophy hunters: its size, hunter share, and the
    share of all hunters it holds."""
    labels = run["model"].labels_ if k is None else run["fits"][k].labels_
    h = np.array([p["hunter"] for p in run["players"]])
    tab = pd.crosstab(labels, h)
    share = tab[True] / tab.sum(axis=1)
    c = int(share.idxmax())
    return {"cluster": c, "size": int(tab.loc[c].sum()), "hunter_share_of_cluster": float(share[c]),
            "share_of_all_hunters": float(tab.loc[c, True] / h.sum()), "hunters": int(h.sum())}


results = {"n_per_persona": N, "seeds": SEEDS}
runs = {}
for version in (1, 2):
    t = time.time()
    runs[version] = {s: L.train(generate(version, s)) for s in SEEDS}
    rs = runs[version]
    base = rs[L.SEED]
    K = base["k"]
    sil = pd.DataFrame({s: r["sil"] for s, r in rs.items()}).rename_axis("k")
    sil_summary = pd.DataFrame({"mean": sil.mean(axis=1), "min": sil.min(axis=1), "max": sil.max(axis=1)})
    sil.round(4).to_csv(OUT / f"v{version}_silhouette_by_seed.csv")
    pd.concat({s: r["checks"] for s, r in rs.items()}, names=["seed"]).round(4).to_csv(OUT / f"v{version}_k_rule_checks.csv")

    stab = {s: L.stability(r) for s, r in rs.items()}  # 10 KMeans seeds at each population's own rule k

    # Seed-to-seed: every other seed's model at seed 42's k vs seed 42's, on both populations
    a42 = L.Assigner.from_run(base)
    names42 = {c: f"c{c}" for c in range(K)}
    seed_to_seed = {}
    for s in L.NOISE_SEEDS:
        r = rs[s]
        res = L.compare(a42, names42, L.Assigner.from_run(r, r["fits"][K]),
                        {"seed 42 players": base["raw"], f"seed {s} players": r["raw"]}, f"seed {s}")
        seed_to_seed[s] = {p: {"ari": d["ari"], "changed": d["changed"]} for p, d in res["pops"].items()}
    s2s_ari = [d["ari"] for v in seed_to_seed.values() for d in v.values()]
    s2s_chg = [d["changed"] for v in seed_to_seed.values() for d in v.values()]

    results[f"v{version}"] = {
        "players": len(base["players"]),
        "rule_k_by_seed": {s: int(r["k"]) for s, r in rs.items()},
        "reason_by_seed": {s: r["reason"] for s, r in rs.items()},
        "silhouette_by_k": sil_summary.round(4).to_dict("index"),
        "stability_by_seed": stab,
        "seed_to_seed": seed_to_seed,
        "seed_to_seed_ari_range": [min(s2s_ari), max(s2s_ari)],
        "seed_to_seed_changed_range": [min(s2s_chg), max(s2s_chg)],
        "persona_ari_seed42": L.persona_ari(base),
    }
    print(f"v{version}: {len(base['players'])} players, {time.time() - t:.0f}s")
    print("  rule k by seed:", results[f"v{version}"]["rule_k_by_seed"])
    print(sil_summary.round(4).to_string())
    print("  stability (mean pairwise ARI) by seed:", {s: round(v["mean_pairwise"], 3) for s, v in stab.items()})
    print(f"  seed-to-seed ARI at k = {K}: {min(s2s_ari):.3f}-{max(s2s_ari):.3f}, "
          f"reassigned {min(s2s_chg):.1%}-{max(s2s_chg):.1%}")

# --- v2: trophy-hunter cluster -------------------------------------------------------
hc = {s: {"rule_k": int(r["k"]), **hunter_cluster(r)} for s, r in runs[2].items()}
hc7 = {s: hunter_cluster(r, 7) for s, r in runs[2].items()}
results["v2"]["hunter_cluster_at_rule_k"] = hc
results["v2"]["hunter_cluster_at_k7"] = hc7
print("hunter cluster at rule k:", {s: (v["rule_k"], round(v["hunter_share_of_cluster"], 2), round(v["share_of_all_hunters"], 2)) for s, v in hc.items()})
print("hunter cluster at k = 7:", {s: (round(v["hunter_share_of_cluster"], 2), round(v["share_of_all_hunters"], 2)) for s, v in hc7.items()})

# --- v2 vs v1 at the larger size (seed 42, each at its rule k) --------------------------
b1, b2 = runs[1][L.SEED], runs[2][L.SEED]
A1, A2 = L.Assigner.from_run(b1), L.Assigner.from_run(b2)
# Name the large v1 clusters by matching them to the frozen v1.0.0 archetypes
m1, _ = L.match(L.V1.c, L.in_units_of(L.V1, A1))
names1 = {j: L.V1_NAMES[i] for i, j in m1.items()}
for j in range(len(A1.c)):
    names1.setdefault(j, f"unmatched large-v1 cluster {j}")
cmp = L.compare(A1, names1, A2, {"v1 players": b1["raw"], "v2 players": b2["raw"]}, "v2")
v2_hunter = hc[L.SEED]["cluster"]
results["v1_vs_v2"] = {
    "k": {"v1": int(b1["k"]), "v2": int(b2["k"])},
    "large_v1_names": {int(k): v for k, v in names1.items()},
    "v2_name_by_match": {int(k): v for k, v in cmp["other_name"].items()},
    "v2_hunter_cluster": v2_hunter,
    "match_distance_v1_sd": cmp["dist"],
    "pops": {p: {"ari": d["ari"], "changed": d["changed"]} for p, d in cmp["pops"].items()},
}
for p, d in cmp["pops"].items():
    d["moves"].to_csv(OUT / f"moves_v1_v2_{p.replace(' ', '_')}.csv")
    print(f"v1 vs v2, {p}: ARI {d['ari']:.3f}, reassigned {d['changed']:.1%}")
    print(d["moves"].to_string())
print("match distances (large-v1 SD):", {k: round(v, 2) for k, v in cmp["dist"].items()})
print("v2 names by match:", results["v1_vs_v2"]["v2_name_by_match"], "| hunter cluster:", v2_hunter)

# Large v1 against the frozen model (does more players reproduce v1.0.0?)
fz = L.compare(L.V1, dict(enumerate(L.V1_NAMES)), A1, {"frozen v1 players (n=100)": L.population(L.players_v1(cal))["raw"],
                                                       "large v1 players": b1["raw"]}, "large v1")
results["large_v1_vs_frozen"] = {p: {"ari": d["ari"], "changed": d["changed"]} for p, d in fz["pops"].items()}
print("large v1 vs frozen v1.0.0:", {p: round(d["ari"], 3) for p, d in fz["pops"].items()})

(OUT / "results.json").write_text(json.dumps(results, indent=2, default=float) + "\n")
print("wrote", (OUT / "results.json").relative_to(REPO))
