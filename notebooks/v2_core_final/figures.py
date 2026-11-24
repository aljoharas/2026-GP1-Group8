"""The GP report's figures for the served model (2.0.1), drawn from kept code and data only:

  silhouette_by_k.png       mean silhouette for k = 2..8 on the served population (v2-core, 500 per
                            persona) for generator seeds 42 and 0-4, KMeans(n_init=20, random_state=42)
  centre_heatmap.png        the six centres in the served scaler's SD units, original values printed
  families_dendrogram.png   Ward linkage of the six centres, labels coloured by family
  pca.png                   the 3,333 training players (v2core_training_features.csv) in the first two
                            principal components of the served scaled space, by served archetype

    python notebooks/v2_core_final/figures.py [--no-silhouette]   (needs matplotlib; data/ as for v2_core_final.py)
Writes docs/archetypes/figures/.
"""
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap  # noqa: E402
from scipy.cluster.hierarchy import dendrogram, linkage  # noqa: E402
from sklearn.decomposition import PCA  # noqa: E402

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "notebooks"))
import archetype_v2_lib as L  # noqa: E402

OUT = REPO / "docs" / "archetypes" / "figures"
OUT.mkdir(parents=True, exist_ok=True)
M = json.loads((REPO / "models" / "archetype_model.json").read_text())
FN = M["features"]
ORDER = ["Casual", "Explorer", "Competitor", "Completionist", "Devotee", "The Main"]
FAMILY = {c["name"]: c["family"] for c in M["clusters"]}

SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#6250d6"]
FAM_COL = {"Light": "#2a78d6", "Committed": "#eb6834", "One-game": "#1baf7a"}
DIVERGING = LinearSegmentedColormap.from_list("blue_red", ["#1c5cab", "#86b6ef", "#f0efec", "#f09a99", "#c23a3a"])
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE, "axes.edgecolor": GRID,
    "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2, "text.color": INK, "axes.titlesize": 11,
    "axes.titleweight": "bold", "axes.titlelocation": "left", "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6, "axes.axisbelow": True, "legend.frameon": False,
})


