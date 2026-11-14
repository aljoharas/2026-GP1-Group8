"""v2-core: generator v2 with rule 5 (trophy hunters) off; rules 1-4 and every other parameter
unchanged. 500 players per persona, seed 42 plus generator seeds 0-4, same pipeline and k rule.

Reason: rule 5's 10% share has no empirical source; trophy hunters will be re-added only if the
survey supports them, with the share taken from survey data.

Compares v2-core with large v1 and large full v2 (seed 42). Exports the seed-42 v2-core model to
notebooks/sim_v2_core/archetype_model_v2_core.json (a candidate artefact for the real-user check,
not wired into the app). Served model and model card untouched.

    python notebooks/sim_v2_core_experiment.py
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archetype_v2_lib as L  # noqa: E402

N = 500
SEEDS = [L.SEED] + L.NOISE_SEEDS
REPO = L.REPO
OUT = REPO / "notebooks" / "sim_v2_core"
OUT.mkdir(exist_ok=True)
FN = L.FN
CORE_RULES = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})

plays, cal, CAT, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")


def v1_players(seed):
    return L.sim.generate_players(cal, n_per_persona=N, mix_share=L.MIX_SHARE, seed=seed)


def v2_players(seed, rules=None):
    return L.sim2.generate_players(cal, CAT, N, L.MIX_SHARE, seed, rules)


def named_by_frozen_v1(asg):
    """Name a model's clusters by Hungarian match to frozen v1.0.0 (in v1.0.0 SD units).
    Also returns, per v1 archetype, the match distance and whether the match is mutual
    (the matched cluster's nearest v1 centre is that archetype)."""
    other = L.in_units_of(L.V1, asg)
    mapping, dist = L.match(L.V1.c, other)
    names = {j: L.V1_NAMES[i] for i, j in mapping.items()}
    for j in range(len(asg.c)):
        names.setdefault(j, f"unmatched cluster {j}")
    d = np.linalg.norm(L.V1.c[:, None, :] - other[None, :, :], axis=2)
    nearest_v1 = d.argmin(axis=0)       # per other cluster
    nearest_other = d.argmin(axis=1)    # per v1 archetype
    match_tab = {
        L.V1_NAMES[i]: {"cluster": int(j), "distance_v1_sd": float(dist[i]),
                        "mutual_nearest": bool(nearest_v1[j] == i and nearest_other[i] == j)}
        for i, j in mapping.items()
    }
    return names, match_tab


t = time.time()
core = {s: L.train(v2_players(s, CORE_RULES)) for s in SEEDS}
base = core[L.SEED]
K = base["k"]
print(f"v2-core: {len(base['players'])} players, {time.time() - t:.0f}s")

# --- k, silhouette, stability, seed-to-seed --------------------------------------------
sil = pd.DataFrame({s: r["sil"] for s, r in core.items()}).rename_axis("k")
sil_summary = pd.DataFrame({"mean": sil.mean(axis=1), "min": sil.min(axis=1), "max": sil.max(axis=1)})
sil.round(4).to_csv(OUT / "silhouette_by_seed.csv")
pd.concat({s: r["checks"] for s, r in core.items()}, names=["seed"]).round(4).to_csv(OUT / "k_rule_checks.csv")
stab = {s: L.stability(r) for s, r in core.items()}
a42 = L.Assigner.from_run(base)
s2s = {}
for s in L.NOISE_SEEDS:
    r = core[s]
    res = L.compare(a42, {c: f"c{c}" for c in range(K)}, L.Assigner.from_run(r, r["fits"][K]),
                    {"seed 42 players": base["raw"], f"seed {s} players": r["raw"]}, f"seed {s}")
    s2s[s] = {p: {"ari": d["ari"], "changed": d["changed"]} for p, d in res["pops"].items()}
s2s_ari = [d["ari"] for v in s2s.values() for d in v.values()]
s2s_chg = [d["changed"] for v in s2s.values() for d in v.values()]
R = {
    "n_per_persona": N, "players": len(base["players"]), "rules": "v2 with rule5_trophy_hunters off",
    "rule_k_by_seed": {s: int(r["k"]) for s, r in core.items()},
    "reason_by_seed": {s: r["reason"] for s, r in core.items()},
    "silhouette_by_k": sil_summary.round(4).to_dict("index"),
    "stability_by_seed": stab,
    "seed_to_seed": s2s, "seed_to_seed_ari_range": [min(s2s_ari), max(s2s_ari)],
    "seed_to_seed_changed_range": [min(s2s_chg), max(s2s_chg)],
    "persona_ari_seed42": L.persona_ari(base),
}
print("rule k by seed:", R["rule_k_by_seed"])
print(sil_summary.round(4).to_string())
print("stability by seed:", {s: round(v["mean_pairwise"], 3) for s, v in stab.items()})
print(f"seed-to-seed ARI at k = {K}: {min(s2s_ari):.3f}-{max(s2s_ari):.3f}, reassigned {min(s2s_chg):.1%}-{max(s2s_chg):.1%}")
for s in L.NOISE_SEEDS:
    print("  seed", s, {p: round(d["ari"], 3) for p, d in s2s[s].items()})
print("persona ARI:", round(R["persona_ari_seed42"], 3))

# --- References at the same size, seed 42 -----------------------------------------------
v1 = L.train(v1_players(L.SEED))
v2 = L.train(v2_players(L.SEED))
A1, A2, Ac = L.Assigner.from_run(v1), L.Assigner.from_run(v2), a42
names1, _ = named_by_frozen_v1(A1)
names2, _ = named_by_frozen_v1(A2)
namesc, match_core_frozen = named_by_frozen_v1(Ac)
R["reference_k"] = {"v1 large": int(v1["k"]), "v2 large": int(v2["k"])}

# Does each of v1's six archetypes have a matching v2-core cluster? (vs large v1, in its SD units)
m_c1, d_c1 = L.match(A1.c, L.in_units_of(A1, Ac))
dfull = np.linalg.norm(A1.c[:, None, :] - L.in_units_of(A1, Ac)[None, :, :], axis=2)
recovery = {}
for i, j in m_c1.items():
    recovery[names1[i]] = {"v2-core cluster": int(j), "distance (large-v1 SD)": float(d_c1[i]),
                           "mutual nearest": bool(dfull[:, j].argmin() == i and dfull[i].argmin() == j)}
for i in range(len(A1.c)):
    if i not in m_c1:
        recovery[names1[i]] = {"v2-core cluster": None, "distance (large-v1 SD)": None, "mutual nearest": False}
R["recovery_vs_large_v1"] = recovery
print("recovery of v1's archetypes:", json.dumps(recovery, indent=1))


def compare_to(ref_asg, ref_names, ref_raw, label):
    res = L.compare(ref_asg, ref_names, Ac, {f"{label} players": ref_raw, "v2-core players": base["raw"]}, "v2-core")
    out = {"v2core_name_by_match": {int(k): v for k, v in res["other_name"].items()},
           "match_distance_ref_sd": res["dist"], "pops": {}}
    for p, d in res["pops"].items():
        tag = f"{label.replace(' ', '_')}__{p.replace(' ', '_')}"
        d["moves"].to_csv(OUT / f"moves_{tag}.csv")
        m = d["moves"].stack()
        top = m[[a != b for a, b in m.index]].sort_values(ascending=False).head(4)
        out["pops"][p] = {"ari": d["ari"], "changed": d["changed"],
                          "top_moves": [{"from": a, "to": b, "players": int(n)} for (a, b), n in top.items()]}
        print(f"v2-core vs {label}, {p}: ARI {d['ari']:.3f}, reassigned {d['changed']:.1%}; top moves:",
              [(a, b, int(n)) for (a, b), n in top.items()])
    # centres side by side in original units
    rows = []
    for i, j in res["mapping"].items():
        for fi, f in enumerate(FN):
            a, b = ref_asg.centres_original()[i, fi], Ac.centres_original()[j, fi]
            rows.append({"reference": ref_names[i], "v2-core cluster": j, "feature": f, label: a, "v2-core": b,
                         "Δ": b - a, "Δ (ref SD)": (b - a) / ref_asg.scale[fi]})
    cent = pd.DataFrame(rows)
    cent.round(4).to_csv(OUT / f"centres_vs_{label.replace(' ', '_')}.csv", index=False)
    out["centres"] = cent.round(4).to_dict("records")
    print(cent.pivot(index="reference", columns="feature", values="Δ (ref SD)")[FN].round(2).to_string())
    return out


R["vs_large_v1"] = compare_to(A1, names1, v1["raw"], "v1 large")
R["vs_large_v2"] = compare_to(A2, names2, v2["raw"], "v2 large")

centres_core = pd.DataFrame(Ac.centres_original(), columns=FN)
centres_core["players"] = np.bincount(base["model"].labels_, minlength=K)
centres_core["matched v1 archetype"] = [namesc[c] for c in range(K)]
centres_core.round(4).to_csv(OUT / "v2_core_centres.csv")
print(centres_core.round(2).to_string())

# --- Export the seed-42 model for the real-user check -----------------------------------
path = OUT / "archetype_model_v2_core.json"
L.export_model(base, {c: f"v2-core cluster {c}" for c in range(K)},
               {c: f"Unnamed v2-core cluster; matched v1 archetype: {namesc[c]}." for c in range(K)},
               "2.0.0-core-candidate", path, stab[L.SEED], R["persona_ari_seed42"], extra_training={
                   "n_per_persona": N, "generator": "archetype_sim_v2, rule 5 off (v2-core)",
                   "status": "candidate for analysis only: not wired into the app"})
assert (L.Assigner.from_json(json.loads(path.read_text())).assign(base["raw"]) == base["model"].labels_).all()
R["v2core_name_by_frozen_v1"] = {int(k): v for k, v in namesc.items()}
R["v2core_match_to_frozen_v1"] = match_core_frozen

# --- Supplementary (not the rule's choice on seed 42): every seed fitted at k = 6 --------
# Seeds 0-4 pick k = 6 by the rule; seed 42 misses it by 0.0026 in silhouette. This shows
# what v2-core's six clusters look like and whether they recover v1's six archetypes.
sup = {}
v1_names_list = [names1[i] for i in range(len(A1.c))]
for s, r in core.items():
    a6 = L.Assigner.from_run(r, r["fits"][6])
    m, d = L.match(A1.c, L.in_units_of(A1, a6))
    full_d = np.linalg.norm(A1.c[:, None, :] - L.in_units_of(A1, a6)[None, :, :], axis=2)
    mutual = {names1[i]: bool(full_d[:, j].argmin() == i and full_d[i].argmin() == j) for i, j in m.items()}
    res = L.compare(A1, names1, a6, {"v1 large players": v1["raw"], "v2-core players": r["raw"]}, "v2-core k6")
    sup[s] = {"distance (large-v1 SD)": {names1[i]: float(d[i]) for i in m}, "mutual nearest": mutual,
              "n mutual": int(sum(mutual.values())),
              "pops": {p: {"ari": x["ari"], "changed": x["changed"]} for p, x in res["pops"].items()}}
    if s == L.SEED:
        for p, x in res["pops"].items():
            x["moves"].to_csv(OUT / f"k6_moves_v1_large__{p.replace(' ', '_')}.csv")
        rows = []
        for i, j in m.items():
            for fi, f in enumerate(FN):
                a, b = A1.centres_original()[i, fi], a6.centres_original()[j, fi]
                rows.append({"v1 archetype": names1[i], "v2-core k6 cluster": j, "feature": f, "v1 large": a,
                             "v2-core k6": b, "Δ": b - a, "Δ (v1 SD)": (b - a) / A1.scale[fi]})
        k6c = pd.DataFrame(rows)
        k6c.round(4).to_csv(OUT / "k6_centres_vs_v1_large.csv", index=False)
        print("k = 6, seed 42: centre Δ vs large v1 (v1 SD)")
        print(k6c.pivot(index="v1 archetype", columns="feature", values="Δ (v1 SD)")[FN].round(2).to_string())
        print(res["pops"]["v1 large players"]["moves"].to_string())
        names6, _ = named_by_frozen_v1(a6)
        p6 = OUT / "archetype_model_v2_core_k6.json"
        run6 = {**r, "k": 6, "model": r["fits"][6]}
        L.export_model(run6, {c: f"v2-core k6 cluster {c}" for c in range(6)},
                       {c: f"Unnamed v2-core k=6 cluster; matched v1 archetype: {names6[c]}." for c in range(6)},
                       "2.0.0-core-k6-supplementary", p6, L.stability(run6), L.persona_ari(run6), extra_training={
                           "n_per_persona": N, "generator": "archetype_sim_v2, rule 5 off (v2-core)",
                           "status": "supplementary, k fixed at 6 (not the rule's choice on seed 42); analysis only"})
        R["k6_name_by_frozen_v1"] = {int(k): v for k, v in names6.items()}
    print(f"k = 6, seed {s}: mutual-nearest matches {sup[s]['n mutual']}/6, "
          f"max distance {max(sup[s]['distance (large-v1 SD)'].values()):.2f}, ARI vs large v1 "
          + ", ".join(f"{p} {x['ari']:.3f} ({x['changed']:.1%})" for p, x in sup[s]["pops"].items()))
k6_s2s = []
a6_42 = L.Assigner.from_run(base, base["fits"][6])
for s in L.NOISE_SEEDS:
    r = core[s]
    res = L.compare(a6_42, {c: f"c{c}" for c in range(6)}, L.Assigner.from_run(r, r["fits"][6]),
                    {"seed 42 players": base["raw"], f"seed {s} players": r["raw"]}, f"seed {s}")
    k6_s2s += [x["ari"] for x in res["pops"].values()]
sup["seed_to_seed_ari_range_k6"] = [min(k6_s2s), max(k6_s2s)]
print(f"k = 6 seed-to-seed ARI: {min(k6_s2s):.3f}-{max(k6_s2s):.3f}")
R["supplementary_k6"] = sup
(OUT / "results.json").write_text(json.dumps(R, indent=2, default=float) + "\n")
print("wrote", (OUT / "results.json").relative_to(REPO), "and", path.relative_to(REPO))
