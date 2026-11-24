"""v2.2 steps 3-6 with the calibrated shifts (calibration.json): plausibility, training (seeds 42 + 0-4,
k = 2..8), Hungarian match to the six archetypes, temperature table, atypical threshold, and the
IN-SAMPLE (not validation) score on the 20 calibration responses. Applies the fixed serve rule.

Matching: primary = each model's centres in its OWN standardised units (relative profile; v2.2's
levels moved on purpose). Also reported: v2.2's centres in 2.0.1's units.

    python notebooks/v2_2/train_v2_2.py     (DATABASE_URL not needed)
Writes notebooks/v2_2/results.json, tables/, and a draft model (not models/).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score, silhouette_score

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[0] / "survey_validation"))
import calibrate as C  # noqa: E402
import survey_features as S  # noqa: E402

L, REPO = C.L, C.REPO
FN = L.FN
TAB = HERE / "tables"
TAB.mkdir(exist_ok=True)
SEEDS = [42, 0, 1, 2, 3, 4]
SERVED = S.archetypes.load_model()                       # 2.0.1
assert SERVED["version"] == "2.0.1"
SERVED_NAMES = [c["name"] for c in SERVED["clusters"]]
FAMILY = {c["name"]: c["family"] for c in SERVED["clusters"]}
DESCRIPTION = {c["name"]: c["description"] for c in SERVED["clusters"]}
TEMPS = [0.5, 0.6, 0.75, 1.0]

cal = json.loads((HERE / "calibration.json").read_text())
SHIFTS = cal["shifts"]
R = {"shifts": SHIFTS, "targets": cal["targets"], "check_500": cal["check_500_per_persona"]}

# --- Populations ------------------------------------------------------------------------------
pops = {s: L.population(C.simulate(SHIFTS, 500, s)) for s in SEEDS}
run = pops[42]

# --- 3. Plausibility -----------------------------------------------------------------------------
checks = L.plausibility(run["players"], C.CORE)
checks.to_csv(TAB / "plausibility.csv", index=False)
rho = L.spearman_table(run["raw"])
X2core = pd.read_csv(REPO / "notebooks" / "survey_validation" / "tables" / "v2core_training_features.csv")
rho0 = L.spearman_table(X2core[FN])
signs = [{"pair": f"{a} ~ {b}", "expected": "+" if sg > 0 else "-", "v2-core": float(rho0.loc[a, b]),
          "v2.2": float(rho.loc[a, b]), "as expected": bool(np.sign(rho.loc[a, b]) == sg)} for a, b, sg in L.EXPECTED_SIGNS]
c = checks.set_index("check")
mp = c.loc["completed multiplayer-only games"]
mp_rate = mp["count"] / mp["out of"]
plaus = {
    "rule1 completions with r < 0.3 (not multiplayer-only)": int(c.loc["  of which not multiplayer-only (rule 1)", "count"]),
    "rule1 games with r < 0.3": int(c.loc["  of which not multiplayer-only (rule 1)", "out of"]),
    "100% trophies on unfinished": int(c.loc["100% trophies on an unfinished game", "count"]),
    "100% trophies with r < 1 + E": int(c.loc["100% trophies with r < 1 + E (3)", "count"]),
    "multiplayer-only completion rate": float(mp_rate),
    "multiplayer-only within 2 SE of 2%": bool(abs(mp_rate - 0.02) <= 2 * np.sqrt(0.02 * 0.98 / mp["out of"])),
}
rule1_ok = plaus["rule1 completions with r < 0.3 (not multiplayer-only)"] <= 0.001 * plaus["rule1 games with r < 0.3"]
# Online <-> completion was accepted as explained (confounded by hours) for v2-core; same treatment here
signs_ok = all(s["as expected"] for s in signs if "online_share" not in s["pair"])
plaus_pass = bool(rule1_ok and plaus["100% trophies on unfinished"] == 0 and plaus["100% trophies with r < 1 + E"] == 0
                  and plaus["multiplayer-only within 2 SE of 2%"] and signs_ok)
R["plausibility"] = {**plaus, "signs": signs, "pass": plaus_pass,
                     "note": "online share ~ completion is judged as for v2-core (explained confound), not as a pass/fail sign"}

# --- 4. Training --------------------------------------------------------------------------------
sweeps = {s: L.sweep(p["Z"]) for s, p in pops.items()}
sil = pd.DataFrame({f"seed {s}": {k: float(silhouette_score(pops[s]["Z"], m.labels_)) for k, m in sweeps[s].items()}
                    for s in SEEDS}).rename_axis("k")
sil["mean"] = sil.mean(axis=1)
sil.round(4).to_csv(TAB / "silhouette_by_k_seed.csv")
best_k = {s: int(sil[f"seed {s}"].idxmax()) for s in SEEDS}
six_within = {s: bool(sil.loc[6, f"seed {s}"] >= sil[f"seed {s}"].max() - 0.01) for s in SEEDS}
rule_a = sum(six_within.values()) > len(SEEDS) / 2
R["silhouette"] = sil.round(4).to_dict()
R["best_k_by_seed"] = best_k
R["k6_within_0.01_by_seed"] = six_within
R["rule_a"] = bool(rule_a)

model = KMeans(n_clusters=6, n_init=L.N_INIT, random_state=L.SEED).fit(run["Z"])
run.update(k=6, model=model)
stab = L.stability(run)
asg = L.Assigner.from_run(run)
agree = []
for s in SEEDS[1:]:
    p = pops[s]
    m = KMeans(n_clusters=6, n_init=L.N_INIT, random_state=L.SEED).fit(p["Z"])
    o = L.Assigner(p["impute"], p["scaler"].mean_, p["scaler"].scale_, m.cluster_centers_)
    agree += [adjusted_rand_score(asg.assign(run["raw"]), o.assign(run["raw"])),
              adjusted_rand_score(asg.assign(p["raw"]), o.assign(p["raw"]))]
R["training"] = {"silhouette_k6": float(silhouette_score(run["Z"], model.labels_)), "stability": stab,
                 "seed_agreement_k6": [float(min(agree)), float(max(agree))], "persona_ari": L.persona_ari(run)}

# --- 5. Match to the six archetypes ---------------------------------------------------------------
S_own = np.array([c["centre_scaled"] for c in SERVED["clusters"]])       # 2.0.1 in its own units
V_own = model.cluster_centers_                                            # v2.2 in its own units
map_own, d_own = L.match(S_own, V_own)
v22_in_served = (asg.centres_original() - SERVED["_mean"]) / SERVED["_scale"]
map_srv, d_srv = L.match(S_own, v22_in_served)
names = {j: SERVED_NAMES[i] for i, j in map_own.items()}
D = np.linalg.norm(S_own[:, None] - V_own[None], axis=2)
mutual = {SERVED_NAMES[i]: bool(D[:, j].argmin() == i and D[i].argmin() == j) for i, j in map_own.items()}
same = all(map_own[i] == map_srv[i] for i in map_own)
centres = pd.DataFrame(asg.centres_original(), columns=FN)
centres.index = [names[j] for j in range(6)]
centres["share"] = np.bincount(model.labels_, minlength=6) / len(model.labels_)
centres = centres.loc[["Completionist", "Explorer", "Competitor", "Casual", "Devotee", "The Main"]]
served_c = pd.DataFrame({c["name"]: c["centre"] for c in SERVED["clusters"]}).T[FN].loc[centres.index]
centres.round(3).to_csv(TAB / "centres_v2_2.csv")
side = pd.concat({"2.0.1": served_c, "v2.2": centres[FN]}, axis=1).swaplevel(axis=1)[[(f, v) for f in FN for v in ("2.0.1", "v2.2")]]
side.round(3).to_csv(TAB / "centres_side_by_side.csv")
# Relative profile of each matched cluster: its rank on each feature among the six (1 = highest)
ranks = centres[FN].rank(ascending=False).astype(int)
ranks_served = served_c.rank(ascending=False).astype(int)
ranks.to_csv(TAB / "feature_ranks_v2_2.csv")
R["match"] = {"names_by_own_units": {int(j): n for j, n in names.items()},
              "distance_own_units": {SERVED_NAMES[i]: float(d) for i, d in d_own.items()},
              "mutual_nearest": mutual, "same_assignment_in_2_0_1_units": bool(same),
              "distance_in_2_0_1_units": {SERVED_NAMES[i]: float(d) for i, d in d_srv.items()},
              "centres": centres.round(4).reset_index().to_dict("records"),
              "feature_ranks_v2_2": ranks.to_dict("index"), "feature_ranks_2_0_1": ranks_served.to_dict("index")}

# --- Draft model JSON (not models/): same structure as 2.0.1 ---------------------------------------
draft = HERE / "archetype_model_v2_2_draft.json"
L.export_model(run, {j: names[j] for j in range(6)}, {j: DESCRIPTION[names[j]] for j in range(6)}, "2.2.0-draft",
               draft, stab, L.persona_ari(run), temperature=0.75, extra_training={
                   "n_per_persona": 500, "generator": "archetype_sim_v2 rules 1-4, engagement levels recalibrated on the survey",
                   "calibration_shifts": SHIFTS, "status": "DRAFT, not served"})
M = json.loads(draft.read_text())
for cl in M["clusters"]:
    cl["family"] = FAMILY[cl["name"]]
M["clusters"] = [{k: cl[k] for k in ["id", "name", "family", "description", "centre_scaled", "centre", "training_share"]}
                 for cl in M["clusters"]]
# Atypical threshold, as for 2.0.x
Zt = (run["raw"].fillna(pd.Series(M["imputation"]))[FN].to_numpy() - np.array(M["scaler"]["mean"])) / np.array(M["scaler"]["scale"])
Ct = np.array([cl["centre_scaled"] for cl in M["clusters"]])
nearest = np.sqrt(((Zt[:, None] - Ct[None]) ** 2).sum(axis=2)).min(axis=1)
M["atypical_distance_threshold"] = float(np.percentile(nearest, 95))
M["training_distance_quantiles"] = [float(q) for q in np.percentile(nearest, np.arange(101))]
M["atypical"] = {"method": "95th percentile of the training players' nearest-centre distance", "percentile": 95,
                 "training_players": int(len(Zt)), "flagged_share_of_training": float((nearest > M["atypical_distance_threshold"]).mean())}
draft.write_text(json.dumps(M, indent=2) + "\n")
V22 = S.archetypes.load_model(draft)
R["atypical_threshold"] = {"v2.2": M["atypical_distance_threshold"], "2.0.1": SERVED["atypical_distance_threshold"]}

# Temperature table, as for 2.0.x
pure = run["is_pure"]
temp = {}
for T in TEMPS:
    top = np.array([max(S.archetypes.largest_remainder(S.archetypes.match_probabilities(z, V22["_centres"], T))) for z in Zt])
    temp[T] = {"pure median": float(np.median(top[pure])), "pure p10": float(np.percentile(top[pure], 10)),
               "pure p90": float(np.percentile(top[pure], 90)), "mixed median": float(np.median(top[~pure])),
               "at >= 90%": float((top >= 90).mean())}
pd.DataFrame(temp).T.round(3).to_csv(TAB / "temperature.csv")
R["temperature"] = temp

# --- 6. IN-SAMPLE check on the 20 calibration responses (NOT validation) ---------------------------
Xs = pd.read_csv(REPO / "notebooks" / "survey_validation" / "tables" / "features_main.csv", index_col=0)
survey = pd.read_csv(REPO / "data" / "Gaming_Habits_Survey.csv")
selfs = {f"R{i + 1:02d}": survey.iloc[i, -1] for i in range(len(survey))}
ins = {}
rows = []
for label, M_ in (("2.0.1", SERVED), ("v2.2", V22)):
    preds1, preds2, labels, flags = [], [], [], []
    for rid, f in Xs.iterrows():
        feats = {k: (None if pd.isna(v) else float(v)) for k, v in f.items()}
        sc = S.score(feats, M_)
        z = S.archetypes.scale_features(S.fill_missing(feats, M_), M_)
        flag, pct = S.archetypes.atypical_check(z, M_)
        preds1.append({sc["top1"]}); preds2.append(set(sc["top2"])); labels.append(S.SELF[selfs[rid]]); flags.append(flag)
        rows.append({"model": label, "respondent": rid, "self": S.SELF_SHORT[selfs[rid]],
                     "top 3": ", ".join(f"{n} {p}%" for n, p in sc["ranked"][:3]), "atypical": flag, "distance pct": pct})
    ins[label] = {"top1": S.summary(preds1, labels), "top2": S.summary(preds2, labels),
                  "atypical": int(sum(flags)), "top_counts": pd.Series([next(iter(p)) for p in preds1]).value_counts().to_dict()}
pd.DataFrame(rows).to_csv(TAB / "in_sample_scores.csv", index=False)
R["in_sample_NOT_validation"] = ins

# --- Serve rule ------------------------------------------------------------------------------------
R["serve_rule"] = {"a_six_within_0.01_on_most_seeds": bool(rule_a), "b_six_matched_one_to_one": len(map_own) == 6,
                   "b_mutual_nearest_all": all(mutual.values()), "b_descriptions": "judged in the report",
                   "c_plausibility": plaus_pass}
(HERE / "results.json").write_text(json.dumps(R, indent=2, default=lambda o: o.item() if hasattr(o, "item") else str(o)) + "\n")

pd.set_option("display.width", 250)
print("shifts", SHIFTS)
print(json.dumps(R["check_500"], indent=1))
print(checks.to_string(index=False)); print(json.dumps(signs, indent=1)); print("plausibility pass", plaus_pass)
print(sil.round(3).to_string()); print("best k", best_k, "| 6 within 0.01", six_within, "| rule a", rule_a)
print(json.dumps(R["training"], indent=1))
print(json.dumps({k: v for k, v in R["match"].items() if k not in ("centres", "feature_ranks_v2_2", "feature_ranks_2_0_1")}, indent=1))
print(side.round(2).to_string()); print(ranks.to_string()); print(ranks_served.to_string())
print(pd.DataFrame(temp).T.round(3).to_string()); print(R["atypical_threshold"], M["atypical"]["flagged_share_of_training"])
print(json.dumps(ins, indent=1))
