"""
Player Archetypes — Steam 200k calibration and the simulated player generator.

Training only: the /archetype endpoint never imports this. The generator
outputs game-level dicts in exactly the shape archetype_features.compute_features
takes, so simulated features come from the shared function, never drawn directly.

Steam 200k (data/steam-200k.csv, no header): user_id, game_title, behavior
("purchase" | "play"), value (hours for "play"), and an unused 5th column.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

STEAM_COLUMNS = ["user_id", "game", "behavior", "value", "unused"]
HOURS_CAP_QUANTILE = 0.99  # Steam counts idle time; the top 1% is mostly left-running clients
MIN_LIBRARY = 5            # same as archetype_features.MIN_GAMES

# RAWG's 19 genre names
GENRES = [
    "Action", "Indie", "Adventure", "RPG", "Strategy", "Shooter", "Casual",
    "Simulation", "Puzzle", "Arcade", "Platformer", "Massively Multiplayer",
    "Racing", "Sports", "Fighting", "Family", "Board Games", "Educational", "Card",
]
MAX_GENRES_PER_GAME = 3
P_ACHIEVEMENT_LIST = 0.8           # most games have a trophy list, some don't
ACHIEVEMENT_LIST_SIZE = (10, 60)   # typical Steam list sizes, inclusive
MONTHS = [f"2025-{m:02d}" for m in range(1, 13)]  # one simulated year

# Every persona parameter. Ranges are inclusive; quantiles index the Steam
# per-game hours distribution; *_beta are (a, b) of a per-player Beta draw.
PERSONAS = {
    "completionist": {
        "library_size": (5, 15),          # finishes what it starts, so a moderate library
        "hours_quantiles": (0.25, 0.90),  # plays each game long enough to see it through
        "top_game_quantiles": None,       # no single dominant game
        "completion_beta": (8, 2),        # finishes most games (mean 0.8)
        "trophy_beta": (6, 4),            # hunts trophies (mean 0.6)
        "favourite_genres": (3, 4),       # sticks to a few genres it knows it likes
        "favourite_share": 0.70,          # but not exclusively
        "online_beta": (2, 5),            # mostly single-player (mean 0.29)
        "active_months": (6, 12),         # plays through most of the year
    },
    "explorer": {
        "library_size": (10, 40),         # samples many games
        "hours_quantiles": (0.05, 0.60),  # tries a game, moves on
        "top_game_quantiles": None,       # no single dominant game
        "completion_beta": (2.5, 4),      # finishes some (mean 0.38)
        "trophy_beta": (2, 6),            # trophies are incidental (mean 0.25)
        "favourite_genres": (12, 12),     # spreads evenly over ~12 genres
        "favourite_share": 1.0,           # first genre always from that wide pool
        "online_beta": (2, 5),            # mostly single-player (mean 0.29)
        "active_months": (6, 12),         # plays through most of the year
    },
    "devotee": {
        "library_size": (5, 10),          # few games besides the main one
        "hours_quantiles": (0.05, 0.50),  # side games get little time
        "top_game_quantiles": (0.95, 0.995),  # one game from the top 5% of Steam hours
        "completion_beta": (3, 4),        # average finisher (mean 0.43)
        "trophy_beta": (2, 6),            # trophies are incidental (mean 0.25)
        "favourite_genres": (1, 2),       # narrow taste around the main game
        "favourite_share": 0.85,          # rarely strays from it
        "online_beta": (2, 5),            # mostly single-player (mean 0.29)
        "active_months": (6, 12),         # plays through most of the year
    },
    "competitor": {
        "library_size": (5, 15),          # a moderate library
        "hours_quantiles": (0.40, 0.95),  # long sessions in the games it plays
        "top_game_quantiles": None,       # no single dominant game
        "completion_beta": (3, 4),        # average finisher (mean 0.43)
        "trophy_beta": (2, 6),            # trophies are incidental (mean 0.25)
        "favourite_genres": (3, 4),       # a few favourite genres
        "favourite_share": 0.70,          # but not exclusively
        "online_beta": (8, 2),            # mostly online/multiplayer (mean 0.8)
        "active_months": (6, 12),         # plays through most of the year
    },
    "casual": {
        "library_size": (5, 8),           # a small library
        "hours_quantiles": (0.05, 0.50),  # short play per game
        "top_game_quantiles": None,       # no single dominant game
        "completion_beta": (2, 4),        # finishes few games (mean 0.33)
        "trophy_beta": (2, 6),            # trophies are incidental (mean 0.25)
        "favourite_genres": (3, 4),       # a few favourite genres
        "favourite_share": 0.70,          # but not exclusively
        "online_beta": (2, 5),            # mostly single-player (mean 0.29)
        "active_months": (2, 5),          # plays in a few months of the year only
    },
}
PERSONA_NAMES = list(PERSONAS)
MIX_WEIGHT_RANGE = (0.3, 0.7)  # a mixed player's share of persona A


# --- Steam 200k ---------------------------------------------------------------

def load_steam_plays(path: str) -> pd.DataFrame:
    """'play' rows with hours > 0, summed per (user, game). Not capped.
    Columns: user_id, game, hours.
    """
    raw = pd.read_csv(path, header=None, names=STEAM_COLUMNS)
    plays = raw[(raw["behavior"] == "play") & (raw["value"] > 0)]
    return (
        plays.groupby(["user_id", "game"], as_index=False)["value"].sum()
        .rename(columns={"value": "hours"})
    )


def steam_calibration(plays: pd.DataFrame) -> dict:
    """The distributions the generator samples from.

    hours are capped at the 99th percentile of all (user, game) plays; both
    distributions then come from users with MIN_LIBRARY+ played games, the
    population the generator simulates.
    Returns {"cap", "hours" (sorted per-game hours), "library_sizes"}.
    """
    cap = float(plays["hours"].quantile(HOURS_CAP_QUANTILE))
    library = plays.groupby("user_id").size()
    keep = library[library >= MIN_LIBRARY].index
    hours = plays.loc[plays["user_id"].isin(keep), "hours"].clip(upper=cap)
    return {
        "cap": cap,
        "hours": np.sort(hours.to_numpy(dtype=float)),
        "library_sizes": library[library >= MIN_LIBRARY].to_numpy(dtype=int),
    }


# --- Generator ----------------------------------------------------------------

def _player_params(name: str, rng: np.random.Generator, calibration: dict) -> dict:
    """Per-player draws for one persona: the Betas, favourites, library, months."""
    p = PERSONAS[name]
    n_fav = rng.integers(p["favourite_genres"][0], p["favourite_genres"][1] + 1)
    return {
        "name": name,
        "completion": rng.beta(*p["completion_beta"]),
        "online": rng.beta(*p["online_beta"]),
        "favourites": list(rng.choice(GENRES, size=n_fav, replace=False)),
        "library_size": int(np.clip(rng.choice(calibration["library_sizes"]), *p["library_size"])),
        "active_months": int(rng.integers(p["active_months"][0], p["active_months"][1] + 1)),
    }


def _game(params: dict, rng: np.random.Generator, calibration: dict, top_game: bool) -> dict:
    """One simulated game drawn from a persona's rules. months is filled later."""
    p = PERSONAS[params["name"]]
    low, high = p["top_game_quantiles"] if top_game else p["hours_quantiles"]
    hours = float(np.quantile(calibration["hours"], rng.uniform(low, high)))

    completed = bool(rng.random() < params["completion"])
    status = "completed" if completed else str(rng.choice(["paused", "playing"]))

    available = unlocked = 0
    if rng.random() < P_ACHIEVEMENT_LIST:
        available = int(rng.integers(ACHIEVEMENT_LIST_SIZE[0], ACHIEVEMENT_LIST_SIZE[1] + 1))
        fraction = rng.beta(*p["trophy_beta"])
        if completed:  # finishing a game unlocks more of its list
            fraction = max(fraction, rng.beta(*p["trophy_beta"]))
        unlocked = int(round(fraction * available))

    if rng.random() < p["favourite_share"]:
        first = str(rng.choice(params["favourites"]))
    else:
        first = str(rng.choice(GENRES))
    others = [g for g in GENRES if g != first]
    extra = int(rng.integers(0, MAX_GENRES_PER_GAME))
    genres = [first] + [str(g) for g in rng.choice(others, size=extra, replace=False)]

    return {
        "hours": hours,
        "completed": completed,
        "latest_status": status,
        "trophies_unlocked": unlocked,
        "trophies_available": available,
        "genres": genres,
        "is_online": bool(rng.random() < params["online"]),
        "months": [],
    }


