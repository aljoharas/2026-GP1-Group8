"""
Player Archetypes — the one shared feature function.

The training notebook, the simulated players (archetype_sim.py) and the
/archetype endpoint all turn a player into features through compute_features,
so the model is served on exactly the features it was trained on.

Pure Python on purpose (no DB, no pandas): it imports cleanly in Colab.

Input: one player's games, one dict per game (not per log):
    hours               float, every log's hours summed; NULL logs count as 0
    completed           bool, True when any log of the game is 'completed'
    latest_status       'playing' | 'completed' | 'paused' (not used by a feature)
    trophies_unlocked   int, distinct achievements unlocked
    trophies_available  int, size of the game's achievement list; 0/None = no list
    genres              list of genre names; [] = no genres
    is_online           bool, from games.game_modes (see wrapped.is_online)
    months              months the game was logged in, any hashable key
                        such as "2026-03"
"""

from __future__ import annotations

import math

MIN_GAMES = 5

# Fixed order: the scaler, the centres and the model JSON all follow it
FEATURE_NAMES = [
    "completion_rate",
    "trophy_rate",
    "genre_diversity",
    "log_hours_per_game",
    "top_game_share",
    "log_activity",
    "online_share",
    "log_games_played",
]

# Features that can be missing (None) and are imputed with the training mean
IMPUTED_FEATURES = ["trophy_rate", "genre_diversity"]

# Entropy is divided by ln(10): ten evenly played genres score 1.0
GENRE_DIVERSITY_BASE = 10


def _hours(game: dict) -> float:
    h = game.get("hours")
    return 0.0 if h is None or (isinstance(h, float) and math.isnan(h)) else float(h)


def genre_shares(games: list[dict]) -> dict[str, float]:
    """Each genre's share of the player's games. A game's weight is its hours,
    split equally between its genres; when those games have 0 hours in total,
    every game weighs 1. Games without genres are skipped. Same rule as
    wrapped.genre_shares. Shares add up to 1; {} when no game has genres.
    """
    with_genres = [(g, list(dict.fromkeys(g["genres"]))) for g in games if g.get("genres")]
    if not with_genres:
        return {}
    use_hours = sum(_hours(g) for g, _ in with_genres) > 0

    weights: dict[str, float] = {}
    for game, genres in with_genres:
        weight = _hours(game) if use_hours else 1.0
        for genre in genres:
            weights[genre] = weights.get(genre, 0.0) + weight / len(genres)

    total = sum(weights.values())
    return {genre: w / total for genre, w in weights.items()}


def compute_features(games: list[dict]) -> dict[str, float | None] | None:
    """The 8 archetype features for one player, keyed in FEATURE_NAMES order.

    None ("not enough data") with fewer than MIN_GAMES games. trophy_rate is
    None when no game has an achievement list, genre_diversity when no game
    has genres; both are imputed later, not here.
    """
    if len(games) < MIN_GAMES:
        return None

    hours = [_hours(g) for g in games]
    total_hours = sum(hours)

    completion_rate = sum(1 for g in games if g.get("completed")) / len(games)

    with_list = [g for g in games if (g.get("trophies_available") or 0) > 0]
    trophy_rate = None
    if with_list:
        unlocked = sum(min(g.get("trophies_unlocked") or 0, g["trophies_available"]) for g in with_list)
        trophy_rate = unlocked / sum(g["trophies_available"] for g in with_list)

    shares = genre_shares(games)
    genre_diversity = None
    if shares:
        entropy = -sum(p * math.log(p) for p in shares.values() if p > 0)
        genre_diversity = min(entropy / math.log(GENRE_DIVERSITY_BASE), 1.0)

    played = [h for h in hours if h > 0]
    log_hours_per_game = sum(math.log1p(h) for h in played) / len(played) if played else 0.0

    top_game_share = max(hours) / total_hours if total_hours > 0 else 0.0

    months = set()
    for g in games:
        months.update(g.get("months") or ())
    log_activity = math.log1p(total_hours / max(len(months), 1))

    online_hours = sum(h for g, h in zip(games, hours) if g.get("is_online"))
    online_share = online_hours / total_hours if total_hours > 0 else 0.0

    return {
        "completion_rate": completion_rate,
        "trophy_rate": trophy_rate,
        "genre_diversity": genre_diversity,
        "log_hours_per_game": log_hours_per_game,
        "top_game_share": top_game_share,
        "log_activity": log_activity,
        "online_share": online_share,
        "log_games_played": math.log(len(games)),
    }
