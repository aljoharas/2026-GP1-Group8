"""Are the three families supported by model 2.0.0 (v2-core, k = 6)? Analysis only.

Decision rule (fixed before running): families are confirmed if, for EVERY archetype,
  (a) its nearest centre is its family partner, AND
  (b) its family partner is the most common second-highest archetype among its players,
and (c) more than 60% of close calls (top two within 10 points) are same-family.

Seed 42 uses the served JSON as-is. Seeds 0-4 use the k = 6 fit on each seed's own v2-core
population (500 per persona), clusters named by Hungarian match to the served centres.
Scores use the served scoring (archetypes.match_probabilities, largest_remainder, T = 0.75).

    python notebooks/families_check.py
Writes notebooks/families_check/ and notebooks/figures/v2/families_dendrogram.png.
"""
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from scipy.cluster.hierarchy import dendrogram, linkage  # noqa: E402
from sklearn.cluster import KMeans  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archetype_v2_lib as L  # noqa: E402

sys.path.insert(0, str(L.REPO / "backend" / "recommender"))
from archetypes import largest_remainder, match_probabilities  # noqa: E402

N, K, T, CLOSE = 500, 6, 0.75, 10
SERVED = json.loads((L.REPO / "models" / "archetype_model.json").read_text())
assert SERVED["version"] == "2.0.0"
FAMILY = {c["name"]: c["family"] for c in SERVED["clusters"]}
PARTNER = {a: b for a in FAMILY for b in FAMILY if a != b and FAMILY[a] == FAMILY[b]}
ORDER = ["Casual", "Explorer", "Competitor", "Completionist", "Devotee", "The Main"]
FAMILY_PAIRS = {frozenset(("Casual", "Explorer")), frozenset(("Competitor", "Completionist")),
                frozenset(("Devotee", "The Main"))}
OUT = L.REPO / "notebooks" / "families_check"
OUT.mkdir(exist_ok=True)
FIG = L.REPO / "notebooks" / "figures" / "v2" / "families_dendrogram.png"
CORE = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})

plays, cal, CAT, _, _ = L.load_inputs(L.REPO / "data" / "steam-200k.csv", L.REPO / "data" / "steam_catalogue.csv")
SERVED_ASG = L.Assigner.from_json(SERVED)
SERVED_NAMES = [c["name"] for c in SERVED["clusters"]]


def analyse(label, centres_scaled, names, Z):
    """Steps 1-3 for one model. centres_scaled in the model's own SD units; Z = its players."""
    C = pd.DataFrame(centres_scaled, index=names).loc[ORDER]
    # 1. distances
    diff = C.to_numpy()[:, None, :] - C.to_numpy()[None, :, :]
    euclid = pd.DataFrame(np.linalg.norm(diff, axis=2), index=ORDER, columns=ORDER)
    maxgap = pd.DataFrame(np.abs(diff).max(axis=2), index=ORDER, columns=ORDER)
    nearest = {a: euclid.loc[a].drop(a).idxmin() for a in ORDER}
    # 2. Ward linkage on the six centres
    Lk = linkage(C.to_numpy(), method="ward")
    members = {i: {ORDER[i]} for i in range(len(ORDER))}
    merges = []
    for step, (i, j, h, _) in enumerate(Lk):
        new = members[int(i)] | members[int(j)]
        members[len(ORDER) + step] = new
        merges.append({"step": step + 1, "merged": " + ".join(sorted(members[int(i)])) + "  |  " +
                       " + ".join(sorted(members[int(j)])), "height": float(h), "members": sorted(new)})
    first3 = {frozenset(m["members"]) for m in merges[:3]}
    # 3. second choice with the served scoring
    idx = {n: k for k, n in enumerate(names)}
    first, second, gap = [], [], []
    for z in Z:
        pct = largest_remainder(match_probabilities(z, centres_scaled, T))
        probs = match_probabilities(z, centres_scaled, T)
        order = sorted(range(len(pct)), key=lambda i: (-pct[i], -probs[i], i))
        first.append(names[order[0]])
        second.append(names[order[1]])
        gap.append(pct[order[0]] - pct[order[1]])
    df = pd.DataFrame({"primary": first, "second": second, "gap": gap})
    counts = pd.crosstab(df["primary"], df["second"]).reindex(index=ORDER, columns=ORDER, fill_value=0)
    pcts = counts.div(counts.sum(axis=1), axis=0) * 100
    top_second = {a: counts.loc[a].idxmax() for a in ORDER if counts.loc[a].sum() > 0}
    close = df[df["gap"] <= CLOSE].copy()
    close["same"] = [FAMILY[a] == FAMILY[b] for a, b in zip(close["primary"], close["second"])]
    cross = (close[~close["same"]].apply(lambda r: " / ".join(sorted((r["primary"], r["second"]))), axis=1)
             .value_counts())
    same_share = float(close["same"].mean()) if len(close) else float("nan")
    # rule
    a_ok = {a: nearest[a] == PARTNER[a] for a in ORDER}
    b_ok = {a: top_second.get(a) == PARTNER[a] for a in ORDER}
    c_ok = same_share > 0.60
    return {
        "label": label, "euclid": euclid, "maxgap": maxgap, "nearest": nearest, "linkage": Lk, "merges": merges,
        "first3_are_families": first3 == FAMILY_PAIRS, "counts": counts, "pcts": pcts, "top_second": top_second,
        "close_n": int(len(close)), "players": int(len(df)), "same_share": same_share, "cross": cross,
        "a": a_ok, "b": b_ok, "c": c_ok, "confirmed": all(a_ok.values()) and all(b_ok.values()) and c_ok,
    }


