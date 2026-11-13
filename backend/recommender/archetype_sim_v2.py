"""
Player Archetypes — simulated player generator v2: real games and dependent features.

Training only. Same personas (archetype_sim.PERSONAS), mix share, truncated
library-size sampling and per-game hours sampling as v1. What changes:

  A  every game is a real catalogue game (archetype_catalogue): genres, online
     flag, achievement list size and typical length come from it
  1  finishing needs enough hours
  2  trophies grow with hours, and past the main story only after finishing
  3  multiplayer-only games have no ending
  4  a hidden engagement z moves hours, active months and both propensities together
  5  10% of players are trophy hunters

Every parameter lives in RULES with its reason and source. Use
archetype_sim.generate_players(..., version=2, catalogue=...) or generate_players
below. v1 is untouched and still the default.

Common random numbers: each player and each game draws the same random numbers
whichever rules are switched on, so a sensitivity variant differs from v2 only
through the rule it changes, not through a shifted random stream.
"""

from __future__ import annotations

import copy
import math

import numpy as np
import pandas as pd

from archetype_sim import GENRES, MIX_WEIGHT_RANGE, PERSONA_NAMES, PERSONAS, _assign_months, sample_library_size

# Rule 1: P(completed) = p * logistic((ln r - ln R_MID) / R_SCALE), r = hours / typical length.
# Chosen so the logistic factor is exactly 0.05 at r = 0.5 and 0.95 at r = 1.5,
# symmetric in ln r: R_MID = sqrt(0.5 * 1.5), R_SCALE = ln 3 / (2 ln 19).
_R_LOW, _R_HIGH, _EDGE = 0.5, 1.5, 0.05
R_MID = math.sqrt(_R_LOW * _R_HIGH)
R_SCALE = math.log(_R_HIGH / _R_LOW) / (2 * math.log((1 - _EDGE) / _EDGE))

RULES = {
    "real_games": {
        "on": True,
        "popularity_weight": "steam200k_players",
        "reason": "Genres, online flag, list size and length belong to a game, so they are taken "
                  "from a real one; common games are drawn more often.",
        "source": "Steam Store Games (Kaggle, SteamSpy 2019) + Steam 200k player counts",
    },
    "rule1_finish_needs_hours": {
        "on": True,
        "r_low": _R_LOW, "r_high": _R_HIGH, "edge": _EDGE,
        "r_mid": R_MID, "r_scale": R_SCALE,
        "reason": "You can't finish a game without playing it through: P(completed) < 5% of p "
                  "below half the typical length, >= 95% of p from 1.5x, logistic in ln r between.",
        "source": "Logic; main-story lengths from HowLongToBeat (Bailey et al., arXiv 2205.15163)",
    },
    "rule2_trophies_follow_hours": {
        "on": True,
        "extra_ratio_E": 2.0,
        "reason": "Trophies accrue evenly over the hours a full list takes, L * (1 + E); the part "
                  "after the main story (r > 1) only counts once the game is completed. Full set "
                  "only when completed and r >= 1 + E. Scaled by the per-game trophy Beta draw.",
        "source": "Bailey et al.: +8.6h after the main story for shorter games, +23.6h for "
                  "full-price ones, about 1.7-2.25x the main story -> E = 2",
    },
    "rule3_multiplayer_only_no_ending": {
        "on": True,
        "p_completed": 0.02,
        "reason": "Live-service games have no ending to reach; 2% allows campaigns the store "
                  "categories don't show.",
        "source": "Logic",
    },
    "rule4_engagement": {
        "on": True,
        "hours_quantile_shift": 0.05,   # added to the hours quantile u per +1 z
        "months_per_z": 1.0,            # active months per +1 z
        "logit_shift": 0.3,             # completion and trophy propensities, logit scale, per +1 z
        "reason": "Engaged players play more and also pursue more goals, so one hidden z ~ N(0,1) "
                  "moves hours, active months and both propensities together, moderately.",
        "source": "Logic",
    },
    "rule5_trophy_hunters": {
        "on": True,
        "share": 0.10,
        "floor_beta": (4, 4),
        "reason": "Some players chase trophies on every game: on every game with a list their "
                  "trophy fraction is at least a Beta(4,4) draw, even unfinished (never 100%).",
        "source": "Bailey et al.: trophy completion rates are bimodal, easy trophies attributed "
                  "to players chasing profile scores",
    },
}


def rules_variant(**changes) -> dict:
    """A copy of RULES with changes, e.g. rules_variant(rule1_finish_needs_hours={"on": False})."""
    rules = copy.deepcopy(RULES)
    for name, values in changes.items():
        rules[name].update(values)
    return rules


