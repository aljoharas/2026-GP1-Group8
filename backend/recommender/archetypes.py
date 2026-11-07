"""
Player Archetypes — turning a real user's manual logs into compute_features input.

Same data rules as Wrapped: library_entries rows with source = 'manual' and a
logged_at (rating/review-only rows have none and are not play logs). Steam
rows never reach this module. hours_played NULL counts as 0.

Trophies: the app stores ticked achievements as display names in
library_entries.achievements. Names are not matched to any list. Per game:
    unlocked  = distinct ticked names across all its logs (case and
                surrounding whitespace ignored)
    available = games.achievements_count (RAWG), when above 0
                else, when the achievements table has a list for the game,
                the larger of that list's size and unlocked (fallback 1)
                else 0: the game is left out of trophy_rate, even when names
                were ticked (fallback 2)
compute_features caps each game's unlocked at available, so a game's rate is
never above 1.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg2.extras

import wrapped
from archetype_features import FEATURE_NAMES, compute_features, genre_shares

MODEL_PATH = Path(os.environ.get(
    "ARCHETYPE_MODEL_PATH",
    Path(__file__).resolve().parents[2] / "models" / "archetype_model.json",
))
REASONS_LIMIT = 2

# Where a game's trophy_rate denominator came from (build_games' counts)
TROPHY_RAWG = "rawg_count"
TROPHY_FALLBACK = "fallback"
TROPHY_EXCLUDED = "excluded"


def normalise_name(name: str) -> str:
    return name.strip().casefold()


def load_manual_logs(conn, uid: str) -> pd.DataFrame:
    """Every manual play log the user has, prepared like Wrapped's
    (wrapped.prepare_logs) plus "achievements" (ticked names) and
    "achievements_count" (games.achievements_count).
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT
            le.id,
            le.game_id,
            le.status,
            le.hours_played,
            le.logged_at,
            g.name,
            g.game_modes,
            COALESCE(le.achievements, '{}') AS achievements,
            g.achievements_count
        FROM library_entries le
        JOIN games g ON g.id = le.game_id
        WHERE le.user_id = %s
          AND le.source = %s
          AND le.logged_at IS NOT NULL
    """, (uid, wrapped.WRAPPED_SOURCE))
    rows = [dict(row) for row in cur.fetchall()]
    cur.close()
    logs = prepare_logs(rows)
    # Same statuses as Wrapped; plan_to_play is a wishlist entry, not play
    return logs[~logs["status"].isin(wrapped.EXCLUDED_STATUSES)].reset_index(drop=True)


def prepare_logs(rows: list[dict]) -> pd.DataFrame:
    """wrapped.prepare_logs, keeping each row's ticked names and its game's
    RAWG achievements_count (None when unknown).
    """
    logs = wrapped.prepare_logs(rows)
    logs["achievements"] = [list(r.get("achievements") or []) for r in rows]
    logs["achievements_count"] = [r.get("achievements_count") for r in rows]
    return logs


def load_achievement_list_sizes(conn, game_ids: list[int]) -> dict[int, int]:
    """Rows in the achievements table per game, in one query. Games with none
    are absent.
    """
    if not game_ids:
        return {}
    cur = conn.cursor()
    cur.execute("""
        SELECT game_id, COUNT(*)
        FROM achievements
        WHERE game_id = ANY(%s)
        GROUP BY game_id
    """, (list(game_ids),))
    sizes = {game_id: int(n) for game_id, n in cur.fetchall()}
    cur.close()
    return sizes


def trophy_denominator(rawg_count, list_size: int, unlocked: int) -> tuple[int, str]:
    """(available, source) for one game; see the module docstring."""
    if rawg_count is not None and not pd.isna(rawg_count) and int(rawg_count) > 0:
        return int(rawg_count), TROPHY_RAWG
    if list_size > 0:
        return max(list_size, unlocked), TROPHY_FALLBACK
    return 0, TROPHY_EXCLUDED


def build_games(
    logs: pd.DataFrame,
    game_genres: dict[int, list[str]],
    list_sizes: dict[int, int],
) -> tuple[list[dict], dict[str, int]]:
    """Logs (prepare_logs) → one compute_features game dict per game, plus how
    many games took their trophy denominator from each source.
    game_genres is wrapped.load_game_genres-shaped; list_sizes is
    load_achievement_list_sizes-shaped.
    """
    sources = {TROPHY_RAWG: 0, TROPHY_FALLBACK: 0, TROPHY_EXCLUDED: 0}
    if logs.empty:
        return [], sources
    latest = wrapped.latest_log_per_game(logs)
    games = []
    for game_id, game_logs in logs.groupby("game_id", sort=True):
        ticked = {
            normalise_name(n)
            for names in game_logs["achievements"]
            for n in names
            if isinstance(n, str) and n.strip()
        }
        available, source = trophy_denominator(
            game_logs["achievements_count"].iloc[0], list_sizes.get(int(game_id), 0), len(ticked),
        )
        sources[source] += 1
        games.append({
            "game_id": int(game_id),
            "name": game_logs["name"].iloc[0],
            "hours": float(game_logs["hours_played"].sum()),
            "completed": bool((game_logs["status"] == "completed").any()),
            "latest_status": latest.loc[game_id, "status"],
            "trophies_unlocked": len(ticked),
            "trophies_available": available,
            "genres": list(game_genres.get(int(game_id), [])),
            "is_online": wrapped.is_online(game_logs["game_modes"].iloc[0]),
            "months": sorted({ts.strftime("%Y-%m") for ts in game_logs["logged_at"]}),
        })
    return games, sources


# --- Serving ------------------------------------------------------------------

def load_model(path: Path = MODEL_PATH) -> dict:
    """The frozen model JSON, checked against the code and with numpy arrays
    added. Raises if it doesn't fit: serving a mismatched model would put
    users in the wrong archetype silently.
    """
    model = json.loads(Path(path).read_text())
    if model["features"] != FEATURE_NAMES:
        raise ValueError(f"model features {model['features']} != compute_features {FEATURE_NAMES}")
    temperature = model.get("scoring", {}).get("temperature")
    if not isinstance(temperature, (int, float)) or temperature <= 0:
        raise ValueError("model JSON has no scoring.temperature > 0")
    model["_mean"] = np.array(model["scaler"]["mean"], dtype=float)
    model["_scale"] = np.array(model["scaler"]["scale"], dtype=float)
    model["_centres"] = np.array([c["centre_scaled"] for c in model["clusters"]], dtype=float)
    return model


def scale_features(features: dict, model: dict) -> np.ndarray:
    """Impute missing features with the training mean, then standardise."""
    x = np.array([
        model["imputation"][f] if features[f] is None else features[f]
        for f in FEATURE_NAMES
    ], dtype=float)
    return (x - model["_mean"]) / model["_scale"]


def match_probabilities(z: np.ndarray, centres: np.ndarray, temperature: float) -> np.ndarray:
    """Softmax of negative Euclidean distances to each centre, divided by the
    temperature. Shifted by the nearest distance so it never overflows.
    """
    distances = np.sqrt(((centres - z) ** 2).sum(axis=1))
    weights = np.exp(-(distances - distances.min()) / temperature)
    return weights / weights.sum()


def largest_remainder(probabilities, total: int = 100) -> list[int]:
    """Whole-number percentages that add up to exactly total: floor every
    share, then give the leftover points to the largest remainders (ties go
    to the higher probability, then the earlier index). A higher probability
    never gets a lower percentage.
    """
    raw = [float(p) * total / sum(probabilities) for p in probabilities]
    floors = [math.floor(r) for r in raw]
    order = sorted(range(len(raw)), key=lambda i: (-(raw[i] - floors[i]), -raw[i], i))
    for i in order[: total - sum(floors)]:
        floors[i] += 1
    return floors


def _hours(value: float) -> str:
    return f"{value:.0f}" if value >= 10 else f"{value:.1f}".rstrip("0").rstrip(".")


def _percent(share: float) -> int:
    return int(math.floor(share * 100 + 0.5))


def reason_sentence(feature: str, above_average: bool, games: list[dict], features: dict) -> str:
    """A plain sentence with the user's real values for one feature.
    above_average says which side of the training average the user is on.
    """
    n = len(games)
    total_hours = sum(g["hours"] for g in games)
    if feature == "completion_rate":
        done = sum(1 for g in games if g["completed"])
        return (f"You've finished {done} of your {n} games" if above_average
                else f"Only {done} of your {n} games are finished so far")
    if feature == "trophy_rate":
        p = _percent(features["trophy_rate"])
        return (f"You've unlocked {p}% of the trophies in your games" if above_average
                else f"Trophies aren't your focus: {p}% unlocked across your games")
    if feature == "genre_diversity":
        shares = genre_shares(games)
        if above_average:
            return f"You've played {len(shares)} different genres"
        genre, share = max(shares.items(), key=lambda kv: (kv[1], kv[0]))
        return f"{_percent(share)}% of your play is {genre}"
    if feature == "log_hours_per_game":
        typical = math.expm1(features["log_hours_per_game"])
        return f"A typical game gets about {_hours(typical)} hours from you"
    if feature == "top_game_share":
        top = max(games, key=lambda g: g["hours"])
        p = _percent(features["top_game_share"])
        return (f"{p}% of your hours go to {top['name']}" if above_average
                else f"No single game takes more than {p}% of your hours")
    if feature == "log_activity":
        per_month = math.expm1(features["log_activity"])
        return f"You average about {_hours(per_month)} hours in each month you play"
    if feature == "online_share":
        p = _percent(features["online_share"])
        return (f"{p}% of your hours are in online games" if above_average
                else f"{100 - p}% of your hours are in offline games")
    if feature == "log_games_played":
        return f"You've played {n} games" if above_average else f"You keep to a small set of {n} games"
    raise ValueError(f"no sentence for {feature}")


def top_reasons(z: np.ndarray, centre: np.ndarray, features: dict, games: list[dict]) -> list[str]:
    """The REASONS_LIMIT features where the user's z-score points most
    strongly in the direction of their centre (largest z × centre). Imputed
    features are skipped: they aren't the user's own data.
    """
    strength = {
        f: z[i] * centre[i]
        for i, f in enumerate(FEATURE_NAMES)
        if features[f] is not None
    }
    chosen = sorted(strength, key=lambda f: -strength[f])[:REASONS_LIMIT]
    return [reason_sentence(f, z[FEATURE_NAMES.index(f)] >= 0, games, features) for f in chosen]


def archetype_response(games: list[dict], model: dict) -> dict:
    """The /archetype body for one user's games (build_games)."""
    features = compute_features(games)
    if features is None:
        return {
            "archetype": None,
            "reason": "not_enough_games",
            "games_played": len(games),
            "min_games": model["min_games"],
            "model_version": model["version"],
        }
    z = scale_features(features, model)
    probabilities = match_probabilities(z, model["_centres"], model["scoring"]["temperature"])
    percents = largest_remainder(probabilities)
    order = sorted(range(len(percents)), key=lambda i: (-percents[i], -probabilities[i], i))
    nearest = order[0]
    clusters = model["clusters"]
    return {
        "archetype": clusters[nearest]["name"],
        "description": clusters[nearest]["description"],
        "scores": [
            {"archetype": clusters[i]["name"], "description": clusters[i]["description"], "percent": percents[i]}
            for i in order
        ],
        "reasons": top_reasons(z, model["_centres"][nearest], features, games),
        "games_played": len(games),
        "model_version": model["version"],
    }