def report(r):
    print(f"\n===== {r['label']} =====")
    print("Euclidean distance between centres (SD units):")
    print(r["euclid"].round(2).to_string())
    print("Largest single-feature gap (SD):")
    print(r["maxgap"].round(2).to_string())
    print("nearest:", r["nearest"])
    print("Ward merges:")
    for m in r["merges"]:
        print(f"  {m['step']}. {m['merged']}  (height {m['height']:.2f})")
    print("first three merges are exactly the families:", r["first3_are_families"])
    print("primary x second (counts):")
    print(r["counts"].to_string())
    print("primary x second (% of row):")
    print(r["pcts"].round(1).to_string())
    print(f"close calls (gap <= {CLOSE}): {r['close_n']} of {r['players']}; same-family {r['same_share']:.1%}")
    print("cross-family close-call pairs:", r["cross"].head(5).to_dict())
    print("(a) nearest is partner:", r["a"])
    print("(b) top second is partner:", r["b"])
    print("(c) >60% close calls same-family:", r["c"], "| CONFIRMED:", r["confirmed"])


def to_json(r):
    return {
        "nearest": r["nearest"], "first3_are_families": r["first3_are_families"],
        "merges": [{k: v for k, v in m.items()} for m in r["merges"]],
        "euclid": r["euclid"].round(4).to_dict(), "maxgap": r["maxgap"].round(4).to_dict(),
        "counts": r["counts"].to_dict(), "top_second": r["top_second"],
        "close_calls": r["close_n"], "players": r["players"], "same_family_share": r["same_share"],
        "cross_pairs": r["cross"].to_dict(), "a": r["a"], "b": r["b"], "c": r["c"], "confirmed": r["confirmed"],
    }


results = {}
# Seed 42: the served model, on its own training population
run = L.population(L.sim2.generate_players(cal, CAT, N, L.MIX_SHARE, L.SEED, CORE))
Z42 = (run["raw"].fillna(SERVED_ASG.impute)[L.FN].to_numpy() - SERVED_ASG.mean) / SERVED_ASG.scale
r42 = analyse("seed 42 (served 2.0.0)", SERVED_ASG.c, SERVED_NAMES, Z42)
report(r42)
results[42] = r42
for name, df in [("euclid", r42["euclid"]), ("maxgap", r42["maxgap"]), ("counts", r42["counts"]), ("pcts", r42["pcts"])]:
    df.round(4).to_csv(OUT / f"seed42_{name}.csv")

# Dendrogram for the served model
fig, ax = plt.subplots(figsize=(9.5, 4.2))
fam_col = {"Light": "#2a78d6", "Committed": "#eb6834", "One-game": "#1baf7a"}
dendrogram(r42["linkage"], labels=ORDER, ax=ax, color_threshold=0, above_threshold_color="#52514e")
for lbl in ax.get_xticklabels():
    lbl.set_color(fam_col[FAMILY[lbl.get_text()]])
    lbl.set_fontweight("bold")
ax.set_ylabel("Ward merge height (SD units)")
ax.set_title("Ward linkage of the six 2.0.0 centres (label colour = family)", loc="left", fontweight="bold")
for fam, col in fam_col.items():
    ax.plot([], [], color=col, linewidth=6, label=fam)
ax.legend(frameon=False, fontsize=8, loc="upper right")
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(FIG, dpi=200, bbox_inches="tight")

# Seeds 0-4: each seed's own k = 6 fit, named by Hungarian match to the served centres
for s in L.NOISE_SEEDS:
    r = L.population(L.sim2.generate_players(cal, CAT, N, L.MIX_SHARE, s, CORE))
    km = KMeans(n_clusters=K, n_init=L.N_INIT, random_state=L.SEED).fit(r["Z"])
    asg = L.Assigner(r["impute"], r["scaler"].mean_, r["scaler"].scale_, km.cluster_centers_)
    mapping, _ = L.match(SERVED_ASG.c, L.in_units_of(SERVED_ASG, asg))
    names = [None] * K
    for i, j in mapping.items():
        names[j] = SERVED_NAMES[i]
    res = analyse(f"seed {s} (k = 6 fit)", km.cluster_centers_, names, r["Z"])
    report(res)
    results[s] = res

summary = pd.DataFrame({
    s: {"first 3 merges = families": r["first3_are_families"],
        "(a) all nearest = partner": all(r["a"].values()),
        "(a) fails": ", ".join(a for a, ok in r["a"].items() if not ok) or "-",
        "(b) all top second = partner": all(r["b"].values()),
        "(b) fails": ", ".join(a for a, ok in r["b"].items() if not ok) or "-",
        "close calls same-family": round(r["same_share"], 3), "(c) > 60%": r["c"], "confirmed": r["confirmed"]}
    for s, r in results.items()
}).T.rename_axis("seed")
summary.to_csv(OUT / "summary.csv")
print("\n", summary.to_string())
(OUT / "results.json").write_text(json.dumps({str(s): to_json(r) for s, r in results.items()}, indent=2, default=str) + "\n")
print("wrote", OUT.relative_to(L.REPO), "and", FIG.relative_to(L.REPO))