def _logit(p: float) -> float:
    p = min(max(p, 1e-9), 1 - 1e-9)
    return math.log(p / (1 - p))


def _sigmoid(x: float) -> float:
    return 1 / (1 + math.exp(-x))


def finish_factor(r: float) -> float:
    """Rule 1's logistic factor of P(completed) for hours/typical-length ratio r."""
    if r <= 0:
        return 0.0
    return _sigmoid((math.log(r) - math.log(R_MID)) / R_SCALE)


# --- Catalogue pools ------------------------------------------------------------

class Catalogue:
    """Fast weighted draws from the catalogue by (genre, online)."""

    def __init__(self, cat: pd.DataFrame):
        self.df = cat.reset_index(drop=True)
        self.weight = self.df["steam200k_players"].to_numpy(dtype=float)
        self.online = self.df["is_online"].to_numpy(dtype=bool)
        self.genre_sets = [set(g) for g in self.df["genre_list"]]
        self.has_genre = {g: np.array([g in s for s in self.genre_sets]) for g in GENRES}
        self.records = self.df[["appid", "name", "is_online", "is_multiplayer_only",
                                "achievement_count", "typical_length_h"]].to_dict("records")
        for rec, genres in zip(self.records, self.df["genre_list"]):
            rec["genres"] = list(genres)

    def draw(self, genre: str, online: bool, owned: np.ndarray, u: float) -> tuple[int, int]:
        """(row, fallback level) of one game with u ~ U(0,1). Level 0: genre and online flag
        match; 1: genre only; 2: online flag only; 3: any game. Never a game already owned.
        """
        free = ~owned
        g, o = self.has_genre[genre], self.online == online
        for level, mask in enumerate((g & o, g, o, np.ones_like(g))):
            w = self.weight * (mask & free)
            total = w.sum()
            if total > 0:
                return int(np.searchsorted(np.cumsum(w), u * total, side="right")), level
        raise ValueError("catalogue exhausted")


# --- Generator ------------------------------------------------------------------

def _player_params(name: str, rng: np.random.Generator, calibration: dict) -> dict:
    """v1's per-player draws (archetype_sim._player_params), same order."""
    p = PERSONAS[name]
    n_fav = rng.integers(p["favourite_genres"][0], p["favourite_genres"][1] + 1)
    return {
        "name": name,
        "completion": rng.beta(*p["completion_beta"]),
        "online": rng.beta(*p["online_beta"]),
        "favourites": list(rng.choice(GENRES, size=n_fav, replace=False)),
        "library_size": sample_library_size(calibration["library_sizes"], p["library_size"], rng),
        "active_months": int(rng.integers(p["active_months"][0], p["active_months"][1] + 1)),
    }


def _game(params: dict, player: dict, rng, calibration, catalogue: Catalogue, owned, top_game, rules, log):
    p = PERSONAS[params["name"]]
    r4, r5 = rules["rule4_engagement"], rules["rule5_trophy_hunters"]
    z = player["z"] if r4["on"] else 0.0

    # Fixed bundle of draws per game (common random numbers)
    u_hours, u_online, u_fav, u_game, u_complete, u_status = rng.random(6)
    first_fav = str(rng.choice(params["favourites"]))
    first_any = str(rng.choice(GENRES))
    t1, t2 = rng.beta(*p["trophy_beta"]), rng.beta(*p["trophy_beta"])
    hunt_floor = rng.beta(*r5["floor_beta"])

    # Hours: v1's quantile draw, shifted by engagement and clipped to the persona range
    low, high = p["top_game_quantiles"] if top_game else p["hours_quantiles"]
    u = low + (high - low) * u_hours
    u = min(max(u + r4["hours_quantile_shift"] * z, low), high)
    hours = float(np.quantile(calibration["hours"], u))

    # A: a real game, from the persona's genre rule and P(online)
    genre = first_fav if u_fav < p["favourite_share"] else first_any
    want_online = bool(u_online < params["online"])
    row, level = catalogue.draw(genre, want_online, owned, u_game)
    owned[row] = True
    log["fallback"][level] += 1
    g = catalogue.records[row]
    length = float(g["typical_length_h"])
    r = hours / length
    mp_only = bool(g["is_multiplayer_only"])

    # Rules 1 and 3: completion
    prop = _sigmoid(_logit(params["completion"]) + r4["logit_shift"] * z)
    if mp_only and rules["rule3_multiplayer_only_no_ending"]["on"]:
        p_done = rules["rule3_multiplayer_only_no_ending"]["p_completed"]
    elif rules["rule1_finish_needs_hours"]["on"]:
        p_done = prop * finish_factor(r)
    else:
        p_done = prop
    completed = bool(u_complete < p_done)
    status = "completed" if completed else ("paused" if u_status < 0.5 else "playing")

    # Rules 2 and 5: trophies
    available = int(g["achievement_count"])
    unlocked = 0
    if available > 0:
        shift = r4["logit_shift"] * z
        t1, t2 = _sigmoid(_logit(t1) + shift), _sigmoid(_logit(t2) + shift)
        r2 = rules["rule2_trophies_follow_hours"]
        if r2["on"]:
            e = r2["extra_ratio_E"]
            progress = min(r, 1 + e) if completed else min(r, 1.0)
            fraction = t1 * progress / (1 + e)
            full_allowed = completed and r >= 1 + e
        else:  # v1: one Beta draw, the larger of two when completed; no gate
            fraction = max(t1, t2) if completed else t1
            full_allowed = True
        if player["hunter"]:
            fraction = max(fraction, hunt_floor)
            full_allowed = full_allowed and completed  # a hunter's partial draw never makes a full set
        unlocked = int(round(fraction * available))
        if not full_allowed:
            unlocked = min(unlocked, available - 1)

    return {
        "hours": hours,
        "completed": completed,
        "latest_status": status,
        "trophies_unlocked": unlocked,
        "trophies_available": available,
        "genres": list(g["genres"]),
        "is_online": bool(g["is_online"]),
        "months": [],
        # Diagnostics only; compute_features ignores extra keys
        "_appid": int(g["appid"]), "_name": g["name"], "_r": r, "_mp_only": mp_only,
        "_typical_length_h": length, "_hunter": player["hunter"], "_want_online": want_online,
    }


