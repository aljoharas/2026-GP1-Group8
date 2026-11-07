"""
Unit tests for archetypes.build_games: manual logs → compute_features input.
No database: rows are built in the shape psycopg2's RealDictCursor returns.

Run from recommender/:  pytest
"""

from datetime import datetime, timezone
from decimal import Decimal

import archetypes
from archetype_features import compute_features


def utc(*args):
    return datetime(*args, tzinfo=timezone.utc)


def row(id, game_id, hours=Decimal("2"), status="playing", logged_at=None, achievements=None, game_modes=None,
        achievements_count=None):
    return {
        "id": id,
        "game_id": game_id,
        "status": status,
        "hours_played": hours,
        "logged_at": logged_at or utc(2026, 3, 10, 12),
        "name": f"Game {game_id}",
        "game_modes": game_modes,
        "achievements": achievements,
        "achievements_count": achievements_count,
    }


def build(rows, genres=None, list_sizes=None):
    return archetypes.build_games(archetypes.prepare_logs(rows), genres or {}, list_sizes or {})


def by_id(games):
    return {g["game_id"]: g for g in games}


def test_logs_of_one_game_are_summed_into_one_game():
    games, _ = build([
        row(1, 7, hours=Decimal("2.5"), status="completed", logged_at=utc(2026, 1, 5)),
        row(2, 7, hours=None, status="paused", logged_at=utc(2026, 2, 5)),   # NULL = 0
        row(3, 7, hours=Decimal("1.5"), status="playing", logged_at=utc(2026, 2, 20)),
    ])
    assert len(games) == 1
    g = games[0]
    assert g["hours"] == 4.0
    assert g["completed"] is True                  # any log completed
    assert g["latest_status"] == "playing"         # newest log
    assert g["months"] == ["2026-01", "2026-02"]


def test_months_are_riyadh_months():
    # 22:00 UTC on Jan 31 is already Feb 1 in Riyadh
    games, _ = build([row(1, 7, logged_at=utc(2026, 1, 31, 22))])
    assert games[0]["months"] == ["2026-02"]


def test_online_and_genres_come_from_the_game():
    games, _ = build(
        [row(1, 7, game_modes=["Single player", "Massively Multiplayer Online (MMO)"]), row(2, 8, game_modes=None)],
        genres={7: ["RPG", "Action"]},
    )
    g = by_id(games)
    assert g[7]["is_online"] is True and g[7]["genres"] == ["RPG", "Action"]
    assert g[8]["is_online"] is False and g[8]["genres"] == []


def test_a_name_ticked_on_several_logs_counts_once():
    games, sources = build([
        row(1, 7, achievements=["First Blood"], achievements_count=40),
        row(2, 7, achievements=["first blood ", "Boss Slayer"], achievements_count=40),  # repeat, other case/space
        row(3, 7, achievements=["  FIRST BLOOD"], achievements_count=40),
    ])
    assert games[0]["trophies_unlocked"] == 2
    assert games[0]["trophies_available"] == 40
    assert sources == {"rawg_count": 1, "fallback": 0, "excluded": 0}


def test_names_are_not_matched_to_any_list():
    # Ticked names the achievements table doesn't know still count
    games, _ = build([row(1, 7, achievements=["Renamed Trophy", "Another"], achievements_count=10)],
                     list_sizes={7: 3})
    assert games[0]["trophies_unlocked"] == 2
    assert games[0]["trophies_available"] == 10   # RAWG count wins over the table


def test_fallback_1_uses_the_larger_of_list_size_and_ticked_names():
    games, sources = build([
        row(1, 7, achievements=["A", "B"], achievements_count=None),   # list 5 > 2 ticked → 5
        row(2, 8, achievements=["A", "B", "C"], achievements_count=0),  # RAWG 0; list 1 < 3 ticked → 3
        row(3, 9, achievements=["A"], achievements_count=None),         # no list → 1 ticked
    ], list_sizes={7: 5, 8: 1})
    g = by_id(games)
    assert (g[7]["trophies_unlocked"], g[7]["trophies_available"]) == (2, 5)
    assert (g[8]["trophies_unlocked"], g[8]["trophies_available"]) == (3, 3)
    assert (g[9]["trophies_unlocked"], g[9]["trophies_available"]) == (1, 1)
    assert sources == {"rawg_count": 0, "fallback": 3, "excluded": 0}


def test_ticked_names_above_the_rawg_count_are_capped_at_one():
    rows = [row(1, 7, achievements=["A", "B", "C"], achievements_count=2)]
    rows += [row(i, i, achievements_count=10) for i in range(2, 6)]
    games, _ = build(rows)
    # game 7: 3 ticked of 2 → counts as 2; others 0/10 → 2 / 42
    assert compute_features(games)["trophy_rate"] == 2 / 42


def test_fallback_2_game_without_any_list_is_left_out_of_trophy_rate():
    rows = [row(1, 7, achievements=["A"], achievements_count=4)]
    rows += [row(i, i, achievements=None, achievements_count=None) for i in range(2, 6)]
    games, sources = build(rows)
    g = by_id(games)
    assert all(g[i]["trophies_available"] == 0 for i in range(2, 6))
    assert sources == {"rawg_count": 1, "fallback": 0, "excluded": 4}
    # Only game 7 counts: 1 / 4
    assert compute_features(games)["trophy_rate"] == 0.25


def test_no_list_anywhere_leaves_trophy_rate_missing():
    games, _ = build([row(i, i) for i in range(1, 6)])
    assert compute_features(games)["trophy_rate"] is None


def test_blank_and_null_names_are_ignored():
    games, _ = build([row(1, 7, achievements=["", "   ", None, "A"], achievements_count=5)])
    assert games[0]["trophies_unlocked"] == 1


def test_no_logs_no_games():
    assert build([]) == ([], {"rawg_count": 0, "fallback": 0, "excluded": 0})
