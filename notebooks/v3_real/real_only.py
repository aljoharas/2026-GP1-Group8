"""v3 "real features only": cluster the real Steam players on the five real features alone
(games played, hours per game, top-game share, genre diversity, online share). No simulated
feature. Also with Dota 2 removed. Analysis only.

Same pipeline as the v3 notebook: StandardScaler, KMeans(n_init=20, random_state=42), k = 2..8.
Real features don't depend on the simulation seed, so there is no seed-to-seed comparison;
stability is across 10 KMeans restarts. Archetype resemblance: Hungarian match to the served
2.0.0 centres on these five features, in the served SD units; "resembles" = mutual nearest and
closer than half the gap to that archetype's nearest other archetype (same test as before).

    python notebooks/v3_real/real_only.py
Writes notebooks/v3_real/real_only/ (tables, figure, results.json).
"""
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import v3_real as V  # noqa: E402

REAL = ["log_games_played", "log_hours_per_game", "top_game_share", "genre_diversity", "online_share"]
KS = list(range(2, 9))
OUT = HERE / "real_only"
OUT.mkdir(exist_ok=True)
DATA = V.REPO / "data"

SERVED = json.loads((V.REPO / "models" / "archetype_model.json").read_text())
NAMES = [c["name"] for c in SERVED["clusters"]]
idx = [V.FEATURES_ACTIVITY.index(f) for f in REAL]
SMEAN = np.array(SERVED["scaler"]["mean"])[idx]
SSCALE = np.array(SERVED["scaler"]["scale"])[idx]
S5 = np.array([c["centre_scaled"] for c in SERVED["clusters"]])[:, idx]
_d = np.linalg.norm(S5[:, None] - S5[None], axis=2)
np.fill_diagonal(_d, np.inf)
HALF_GAP = _d.min(axis=1) / 2


def real_features(games: pd.DataFrame, cat_median: float) -> pd.DataFrame:
    """The five real features via the v3 pipeline (compute_features; online share over matched
    games). The simulated columns are computed and dropped; they don't affect these five."""
    _, _, X = V.run(games, 42, V.SimConfig(), cat_median)
    return X[REAL]


def resemblance(fit) -> tuple[pd.DataFrame, dict]:
    C = (fit.centres_original()[REAL].to_numpy() - SMEAN) / SSCALE
    mapping, d = V.hungarian(S5, C)
    rows = []
    for i, nm in enumerate(NAMES):
        j = mapping.get(i)
        if j is None:
            rows.append({"served archetype": nm, "group": None, "distance (SD)": None, "mutual nearest": False,
                         "half gap": HALF_GAP[i], "resembles": False})
            continue
        mutual = bool(d[:, j].argmin() == i and d[i].argmin() == j)
        rows.append({"served archetype": nm, "group": j, "distance (SD)": float(d[i, j]), "mutual nearest": mutual,
                     "half gap": float(HALF_GAP[i]), "resembles": bool(mutual and d[i, j] < HALF_GAP[i])})
    nearest = {j: NAMES[int(d[:, j].argmin())] for j in range(len(C))}
    return pd.DataFrame(rows).set_index("served archetype"), nearest


def analyse(label: str, X: pd.DataFrame) -> dict:
    fits, sil, inertia = V.sweep(X, KS)
    best = max(sil, key=sil.get)
    ties = V.near_ties(sil)
    show = sorted(set([best, 6] + ties))
    res = {"players": len(X), "imputed": X.isna().sum()[lambda s: s > 0].to_dict(), "silhouette": sil,
           "inertia": inertia, "best_k": best, "within_0.01": ties, "k": {}}
    tag = label.replace(" ", "_")
    pd.DataFrame({"silhouette": sil, "inertia": inertia}).rename_axis("k").round(4).to_csv(OUT / f"{tag}_k_sweep.csv")
    for k in show:
        f = fits[k]
        c = f.centres_original()[REAL]
        c["players"] = np.bincount(f.labels, minlength=k)
        c["share"] = c["players"] / len(f.labels)
        c["≈ games"] = np.exp(c["log_games_played"])
        c["≈ hours/game"] = np.expm1(c["log_hours_per_game"])
        tab, nearest = resemblance(f)
        c["nearest served archetype"] = [nearest[j] for j in range(k)]
        c.round(4).to_csv(OUT / f"{tag}_centres_k{k}.csv")
        tab.round(4).to_csv(OUT / f"{tag}_resemblance_k{k}.csv")
        res["k"][k] = {"restart": V.restart_stability(X, k), "centres": c.round(4).to_dict("records"),
                       "resemblance": tab.reset_index().round(4).to_dict("records"),
                       "resembles": [nm for nm, r in tab.iterrows() if r["resembles"]]}
    res["_fits"] = fits
    return res


