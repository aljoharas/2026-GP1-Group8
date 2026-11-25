"""
Unit tests for archetype_features.compute_features. Every expected value is
worked out by hand in the comments next to it.

Run from recommender/:  pytest
"""

import math

import pandas as pd
import pytest

import wrapped
from archetype_features import FEATURE_NAMES, MIN_GAMES, compute_features, genre_shares


def game(hours=1.0, completed=False, unlocked=0, available=0, genres=("Action",),
         online=False, months=("2026-01",), status=None):
    return {
        "hours": hours,
        "completed": completed,
        "latest_status": status or ("completed" if completed else "playing"),
        "trophies_unlocked": unlocked,
        "trophies_available": available,
        "genres": list(genres),
        "is_online": online,
        "months": list(months),
    }


# Five games, 100 hours in total, covering null hours, a game without genres
# and games without an achievement list.
PLAYER = [
    game(hours=10,   completed=True,  unlocked=5, available=10,   genres=["Action", "RPG"], months=["2026-01"]),
    game(hours=None, completed=False, unlocked=0, available=0,    genres=[],                online=True, months=["2026-01"]),
    game(hours=30,   completed=True,  unlocked=3, available=20,   genres=["Shooter"],       online=True, months=["2026-02"]),
    game(hours=0,    completed=False, unlocked=0, available=None, genres=["Action"],        months=["2026-02"]),
    game(hours=60,   completed=False, unlocked=2, available=10,   genres=["RPG"],           months=["2026-03"]),
]


@pytest.fixture
def features():
    return compute_features(PLAYER)


def test_keys_follow_the_fixed_order(features):
    assert list(features) == FEATURE_NAMES


def test_completion_rate(features):
    # 2 of 5 games have a completed log
    assert features["completion_rate"] == pytest.approx(0.4)


def test_trophy_rate_sums_over_games_with_a_list(features):
    # (5 + 3 + 2) / (10 + 20 + 10); games 2 (0) and 4 (None) have no list
    assert features["trophy_rate"] == pytest.approx(10 / 40)


def test_genre_diversity(features):
    # Action 10/2 + 0 = 5, RPG 10/2 + 60 = 65, Shooter 30; game 2 has no genres
    # shares .05/.65/.30 → H = 0.790988 → / ln 10 = 0.343521
    assert features["genre_diversity"] == pytest.approx(0.343521, abs=1e-6)


def test_log_hours_per_game_skips_null_and_zero_hours(features):
    # (ln 11 + ln 31 + ln 61) / 3
    assert features["log_hours_per_game"] == pytest.approx(3.314252, abs=1e-6)


def test_top_game_share(features):
    # 60 / 100
    assert features["top_game_share"] == pytest.approx(0.6)


def test_log_activity_counts_each_month_once(features):
    # 3 distinct months → ln(1 + 100 / 3)
    assert features["log_activity"] == pytest.approx(math.log(1 + 100 / 3))


def test_online_share(features):
    # game 2 (null hours) and game 3 (30h) are online → 30 / 100
    assert features["online_share"] == pytest.approx(0.3)


def test_log_games_played(features):
    # 5 games → ln 5
    assert features["log_games_played"] == pytest.approx(1.609438, abs=1e-6)


def test_log_games_played_counts_games_not_hours():
    # 8 games, all with 0 hours → ln 8
    assert compute_features([game(hours=0) for _ in range(8)])["log_games_played"] == pytest.approx(2.079442, abs=1e-6)


def test_fewer_than_min_games_is_not_enough_data():
    assert MIN_GAMES == 5
    assert compute_features(PLAYER[:4]) is None
    assert compute_features([]) is None


def test_no_achievement_lists_leaves_trophy_rate_missing():
    player = [game(hours=5, available=0) for _ in range(4)] + [game(hours=5, available=None)]
    assert compute_features(player)["trophy_rate"] is None


def test_unlocked_never_exceeds_available():
    # 12 unlocked of 10 counts as 10; with 0/10 on the others → 10 / 50
    player = [game(available=10, unlocked=12)] + [game(available=10) for _ in range(4)]
    assert compute_features(player)["trophy_rate"] == pytest.approx(0.2)


def test_no_genres_leaves_genre_diversity_missing():
    player = [game(hours=5, genres=[]) for _ in range(5)]
    assert compute_features(player)["genre_diversity"] is None


def test_single_genre_has_zero_diversity():
    player = [game(hours=5, genres=["RPG"]) for _ in range(5)]
    assert compute_features(player)["genre_diversity"] == pytest.approx(0.0)


def test_genre_diversity_is_capped_at_one():
    # 12 evenly played genres: ln 12 / ln 10 = 1.079 → 1.0
    genres = [f"G{i}" for i in range(12)]
    player = [game(hours=6, genres=genres[i:i + 3]) for i in range(0, 12, 3)] + [game(genres=[])]
    assert compute_features(player)["genre_diversity"] == 1.0


def test_zero_total_hours_weights_each_game_as_one():
    # Every game 0/None hours. Genres by count: Action 2, RPG 2, Shooter 1
    # → shares .4/.4/.2 → H = 1.054920 → / ln 10 = 0.458146
    player = [
        game(hours=0, genres=["Action"]),
        game(hours=None, genres=["Action"]),
        game(hours=0, genres=["RPG"]),
        game(hours=None, genres=["RPG"]),
        game(hours=0, genres=["Shooter"], online=True),
    ]
    f = compute_features(player)
    assert f["genre_diversity"] == pytest.approx(0.458146, abs=1e-6)
    assert f["log_hours_per_game"] == 0.0
    assert f["top_game_share"] == 0.0
    assert f["log_activity"] == 0.0
    assert f["online_share"] == 0.0


def test_duplicate_genre_on_a_game_counts_once():
    assert genre_shares([game(hours=4, genres=["RPG", "RPG", "Action"])]) == {"RPG": 0.5, "Action": 0.5}


def test_genre_shares_match_wrappeds_rule():
    per_game = pd.Series({1: 10.0, 2: 0.0, 3: 30.0, 4: 0.0, 5: 60.0})
    genres = {1: ["Action", "RPG"], 3: ["Shooter"], 4: ["Action"], 5: ["RPG"]}
    expected, _ = wrapped.genre_shares(per_game, genres)
    assert genre_shares(PLAYER) == pytest.approx(expected)