def save(fig, name):
    fig.savefig(OUT / name, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("wrote", (OUT / name).relative_to(REPO))


centres = pd.DataFrame([c["centre_scaled"] for c in M["clusters"]], index=[c["name"] for c in M["clusters"]],
                       columns=FN).loc[ORDER]
orig = pd.DataFrame([c["centre"] for c in M["clusters"]], index=[c["name"] for c in M["clusters"]])[FN].loc[ORDER]

# Centre heatmap
fig, ax = plt.subplots(figsize=(10.5, 4.2))
lim = 2.0
im = ax.imshow(centres.to_numpy(), cmap=DIVERGING, vmin=-lim, vmax=lim, aspect="auto")
for i in range(len(ORDER)):
    for j in range(len(FN)):
        z = centres.iloc[i, j]
        ax.text(j, i, f"{orig.iloc[i, j]:.2f}", ha="center", va="center", fontsize=8.5,
                color=SURFACE if abs(z) > 0.6 * lim else INK)
ax.set_xticks(range(len(FN)), FN, rotation=30, ha="right", fontsize=8.5)
ax.set_yticks(range(len(ORDER)), [f"{n} ({FAMILY[n]})" for n in ORDER], fontsize=9)
ax.grid(False)
for sp in ax.spines.values():
    sp.set_visible(False)
cb = fig.colorbar(im, ax=ax, fraction=0.025, pad=0.01)
cb.set_label("centre in SD units (served scaler)", color=INK2)
cb.outline.set_visible(False)
ax.set_title(f"Archetype centres, model {M['version']} (numbers in original units)")
save(fig, "centre_heatmap.png")

# Families dendrogram
fig, ax = plt.subplots(figsize=(9.5, 4.2))
dendrogram(linkage(centres.to_numpy(), method="ward"), labels=ORDER, ax=ax, color_threshold=0,
           above_threshold_color=INK2)
for lbl in ax.get_xticklabels():
    lbl.set_color(FAM_COL[FAMILY[lbl.get_text()]])
    lbl.set_fontweight("bold")
for fam, col in FAM_COL.items():
    ax.plot([], [], color=col, linewidth=6, label=fam)
ax.legend(fontsize=8, loc="upper right")
ax.set_ylabel("Ward merge height (SD units)")
ax.grid(axis="x", visible=False)
ax.set_title(f"Ward linkage of the six centres, model {M['version']} (label colour = family)")
save(fig, "families_dendrogram.png")

# PCA of the training players
X = pd.read_csv(HERE / "v2core_training_features.csv")[FN].fillna(pd.Series(M["imputation"]))
Z = (X.to_numpy(dtype=float) - np.array(M["scaler"]["mean"])) / np.array(M["scaler"]["scale"])
C = np.array([c["centre_scaled"] for c in M["clusters"]])
lab = np.argmin(((Z[:, None] - C[None]) ** 2).sum(axis=2), axis=1)
pca = PCA(n_components=2, random_state=42).fit(Z)
P, PC, ev = pca.transform(Z), pca.transform(C), pca.explained_variance_ratio_
fig, ax = plt.subplots(figsize=(8.5, 6.2))
names = [c["name"] for c in M["clusters"]]
for colour, name in zip(SERIES, ORDER):
    k = names.index(name)
    m = lab == k
    ax.scatter(P[m, 0], P[m, 1], s=8, color=colour, alpha=0.55, edgecolor="none", label=f"{name} ({m.mean():.0%})")
    ax.scatter(PC[k, 0], PC[k, 1], s=140, color=colour, marker="X", edgecolor=INK, linewidth=1.2, zorder=3)
    # Devotee and The Main sit close together on these two components: label them on opposite sides
    offset = {"Devotee": (-62, -16), "The Main": (10, 8)}.get(name, (8, 6))
    ax.annotate(name, PC[k], xytext=offset, textcoords="offset points", fontsize=9, fontweight="bold", color=INK)
ax.set_xlabel(f"PC1 ({ev[0]:.0%} of variance)")
ax.set_ylabel(f"PC2 ({ev[1]:.0%} of variance)")
ax.legend(fontsize=8, markerscale=2.5, loc="best")
ax.set_title(f"Training players by archetype, model {M['version']} (× = centre)")
save(fig, "pca.png")

# Silhouette by k on the served population, generator seeds 42 and 0-4 (slow: six populations)
if "--no-silhouette" in sys.argv:
    sys.exit(0)
_, cal, CAT, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")
core = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})
seeds = [42, 0, 1, 2, 3, 4]
sil = {}
for s in seeds:
    pop = L.population(L.sim2.generate_players(cal, CAT, 500, L.MIX_SHARE, s, core))
    from sklearn.metrics import silhouette_score  # noqa: E402
    sil[s] = {k: float(silhouette_score(pop["Z"], f.labels_)) for k, f in L.sweep(pop["Z"]).items()}
    print("seed", s, {k: round(v, 3) for k, v in sil[s].items()})
tab = pd.DataFrame(sil).rename_axis("k")
tab.round(4).to_csv(OUT / "silhouette_by_k.csv")
fig, ax = plt.subplots(figsize=(8, 4.2))
for s in seeds[1:]:
    ax.plot(L.KS, tab[s], color="#a3a29b", linewidth=1, marker="o", markersize=3,
            label="generator seeds 0–4" if s == 0 else None)
ax.plot(L.KS, tab[42], color=SERIES[0], linewidth=2.2, marker="o", label="seed 42 (training population)")
ax.axvline(6, color=INK2, linestyle="--", linewidth=1)
ax.text(6.05, ax.get_ylim()[1], " k = 6 (served)", va="top", fontsize=8.5, color=INK2)
ax.set_xticks(L.KS)
ax.set_xlabel("k")
ax.set_ylabel("mean silhouette")
ax.legend(fontsize=8, loc="lower left")
ax.set_title("Silhouette by k, served population (v2-core, 3,333 players per seed)")
save(fig, "silhouette_by_k.png")