cat = V.load_catalogue(DATA / "steam_catalogue.csv")
matches = pd.read_csv(DATA / "steam_catalogue_matches.csv")
med = V.median_typical_length(cat)
plays = V.sim.load_steam_plays(str(DATA / "steam-200k.csv"))
games, anon, _ = V.build_base(plays, cat, matches)
games_nodota, _, _ = V.build_base(plays, cat, matches, exclude_titles=("Dota 2",), anon=anon)
del plays

results = {"main": analyse("all players", real_features(games, med)),
           "no_dota": analyse("Dota 2 removed", real_features(games_nodota, med))}

# Agreement between the two at the main run's best k, on common players
from sklearn.metrics import adjusted_rand_score  # noqa: E402
Xa, Xb = real_features(games, med), real_features(games_nodota, med)
common = Xa.index.intersection(Xb.index)
for k in sorted(set([results["main"]["best_k"], 6])):
    la = pd.Series(results["main"]["_fits"][k].labels, index=Xa.index)[common]
    lb = pd.Series(results["no_dota"]["_fits"][k].labels, index=Xb.index)[common]
    results.setdefault("ari_main_vs_no_dota", {})[k] = float(adjusted_rand_score(la, lb))

# Figure: elbow and silhouette, both populations
fig, (a1, a2) = plt.subplots(1, 2, figsize=(12, 3.8))
for lab, col, r in (("all players", "#2a78d6", results["main"]), ("Dota 2 removed", "#eb6834", results["no_dota"])):
    a1.plot(KS, [r["inertia"][k] for k in KS], marker="o", color=col, lw=1.8, label=lab)
    a2.plot(KS, [r["silhouette"][k] for k in KS], marker="o", color=col, lw=1.8, label=lab)
a1.set_title("Inertia (elbow), 5 real features", loc="left", fontweight="bold")
a2.set_title("Mean silhouette, 5 real features", loc="left", fontweight="bold")
for a in (a1, a2):
    a.set_xticks(KS)
    a.set_xlabel("k")
    a.legend(frameon=False, fontsize=8)
    a.spines[["top", "right"]].set_visible(False)
    a.grid(color="#e4e3df", lw=0.6)
fig.tight_layout()
fig.savefig(OUT / "real_only_choose_k.png", dpi=200, bbox_inches="tight")

for r in results.values():
    if isinstance(r, dict):
        r.pop("_fits", None)
(OUT / "results.json").write_text(json.dumps(results, indent=2, default=lambda o: o.item() if hasattr(o, "item") else str(o)) + "\n")

for key in ("main", "no_dota"):
    r = results[key]
    print(f"\n===== {key}: {r['players']} players, imputed {r['imputed']}")
    print("silhouette:", {k: round(v, 3) for k, v in r["silhouette"].items()})
    print("best k", r["best_k"], "| within 0.01:", r["within_0.01"])
    for k, d in r["k"].items():
        print(f"-- k = {k}: restart ARI {d['restart']['mean_pairwise']:.3f} (min {d['restart']['min_pairwise']:.3f}); resembles {d['resembles']}")
        print(pd.DataFrame(d["centres"]).round(2).to_string())
        print(pd.DataFrame(d["resemblance"]).set_index("served archetype").round(2).to_string())
print("\nARI all players vs Dota 2 removed (common players):", results["ari_main_vs_no_dota"])
