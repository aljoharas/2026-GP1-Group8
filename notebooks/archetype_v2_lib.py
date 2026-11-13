"""Simulation v2 analysis: training, plausibility checks, v1 vs v2 comparison, sensitivity.

Used by notebooks/archetypes_training_v2.ipynb and notebooks/run_sim_v2.py. The training
pipeline is the v1 notebook's (cells 12-17, 25-27, 33, 39) and the comparison is the
robustness check's (~/archetype-robustness/pipeline.py, run_robustness.py), copied, not
changed: StandardScaler, k = 2..8, the pre-registered k rule, KMeans(n_init=20,
random_state=42), Hungarian matching, ARI on common players, the same verdict rule.
"""
from __future__ import annotations

import itertools
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import linear_sum_assignment
from scipy.stats import spearmanr
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score, silhouette_score
from sklearn.preprocessing import StandardScaler

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetype_catalogue as ac  # noqa: E402
import archetype_sim as sim  # noqa: E402
import archetype_sim_v2 as sim2  # noqa: E402
from archetype_features import FEATURE_NAMES, IMPUTED_FEATURES, compute_features  # noqa: E402

FN = FEATURE_NAMES
MODEL_V1 = json.loads((REPO / "models" / "archetype_model.json").read_text())
SEED = MODEL_V1["seed"]
N_PER_PERSONA = MODEL_V1["training"]["n_per_persona"]
MIX_SHARE = MODEL_V1["training"]["mix_share"]
N_INIT = MODEL_V1["training"]["kmeans"]["n_init"]
KS = list(range(2, 9))
K_TOL, MIN_SD_GAP, MIN_SHARE = 0.01, 0.5, 0.05   # the pre-registered k rule (v1 cell 17)
NOISE_SEEDS = [0, 1, 2, 3, 4]
V1_NAMES = [c["name"] for c in MODEL_V1["clusters"]]
NAME_ORDER = ["Completionist", "Explorer", "Devotee", "The Main", "Competitor", "Casual"]


# --- Inputs -----------------------------------------------------------------------

def load_inputs(steam200k_csv, store_csv=None, catalogue_csv=None):
    """(plays, calibration, catalogue DataFrame, full catalogue, matches). Builds the
    catalogue from steam.csv when store_csv is given, else reads catalogue_csv."""
    plays = sim.load_steam_plays(str(steam200k_csv))
    cal = sim.steam_calibration(plays)
    matches = None
    if store_csv is not None:
        full, matches = ac.build_catalogue(pd.read_csv(store_csv), plays)
        if catalogue_csv is not None:
            Path(catalogue_csv).parent.mkdir(parents=True, exist_ok=True)
            full.to_csv(catalogue_csv, index=False)
    else:
        full = pd.read_csv(catalogue_csv)
    usable = full[full["typical_length_h"].notna() & (full["steam200k_players"] > 0)].copy()
    usable["genre_list"] = usable["genres"].str.split(";")
    return plays, cal, usable.reset_index(drop=True), full, matches


def players_v1(cal, seed=SEED):
    return sim.generate_players(cal, n_per_persona=N_PER_PERSONA, mix_share=MIX_SHARE, seed=seed)


def players_v2(cal, catalogue, seed=SEED, rules=None, log=None):
    return sim2.generate_players(cal, catalogue, N_PER_PERSONA, MIX_SHARE, seed, rules, log)


# --- Population -> features -> scaling (v1 cell 12) -----------------------------------

def features(players) -> pd.DataFrame:
    return pd.DataFrame([compute_features(p["games"]) for p in players], columns=FN).astype(float)


def population(players) -> dict:
    persona = pd.Series([p["persona"] for p in players], name="persona")
    group = persona.where(~persona.str.startswith("mixed:"), "mixed").rename("group")
    raw = features(players)
    impute = raw[IMPUTED_FEATURES].mean()
    X = raw.fillna(impute)
    scaler = StandardScaler().fit(X)
    return {"players": players, "group": group, "is_pure": (group != "mixed").to_numpy(),
            "raw": raw, "impute": impute, "X": X, "scaler": scaler, "Z": scaler.transform(X)}


