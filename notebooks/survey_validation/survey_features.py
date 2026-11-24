"""Survey answers -> archetype features -> scores with a FROZEN model. Conversion rules fixed in the
task before scoring; nothing here changes a model.

Features always go through the shared archetype_features.compute_features. Trophy rate: every game
with a known share gets the same denominator (TROPHY_DENOM), so compute_features' sum(unlocked) /
sum(available) equals the unweighted mean of the respondent's shares, as specified.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetypes  # noqa: E402
from archetype_features import FEATURE_NAMES, compute_features  # noqa: E402

# Geometric midpoints of the hour ranges
HOURS = {"Less than 2": 1.0, "2–5": 3.2, "6–10": 7.7, "11–25": 16.6, "26–50": 36.0,
         "51–100": 71.0, "101–200": 142.0, "More than 200": 280.0}
STATUS = {"Finished": "completed", "Paused": "paused", "Still Playing": "playing"}
# Trophy share midpoints; None = leave the game out of trophy rate
TROPHIES = {"0%": 0.0, "1–25%": 0.13, "26–50%": 0.38, "51–75%": 0.63, "76–99%": 0.875, "100%": 1.0,
            "The game has none": None, "Don’t know": None, "Don't know": None}
TROPHY_DENOM = 1000

# Self-description -> the archetypes it agrees with (fixed before scoring)
SELF = {
    "I like to finish games and collect trophies.": frozenset({"Completionist"}),
    "I like trying lots of different games and genres.": frozenset({"Explorer"}),
    "I sink a lot of hours into a few favourite games.": frozenset({"Devotee", "The Main"}),
    "I mostly play online or multiplayer games.": frozenset({"Competitor", "The Main"}),
    "I play now and then, when I have time.": frozenset({"Casual"}),
}
SELF_SHORT = {
    "I like to finish games and collect trophies.": "finish & trophies",
    "I like trying lots of different games and genres.": "many games & genres",
    "I sink a lot of hours into a few favourite games.": "hours in a few favourites",
    "I mostly play online or multiplayer games.": "online / multiplayer",
    "I play now and then, when I have time.": "now and then",
}


def game_dict(hours: str, status: str, trophies: str, genres: list[str], online: bool, months: list[str]) -> dict:
    """One survey game in compute_features' input shape."""
    if hours not in HOURS or status not in STATUS or trophies not in TROPHIES:
        raise ValueError(f"unknown answer: {hours!r} / {status!r} / {trophies!r}")
    share = TROPHIES[trophies]
    return {
        "hours": HOURS[hours],
        "completed": STATUS[status] == "completed",
        "latest_status": STATUS[status],
        "trophies_unlocked": 0 if share is None else int(round(share * TROPHY_DENOM)),
        "trophies_available": 0 if share is None else TROPHY_DENOM,
        "genres": list(genres),
        "is_online": bool(online),
        "months": list(months),
    }


def respondent_games(entries: pd.DataFrame, months: int) -> list[dict]:
    """entries: one respondent's rows of survey_game_matches.csv (hours, status, trophies, genres,
    online). Unmatched games have no genres and count as offline, as in the app. The respondent's
    Q1 months are put on the first game, so activity = total hours / months."""
    labels = [f"m{k}" for k in range(int(months))]
    out = []
    for i, r in enumerate(entries.itertuples(index=False)):
        genres = [] if pd.isna(r.genres) or not str(r.genres) else str(r.genres).split(";")
        out.append(game_dict(r.hours, r.status, r.trophies, genres, bool(r.online), labels if i == 0 else []))
    return out


def features(games: list[dict], games_played: str = "missing", activity: str = "computed") -> dict:
    """compute_features, then the fixed treatments:
    games_played: "missing" (form cap: fill with the training mean at scoring) | "five" (use ln 5)
    activity: "computed" (total hours / Q1 months) | "mean" (fill with the training mean)"""
    f = compute_features(games)
    if games_played == "missing":
        f["log_games_played"] = None
    elif games_played != "five":
        raise ValueError(games_played)
    if activity == "mean":
        f["log_activity"] = None
    elif activity != "computed":
        raise ValueError(activity)
    return f


def fill_missing(f: dict, model: dict) -> dict:
    """Missing features the model can't impute itself (games played, activity) get the training
    mean = the scaler mean; trophy rate and genre diversity keep the model's own imputation."""
    out = dict(f)
    for i, name in enumerate(FEATURE_NAMES):
        if out[name] is None and name not in model["imputation"]:
            out[name] = float(model["_mean"][i])
    return out


def score(f: dict, model: dict) -> dict:
    """The served scoring (archetypes.archetype_response's): softmax at the model's temperature,
    largest-remainder percentages, same ordering and blend rule."""
    z = archetypes.scale_features(fill_missing(f, model), model)
    probs = archetypes.match_probabilities(z, model["_centres"], model["scoring"]["temperature"])
    pct = archetypes.largest_remainder(probs)
    order = sorted(range(len(pct)), key=lambda i: (-pct[i], -probs[i], i))
    clusters = model["clusters"]
    return {"ranked": [(clusters[i]["name"], pct[i]) for i in order],
            "top1": clusters[order[0]]["name"], "top2": [clusters[i]["name"] for i in order[:2]],
            "blend": archetypes.blend_of(clusters, order, pct)}


# --- Statistics ---------------------------------------------------------------------------

def wilson(k: int, n: int, z: float = 1.959963984540054) -> tuple[float, float]:
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def agreement(preds: list[set], labels: list[frozenset]) -> np.ndarray:
    """1 where a prediction set (top-1 as a 1-set, or top-2) meets the respondent's mapped set."""
    return np.array([bool(set(p) & set(s)) for p, s in zip(preds, labels)], dtype=int)


def permutation_test(preds: list[set], labels: list[frozenset], n: int = 10_000, seed: int = 42) -> dict:
    """Shuffle the self-labels across respondents n times. chance = mean shuffled agreement;
    p = (1 + #shuffles >= observed) / (1 + n), one-sided."""
    rng = np.random.default_rng(seed)
    obs = int(agreement(preds, labels).sum())
    hits = np.empty(n, dtype=int)
    idx = np.arange(len(labels))
    for b in range(n):
        perm = rng.permutation(idx)
        hits[b] = agreement(preds, [labels[j] for j in perm]).sum()
    return {"observed": obs, "chance_mean": float(hits.mean()) / len(labels), "chance_count": float(hits.mean()),
            "p_value": float((1 + (hits >= obs).sum()) / (1 + n))}


def summary(preds: list[set], labels: list[frozenset], n_perm: int = 10_000) -> dict:
    a = agreement(preds, labels)
    k, n = int(a.sum()), len(a)
    lo, hi = wilson(k, n)
    perm = permutation_test(preds, labels, n_perm)
    return {"agree": k, "n": n, "share": k / n, "wilson_lo": lo, "wilson_hi": hi,
            "chance": perm["chance_mean"], "p_value": perm["p_value"]}
