"""Archetypes v3: cluster REAL Steam 200k players instead of persona-generated ones. Experiment only.

Real from each player's library: games played, hours per game, top-game share; from games matched to
the Steam Store catalogue: genre diversity and online share. Simulated, with NO personas: completion
and trophies (v2-core rules 1-3 on the player's real hours and real games, one population Beta for
each propensity, engagement measured as standardised ln total hours) and, in the activity variant
only, active months.

Features go through the shared archetype_features.compute_features. One deliberate exception:
online_share is recomputed over matched games only (unmatched games are left out of it), as the
experiment specifies; the app itself counts a game with no modes as offline.

Every simulated draw is a hash of (seed, player, game, purpose), so variants that change the
population (Dota 2 removed, the >= 80% matched subset) keep every other draw identical.

Nothing here changes the served model, the generators or compute_features.
"""
from __future__ import annotations

import math
import sys
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import beta as beta_dist

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetype_catalogue as ac  # noqa: E402
import archetype_sim as sim  # noqa: E402
import archetype_sim_v2 as sim2  # noqa: E402
from archetype_features import FEATURE_NAMES, compute_features  # noqa: E402

FEATURES_MAIN = [f for f in FEATURE_NAMES if f != "log_activity"]   # 7 features
FEATURES_ACTIVITY = list(FEATURE_NAMES)                             # 8 features
IMPUTED = ["trophy_rate", "genre_diversity", "online_share"]
MIN_GAMES = 5
SEEDS = [42, 0, 1, 2, 3, 4]
MONTHS = (6, 12)   # activity variant: active months ~ Uniform{6..12}

_R2 = sim2.RULES["rule2_trophies_follow_hours"]
_R3 = sim2.RULES["rule3_multiplayer_only_no_ending"]
_R4 = sim2.RULES["rule4_engagement"]


# --- Propensity Betas -------------------------------------------------------------------