# --- k sweep and the k rule (v1 cells 15, 17) -------------------------------------------

def sweep(z):
    return {k: KMeans(n_clusters=k, n_init=N_INIT, random_state=SEED).fit(z) for k in KS}


def rule_check(model, z):
    c = model.cluster_centers_
    pairs = [(i, j, np.abs(c[i] - c[j]).max()) for i, j in itertools.combinations(range(len(c)), 2)]
    i, j, gap = min(pairs, key=lambda t: t[2])
    shares = np.bincount(model.labels_, minlength=len(c)) / len(z)
    return {"closest pair": f"{i}-{j}", "its largest gap (SD)": gap, "smallest cluster share": shares.min(),
            "(a) gap >= 0.5 SD": gap >= MIN_SD_GAP, "(b) share >= 5%": shares.min() >= MIN_SHARE}


def choose_k(fits, z):
    sil = {k: silhouette_score(z, m.labels_) for k, m in fits.items()}
    best = max(sil.values())
    candidates = sorted(k for k in sil if sil[k] >= best - K_TOL)
    checks = pd.DataFrame({k: {"silhouette": sil[k], **rule_check(fits[k], z)} for k in candidates}).T.rename_axis("k")
    checks["passes"] = checks["(a) gap >= 0.5 SD"] & checks["(b) share >= 5%"]
    highest = max(sil, key=sil.get)
    if len(candidates) == 1:
        return highest, checks, sil, "only one k within 0.01 -> highest silhouette"
    passing = [k for k in candidates if checks.loc[k, "passes"]]
    if passing:
        return max(passing), checks, sil, f"{len(candidates)} k within 0.01 -> largest passing k"
    return highest, checks, sil, "no candidate passes (a) and (b) -> fallback: highest silhouette"


def train(players) -> dict:
    """Population, k sweep, rule k, and the model at the rule's k."""
    run = population(players)
    fits = sweep(run["Z"])
    k, checks, sil, reason = choose_k(fits, run["Z"])
    run.update(fits=fits, k=k, checks=checks, sil=sil, reason=reason, model=fits[k],
               inertia={kk: m.inertia_ for kk, m in fits.items()})
    return run


def stability(run, n=10):
    """v1 cell 27: refit at the chosen k with KMeans seeds 1..n."""
    labs = [KMeans(n_clusters=run["k"], n_init=N_INIT, random_state=s).fit_predict(run["Z"]) for s in range(1, n + 1)]
    pairwise = [adjusted_rand_score(a, b) for a, b in itertools.combinations(labs, 2)]
    vs = [adjusted_rand_score(run["model"].labels_, l) for l in labs]
    return {"mean_pairwise": float(np.mean(pairwise)), "min_pairwise": float(np.min(pairwise)),
            "mean_vs_model": float(np.mean(vs))}


def persona_ari(run):
    """v1 cell 39: clusters vs persona labels, pure players only."""
    return float(adjusted_rand_score(run["group"][run["is_pure"]], run["model"].labels_[run["is_pure"]]))


def suggested_names(run):
    """v1 cell 33: the pure persona whose average is nearest each centre (scaled space)."""
    means = run["X"].groupby(run["group"]).mean().loc[sim.PERSONA_NAMES]
    pz = pd.DataFrame(run["scaler"].transform(means), index=sim.PERSONA_NAMES)
    dist = pd.DataFrame([[np.linalg.norm(c - pz.loc[p]) for p in sim.PERSONA_NAMES]
                         for c in run["model"].cluster_centers_], columns=sim.PERSONA_NAMES).rename_axis("cluster")
    return dist.idxmin(axis=1), dist


# --- Models as the service uses them -------------------------------------------------