def _assign_months(games: list[dict], n_months: int, rng: np.random.Generator) -> None:
    """Spread n_months distinct months over the games so every one is used and
    every game has at least one."""
    months = list(rng.choice(MONTHS, size=n_months, replace=False))
    order = rng.permutation(len(games))
    for i, month in enumerate(months):
        games[order[i % len(games)]]["months"].append(str(month))
    for game in games:
        if not game["months"]:
            game["months"].append(str(rng.choice(months)))


def _simulate(sources: list[dict], weight: float, rng: np.random.Generator, calibration: dict) -> list[dict]:
    """One player's games. sources is [A] for a pure player or [A, B] for a
    mixed one; each mixed game (and the library size and active months) comes
    from A with probability weight, else from B.
    """
    def pick() -> dict:
        return sources[0] if len(sources) == 1 or rng.random() < weight else sources[1]

    n_games = pick()["library_size"]
    n_months = pick()["active_months"]
    games, had_top_game = [], set()
    for _ in range(n_games):
        params = pick()
        # A devotee's first game is its one big game
        top_game = PERSONAS[params["name"]]["top_game_quantiles"] is not None and params["name"] not in had_top_game
        if top_game:
            had_top_game.add(params["name"])
        games.append(_game(params, rng, calibration, top_game))
    _assign_months(games, n_months, rng)
    return games


def generate_players(calibration: dict, n_per_persona: int = 100, mix_share: float = 0.25, seed: int = 42) -> list[dict]:
    """Simulated players: n_per_persona pure players per persona, plus mixed
    players so that mix_share of the whole population is mixed.

    Returns [{"player_id", "persona", "games"}]; persona is a PERSONAS name or
    "mixed:A+B"; games is compute_features' input. Same seed → same output.
    """
    rng = np.random.default_rng(seed)
    n_pure = n_per_persona * len(PERSONA_NAMES)
    n_mixed = int(round(n_pure * mix_share / (1 - mix_share)))

    players = []
    for name in PERSONA_NAMES:
        for _ in range(n_per_persona):
            games = _simulate([_player_params(name, rng, calibration)], 1.0, rng, calibration)
            players.append({"persona": name, "games": games})
    for _ in range(n_mixed):
        a, b = (str(n) for n in rng.choice(PERSONA_NAMES, size=2, replace=False))
        weight = rng.uniform(*MIX_WEIGHT_RANGE)
        sources = [_player_params(a, rng, calibration), _player_params(b, rng, calibration)]
        players.append({"persona": f"mixed:{a}+{b}", "games": _simulate(sources, weight, rng, calibration)})

    return [{"player_id": i, **p} for i, p in enumerate(players)]