def _simulate(sources, weight, rng, calibration, catalogue, rules, log):
    def pick():
        return sources[0] if len(sources) == 1 or rng.random() < weight else sources[1]

    # Per-player draws, always made (common random numbers)
    z = float(rng.standard_normal())
    r5 = rules["rule5_trophy_hunters"]
    hunter = bool(rng.random() < r5["share"]) and r5["on"]
    player = {"z": z, "hunter": hunter}
    r4 = rules["rule4_engagement"]
    zz = z if r4["on"] else 0.0

    n_games = pick()["library_size"]
    month_src = pick()
    lo, hi = PERSONAS[month_src["name"]]["active_months"]
    n_months = int(min(max(month_src["active_months"] + round(r4["months_per_z"] * zz), lo), hi))

    owned = np.zeros(len(catalogue.records), dtype=bool)
    games, had_top_game = [], set()
    for _ in range(n_games):
        params = pick()
        top_game = PERSONAS[params["name"]]["top_game_quantiles"] is not None and params["name"] not in had_top_game
        if top_game:
            had_top_game.add(params["name"])
        games.append(_game(params, player, rng, calibration, catalogue, owned, top_game, rules, log))
    _assign_months(games, n_months, rng)
    return games, player


def generate_players(calibration: dict, catalogue, n_per_persona: int = 100, mix_share: float = 0.25,
                     seed: int = 42, rules: dict | None = None, log: dict | None = None) -> list[dict]:
    """v2 players, same shape and population layout as archetype_sim.generate_players,
    plus "z" and "hunter" per player. catalogue is archetype_catalogue.load_catalogue's
    DataFrame (or a Catalogue). log, when given, collects fallback counts.
    """
    rules = RULES if rules is None else rules
    if not rules["real_games"]["on"]:
        raise ValueError("v2 always draws real games")
    cat = catalogue if isinstance(catalogue, Catalogue) else Catalogue(catalogue)
    log = {} if log is None else log
    log.setdefault("fallback", [0, 0, 0, 0])

    rng = np.random.default_rng(seed)
    n_pure = n_per_persona * len(PERSONA_NAMES)
    n_mixed = int(round(n_pure * mix_share / (1 - mix_share)))

    players = []
    for name in PERSONA_NAMES:
        for _ in range(n_per_persona):
            games, extra = _simulate([_player_params(name, rng, calibration)], 1.0, rng, calibration, cat, rules, log)
            players.append({"persona": name, "games": games, **extra})
    for _ in range(n_mixed):
        a, b = (str(n) for n in rng.choice(PERSONA_NAMES, size=2, replace=False))
        weight = rng.uniform(*MIX_WEIGHT_RANGE)
        sources = [_player_params(a, rng, calibration), _player_params(b, rng, calibration)]
        games, extra = _simulate(sources, weight, rng, calibration, cat, rules, log)
        players.append({"persona": f"mixed:{a}+{b}", "games": games, **extra})

    return [{"player_id": i, **p} for i, p in enumerate(players)]