class Assigner:
    """impute -> scale -> nearest centre (pipeline.Assigner)."""

    def __init__(self, impute, mean, scale, centres_scaled):
        self.impute = pd.Series(impute, dtype=float)
        self.mean, self.scale = np.asarray(mean, dtype=float), np.asarray(scale, dtype=float)
        self.c = np.asarray(centres_scaled, dtype=float)

    @classmethod
    def from_run(cls, run, model=None):
        model = run["model"] if model is None else model
        s = run["scaler"]
        return cls(run["impute"], s.mean_, s.scale_, model.cluster_centers_)

    @classmethod
    def from_json(cls, m):
        return cls(m["imputation"], m["scaler"]["mean"], m["scaler"]["scale"],
                   [c["centre_scaled"] for c in m["clusters"]])

    def assign(self, raw: pd.DataFrame) -> np.ndarray:
        x = raw.fillna(self.impute)[FN].to_numpy(dtype=float)
        z = (x - self.mean) / self.scale
        return np.argmin(((z[:, None, :] - self.c[None, :, :]) ** 2).sum(axis=2), axis=1)

    def centres_original(self):
        return self.c * self.scale + self.mean


V1 = Assigner.from_json(MODEL_V1)


def match(centres_a, centres_b):
    """Hungarian match on Euclidean distance. Returns {a index: b index} and distances;
    rectangular when the k differ (unmatched clusters are left out)."""
    d = np.linalg.norm(centres_a[:, None, :] - centres_b[None, :, :], axis=2)
    rows, cols = linear_sum_assignment(d)
    return dict(zip(rows.tolist(), cols.tolist())), {int(r): float(d[r, c]) for r, c in zip(rows, cols)}


def in_units_of(asg_ref: Assigner, asg: Assigner):
    """asg's centres in asg_ref's scaled (SD) units."""
    return (asg.centres_original() - asg_ref.mean) / asg_ref.scale


def compare(ref: Assigner, ref_names: dict, other: Assigner, populations: dict, other_label="other"):
    """Name other's clusters by Hungarian match to ref (in ref SD units), then ARI and
    % reassigned on each population (name -> raw features)."""
    mapping, dist = match(ref.c, in_units_of(ref, other))
    other_name = {j: ref_names[i] for i, j in mapping.items()}
    for j in range(len(other.c)):
        other_name.setdefault(j, f"unmatched {other_label} cluster {j}")
    res = {"mapping": mapping, "dist": {ref_names[i]: d for i, d in dist.items()}, "other_name": other_name, "pops": {}}
    for label, raw in populations.items():
        la = np.array([ref_names[c] for c in ref.assign(raw)])
        lb = np.array([other_name[c] for c in other.assign(raw)])
        res["pops"][label] = {
            "ari": float(adjusted_rand_score(la, lb)),
            "changed": float((la != lb).mean()),
            "moves": pd.crosstab(pd.Series(la, name="reference"), pd.Series(lb, name=other_label)),
        }
    return res


def verdict(same_k: bool, ari_min: float, noise_min: float) -> str:
    """The robustness check's rule (run_robustness.py)."""
    if not same_k or ari_min < 0.8:
        return "Substantial effect"
    if ari_min >= noise_min:
        return "No meaningful effect"
    return "Small effect"


# --- Plausibility (Step 3) --------------------------------------------------------------

def game_table(players) -> pd.DataFrame:
    rows = []
    for p in players:
        for g in p["games"]:
            rows.append({"player_id": p["player_id"], "persona": p["persona"].split(":")[0],
                         **{k: v for k, v in g.items() if k not in ("months", "genres")}})
    return pd.DataFrame(rows)