def mixture_beta(betas: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    """(a, b, mean, var) of the Beta whose mean and variance match the equal-weight mixture
    of the given Betas."""
    means = np.array([a / (a + b) for a, b in betas])
    vars_ = np.array([a * b / ((a + b) ** 2 * (a + b + 1)) for a, b in betas])
    m = float(means.mean())
    v = float((vars_ + means ** 2).mean() - m ** 2)
    a, b = beta_from_moments(m, v)
    return a, b, m, v


def beta_from_moments(mean: float, var: float) -> tuple[float, float]:
    if not 0 < mean < 1 or not 0 < var < mean * (1 - mean):
        raise ValueError(f"no Beta with mean {mean} and variance {var}")
    k = mean * (1 - mean) / var - 1
    return mean * k, (1 - mean) * k


COMPLETION_BETA = mixture_beta([p["completion_beta"] for p in sim.PERSONAS.values()])
TROPHY_BETA = mixture_beta([p["trophy_beta"] for p in sim.PERSONAS.values()])


@dataclass(frozen=True)
class SimConfig:
    """The simulated parts. Defaults are the main run."""
    engagement: float = 1.0      # multiplies v2's logit shift (0.3 per z)
    mean_shift: float = 0.0      # added to both propensity Beta means, variance unchanged
    activity: bool = False       # 8-feature variant with simulated active months


# --- Hash-based uniforms ----------------------------------------------------------------

def uniforms(*parts) -> np.ndarray:
    """Deterministic U(0,1) per row from the string parts (scalars broadcast)."""
    n = max(len(p) for p in parts if isinstance(p, (list, np.ndarray, pd.Series, pd.Index)))
    cols = [np.asarray(p, dtype=str) if isinstance(p, (list, np.ndarray, pd.Series, pd.Index))
            else np.full(n, str(p)) for p in parts]
    keys = pd.Series(cols[0])
    for c in cols[1:]:
        keys = keys + "|" + c
    h = pd.util.hash_pandas_object(keys, index=False).to_numpy(dtype=np.uint64)
    return (h >> np.uint64(11)).astype(np.float64) / float(1 << 53) + 0.5 / float(1 << 53)


# --- Step 1: the real player base -----------------------------------------------------------

def load_catalogue(path=REPO / "data" / "steam_catalogue.csv") -> pd.DataFrame:
    cat = pd.read_csv(path).set_index("appid")
    cat["genre_list"] = cat["genres"].str.split(";")
    return cat


def median_typical_length(cat: pd.DataFrame) -> float:
    """The catalogue's median typical length (games with a length)."""
    return float(cat["typical_length_h"].median())


def build_base(plays: pd.DataFrame, cat: pd.DataFrame, matches: pd.DataFrame,
               exclude_titles: tuple[str, ...] = (), anon: dict | None = None):
    """Real Steam players as one game table.

    plays: archetype_sim.load_steam_plays (user_id, game, hours; not capped).
    Hours are capped at the 99th percentile of ALL plays (as archetype_sim.steam_calibration),
    users need >= 5 played titles, titles in exclude_titles are then dropped and users re-filtered.
    Titles matching the same catalogue game are merged per player (hours summed, re-capped).
    Returns (games, anon): games has pid, key, title, appid, hours, matched, genres, is_online,
    mp_only, achievement_count, typical_length_h; anon maps Steam user_id -> pid (sequential,
    assigned on the full >= 5-game base so ids are stable across variants).
    """
    cap = float(plays["hours"].quantile(sim.HOURS_CAP_QUANTILE))
    p = plays.assign(hours=plays["hours"].clip(upper=cap))
    titles = p.groupby("user_id")["game"].size()
    base_users = titles[titles >= MIN_GAMES].index
    if anon is None:
        anon = {u: f"P{i + 1:04d}" for i, u in enumerate(sorted(base_users))}
    p = p[p["user_id"].isin(base_users)]
    if exclude_titles:
        p = p[~p["game"].isin(exclude_titles)]
    appid = dict(zip(matches["game"], matches["appid"]))
    p = p.assign(appid=p["game"].map(appid))
    p["matched"] = p["appid"].notna() & p["appid"].isin(cat.index)
    p["key"] = np.where(p["matched"], "app:" + p["appid"].fillna(0).astype(int).astype(str), "title:" + p["game"])
    g = (p.groupby(["user_id", "key"], as_index=False)
          .agg(title=("game", "first"), hours=("hours", "sum"), matched=("matched", "first"), appid=("appid", "first")))
    g["hours"] = g["hours"].clip(upper=cap)
    n = g.groupby("user_id")["key"].transform("size")
    g = g[n >= MIN_GAMES].copy()
    g["pid"] = g["user_id"].map(anon)
    g = g.drop(columns="user_id")
    c = cat.reindex(g["appid"].where(g["matched"]).fillna(-1).astype(int))
    g["genres"] = [list(x) if m else [] for x, m in zip(c["genre_list"].to_numpy(), g["matched"])]
    g["is_online"] = g["matched"].to_numpy() & c["is_online"].astype("boolean").fillna(False).to_numpy(dtype=bool)
    g["mp_only"] = g["matched"].to_numpy() & c["is_multiplayer_only"].astype("boolean").fillna(False).to_numpy(dtype=bool)
    g["achievement_count"] = np.where(g["matched"], c["achievement_count"].fillna(0).to_numpy(), 0).astype(int)
    g["typical_length_h"] = np.where(g["matched"], c["typical_length_h"].to_numpy(), np.nan)
    g = g.sort_values(["pid", "key"]).reset_index(drop=True)
    return g, anon, cap


def base_summary(games: pd.DataFrame, n_users_before: int, cap: float) -> dict:
    per_user = games.groupby("pid").agg(n=("key", "size"), hours=("hours", "sum"),
                                        matched_hours=("hours", lambda h: h[games.loc[h.index, "matched"]].sum()))
    share = per_user["matched_hours"] / per_user["hours"]
    return {
        "users with >= 5 played titles": n_users_before,
        "users kept (>= 5 games after merging same-game titles)": int(len(per_user)),
        "games (player x game)": int(len(games)),
        "games per user: median": float(per_user["n"].median()),
        "games per user: p25": float(per_user["n"].quantile(0.25)),
        "games per user: p75": float(per_user["n"].quantile(0.75)),
        "games per user: p90": float(per_user["n"].quantile(0.90)),
        "share of games matched": float(games["matched"].mean()),
        "share of hours matched": float(games.loc[games["matched"], "hours"].sum() / games["hours"].sum()),
        "users with < 50% of hours matched": int((share < 0.5).sum()),
        "users with >= 80% of hours matched": int((share >= 0.8).sum()),
        "games without a typical length (median used)": int(games["typical_length_h"].isna().sum()),
        "  of which unmatched": int((~games["matched"]).sum()),
        "games with an achievement list": int((games["achievement_count"] > 0).sum()),
        "hours cap (p99 of all plays)": cap,
    }


def matched_share(games: pd.DataFrame) -> pd.Series:
    h = games.groupby("pid")["hours"].sum()
    m = games[games["matched"]].groupby("pid")["hours"].sum().reindex(h.index, fill_value=0)
    return m / h


# --- Step 2: simulated parts ----------------------------------------------------------------

def _logit(p):
    p = np.clip(p, 1e-9, 1 - 1e-9)
    return np.log(p / (1 - p))


def _sigmoid(x):
    return 1 / (1 + np.exp(-x))


def finish_factor(r: np.ndarray) -> np.ndarray:
    """archetype_sim_v2.finish_factor, vectorised."""
    r = np.asarray(r, dtype=float)
    out = np.zeros_like(r)
    pos = r > 0
    out[pos] = _sigmoid((np.log(r[pos]) - math.log(sim2.R_MID)) / sim2.R_SCALE)
    return out


def trophy_progress(r: np.ndarray, completed: np.ndarray, m: float, e: float) -> np.ndarray:
    """archetype_sim_v2.trophy_progress, vectorised."""
    r = np.maximum(np.asarray(r, dtype=float), 0)
    story = m * np.minimum(r, 1.0)
    after = m + (1 - m) * np.minimum((r - 1) / e, 1.0)
    return np.where(completed & (r > 1), after, story)


def shifted_beta(ab_mean_var, shift: float) -> tuple[float, float]:
    a, b, m, v = ab_mean_var
    return (a, b) if shift == 0 else beta_from_moments(m + shift, v)


def simulate(games: pd.DataFrame, seed: int, cfg: SimConfig, median_length: float) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Completion, trophies and (activity variant) months for every real game.
    Returns (games with completed / trophies_unlocked / trophies_available / r / months_n columns,
    players with p, t, z, months)."""
    g = games.copy()
    tot = g.groupby("pid")["hours"].sum()
    lz = np.log(tot)
    z = (lz - lz.mean()) / lz.std(ddof=0)
    pl = pd.DataFrame({"total_hours": tot, "z": z})
    pids = pl.index.to_numpy()
    shift = _R4["logit_shift"] * cfg.engagement * pl["z"].to_numpy()
    ca, cb = shifted_beta(COMPLETION_BETA, cfg.mean_shift)
    ta, tb = shifted_beta(TROPHY_BETA, cfg.mean_shift)
    pl["p_base"] = beta_dist.ppf(uniforms(seed, pids, "completion"), ca, cb)
    pl["t_base"] = beta_dist.ppf(uniforms(seed, pids, "trophy"), ta, tb)
    pl["p"] = _sigmoid(_logit(pl["p_base"].to_numpy()) + shift)
    pl["t"] = _sigmoid(_logit(pl["t_base"].to_numpy()) + shift)
    pl["months"] = MONTHS[0] + np.floor(uniforms(seed, pids, "months") * (MONTHS[1] - MONTHS[0] + 1)).astype(int)

    length = g["typical_length_h"].fillna(median_length).to_numpy()
    r = g["hours"].to_numpy() / length
    p = g["pid"].map(pl["p"]).to_numpy()
    t = g["pid"].map(pl["t"]).to_numpy()
    p_done = np.where(g["mp_only"].to_numpy(), _R3["p_completed"], p * finish_factor(r))
    completed = uniforms(seed, g["pid"], g["key"], "completed") < p_done
    m, e = _R2["story_share_M"], _R2["extra_ratio_E"]
    n = g["achievement_count"].to_numpy()
    frac = t * trophy_progress(r, completed, m, e)
    unlocked = np.rint(frac * n).astype(int)
    full_ok = completed & (r >= 1 + e)
    unlocked = np.where(full_ok, unlocked, np.minimum(unlocked, np.maximum(n - 1, 0)))
    g["r"] = r
    g["completed"] = completed
    g["trophies_available"] = n
    g["trophies_unlocked"] = np.where(n > 0, unlocked, 0)
    return g, pl


# --- Features --------------------------------------------------------------------------------

def features(sim_games: pd.DataFrame, players: pd.DataFrame, cfg: SimConfig) -> pd.DataFrame:
    """compute_features per player (the app's function), then online_share over matched games
    only (None when the player has no matched hours). Returns the 7 or 8 feature columns."""
    rows, idx = [], []
    for pid, gg in sim_games.groupby("pid", sort=True):
        n_months = int(players.loc[pid, "months"])
        months = [f"m{k}" for k in range(n_months)]
        dicts = []
        for i, row in enumerate(gg.itertuples(index=False)):
            dicts.append({"hours": row.hours, "completed": bool(row.completed),
                          "trophies_unlocked": int(row.trophies_unlocked), "trophies_available": int(row.trophies_available),
                          "genres": row.genres, "is_online": bool(row.is_online),
                          "months": months if i == 0 else []})
        f = compute_features(dicts)
        mh = gg.loc[gg["matched"], "hours"].sum()
        f["online_share"] = float(gg.loc[gg["matched"] & gg["is_online"], "hours"].sum() / mh) if mh > 0 else None
        rows.append(f)
        idx.append(pid)
    X = pd.DataFrame(rows, index=pd.Index(idx, name="pid"))
    return X[FEATURES_ACTIVITY if cfg.activity else FEATURES_MAIN].astype(float)


def online_share_app_rule(sim_games: pd.DataFrame) -> pd.Series:
    """For comparison: the app's rule, unmatched (no modes) counted as offline."""
    tot = sim_games.groupby("pid")["hours"].sum()
    on = sim_games[sim_games["is_online"]].groupby("pid")["hours"].sum().reindex(tot.index, fill_value=0)
    return on / tot


def run(games: pd.DataFrame, seed: int, cfg: SimConfig, median_length: float):
    g, pl = simulate(games, seed, cfg, median_length)
    return g, pl, features(g, pl, cfg)


# --- Plausibility ------------------------------------------------------------------------------

def plausibility(g: pd.DataFrame) -> pd.DataFrame:
    has = g["trophies_available"] > 0
    full = has & (g["trophies_unlocked"] >= g["trophies_available"])
    e = _R2["extra_ratio_E"]
    mp = g["mp_only"]
    low = g["r"] < 0.3
    rows = [
        ("completed with r < 0.3 (all games)", int((g["completed"] & low).sum()), int(low.sum())),
        ("  of which multiplayer-only (rule 3's flat 2%)", int((g["completed"] & low & mp).sum()), int((low & mp).sum())),
        ("  of which not multiplayer-only (rule 1)", int((g["completed"] & low & ~mp).sum()), int((low & ~mp).sum())),
        ("100% trophies on an unfinished game", int((full & ~g["completed"]).sum()), int((has & ~g["completed"]).sum())),
        (f"100% trophies with r < 1 + E ({1 + e:g})", int((full & (g["r"] < 1 + e)).sum()), int((has & (g["r"] < 1 + e)).sum())),
        ("completed multiplayer-only games", int((mp & g["completed"]).sum()), int(mp.sum())),
        ("completed games overall", int(g["completed"].sum()), len(g)),
    ]
    return pd.DataFrame(rows, columns=["check", "count", "out of"])


# --- Clustering helpers --------------------------------------------------------------------------

@dataclass
class Fit:
    features: list
    impute: pd.Series
    mean: np.ndarray
    scale: np.ndarray
    centres: np.ndarray          # scaled
    labels: np.ndarray

    def z(self, X: pd.DataFrame) -> np.ndarray:
        x = X[self.features].fillna(self.impute).to_numpy(dtype=float)
        return (x - self.mean) / self.scale

    def assign(self, X: pd.DataFrame) -> np.ndarray:
        z = self.z(X)
        return np.argmin(((z[:, None, :] - self.centres[None, :, :]) ** 2).sum(axis=2), axis=1)

    def centres_original(self) -> pd.DataFrame:
        return pd.DataFrame(self.centres * self.scale + self.mean, columns=self.features)


def prepare(X: pd.DataFrame):
    from sklearn.preprocessing import StandardScaler
    impute = X.mean()
    Xf = X.fillna(impute)
    scaler = StandardScaler().fit(Xf)
    return impute, scaler, scaler.transform(Xf)


def sweep(X: pd.DataFrame, ks=range(2, 9), n_init=20, random_state=42):
    """Fits for each k. Returns {k: Fit}, silhouette {k}, inertia {k}."""
    from sklearn.cluster import KMeans
    from sklearn.metrics import silhouette_score
    impute, scaler, Z = prepare(X)
    fits, sil, inertia = {}, {}, {}
    for k in ks:
        km = KMeans(n_clusters=k, n_init=n_init, random_state=random_state).fit(Z)
        fits[k] = Fit(list(X.columns), impute, scaler.mean_, scaler.scale_, km.cluster_centers_, km.labels_)
        sil[k] = float(silhouette_score(Z, km.labels_))
        inertia[k] = float(km.inertia_)
    return fits, sil, inertia


def near_ties(sil: dict, tol: float = 0.01) -> list[int]:
    best = max(sil.values())
    return sorted(k for k, s in sil.items() if s >= best - tol)


def restart_stability(X: pd.DataFrame, k: int, n: int = 10) -> dict:
    import itertools
    from sklearn.cluster import KMeans
    from sklearn.metrics import adjusted_rand_score
    _, _, Z = prepare(X)
    labs = [KMeans(n_clusters=k, n_init=20, random_state=s).fit_predict(Z) for s in range(1, n + 1)]
    pw = [adjusted_rand_score(a, b) for a, b in itertools.combinations(labs, 2)]
    return {"mean_pairwise": float(np.mean(pw)), "min_pairwise": float(np.min(pw))}


def hungarian(ref_centres: np.ndarray, other_centres: np.ndarray):
    from scipy.optimize import linear_sum_assignment
    d = np.linalg.norm(ref_centres[:, None, :] - other_centres[None, :, :], axis=2)
    rows, cols = linear_sum_assignment(d)
    return dict(zip(rows.tolist(), cols.tolist())), d