def plausibility(players_v2_, rules) -> pd.DataFrame:
    g = game_table(players_v2_)
    has_list = g["trophies_available"] > 0
    full = has_list & (g["trophies_unlocked"] >= g["trophies_available"])
    E = rules["rule2_trophies_follow_hours"]["extra_ratio_E"]
    mp = g["_mp_only"]
    n_mp, done_mp = int(mp.sum()), int((mp & g["completed"]).sum())
    rate = done_mp / max(n_mp, 1)
    se = np.sqrt(0.02 * 0.98 / max(n_mp, 1))
    rows = [
        {"check": "completed with r < 0.3 (all games)", "count": int((g["completed"] & (g["_r"] < 0.3)).sum()),
         "out of": int((g["_r"] < 0.3).sum())},
        {"check": "  of which multiplayer-only (rule 3's flat 2%)",
         "count": int((g["completed"] & (g["_r"] < 0.3) & mp).sum()), "out of": int(((g["_r"] < 0.3) & mp).sum())},
        {"check": "  of which not multiplayer-only (rule 1)",
         "count": int((g["completed"] & (g["_r"] < 0.3) & ~mp).sum()), "out of": int(((g["_r"] < 0.3) & ~mp).sum())},
        {"check": "100% trophies on an unfinished game", "count": int((full & ~g["completed"]).sum()),
         "out of": int((has_list & ~g["completed"]).sum())},
        {"check": "100% trophies, hunters' unfinished games", "count": int((full & ~g["completed"] & g["_hunter"]).sum()),
         "out of": int((has_list & ~g["completed"] & g["_hunter"]).sum())},
        {"check": f"100% trophies with r < 1 + E ({1 + E:g})", "count": int((full & (g["_r"] < 1 + E)).sum()),
         "out of": int((has_list & (g["_r"] < 1 + E)).sum())},
        {"check": "completed multiplayer-only games", "count": done_mp, "out of": n_mp,
         "note": f"rate {rate:.2%} vs 2% (binomial ±2 SE: {max(0, 0.02 - 2 * se):.2%}–{0.02 + 2 * se:.2%})"},
        {"check": "full sets (100%) overall", "count": int(full.sum()), "out of": int(has_list.sum())},
    ]
    return pd.DataFrame(rows)


def spearman_table(raw: pd.DataFrame) -> pd.DataFrame:
    X = raw.copy()
    rho = pd.DataFrame(spearmanr(X, nan_policy="omit").correlation, index=FN, columns=FN)
    return rho


EXPECTED_SIGNS = [  # Step 3's expected v2 directions
    ("log_hours_per_game", "trophy_rate", +1),
    ("log_activity", "trophy_rate", +1),
    ("completion_rate", "trophy_rate", +1),
    ("online_share", "completion_rate", -1),
]


# --- Model export (v1 cell 47's structure) ----------------------------------------------

def export_model(run, names, descriptions, version, path, stab, p_ari, temperature=None, extra_training=None):
    """Same JSON structure as models/archetype_model.json. temperature is copied from v1 only
    as a placeholder; it has not been reviewed for v2."""
    from datetime import datetime, timezone
    model, Z, scaler = run["model"], run["Z"], run["scaler"]
    K = run["k"]
    centres = pd.DataFrame(scaler.inverse_transform(model.cluster_centers_), columns=FN)
    shares = np.bincount(model.labels_, minlength=K) / len(model.labels_)
    export = {
        "version": version,
        "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "seed": SEED,
        "min_games": MODEL_V1["min_games"],
        "k": int(K),
        "silhouette": round(float(silhouette_score(Z, model.labels_)), 4),
        "features": FN,
        "scoring": {**MODEL_V1["scoring"], "temperature": temperature or MODEL_V1["scoring"]["temperature"]},
        "imputation": {f: float(run["impute"][f]) for f in IMPUTED_FEATURES},
        "scaler": {"mean": scaler.mean_.tolist(), "scale": scaler.scale_.tolist()},
        "clusters": [
            {"id": c, "name": names[c], "description": descriptions[c],
             "centre_scaled": model.cluster_centers_[c].tolist(),
             "centre": dict(zip(FN, centres.loc[c, FN].astype(float).tolist())),
             "training_share": round(float(shares[c]), 4)}
            for c in range(K)
        ],
        "training": {
            "players": len(run["players"]),
            "n_per_persona": N_PER_PERSONA,
            "mix_share": MIX_SHARE,
            "kmeans": {"n_init": N_INIT, "random_state": SEED},
            "k_rule": MODEL_V1["training"]["k_rule"],
            "stability_mean_pairwise_ari": round(stab["mean_pairwise"], 4),
            "persona_sanity_ari": round(p_ari, 4),
            "calibration": MODEL_V1["training"]["calibration"],
            **(extra_training or {}),
        },
    }
    Path(path).write_text(json.dumps(export, indent=2) + "\n")
    return export
