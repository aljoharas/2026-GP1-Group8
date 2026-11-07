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


def row(id, game_id, hours=Decimal("2"), status="playing", logged_at=None, achievements=None, game_modes=None):
    return {
        "id": id,
        "game_id": game_id,
        "status": status,
        "hours_played": hours,
        "logged_at": logged_at or utc(2026, 3, 10, 12),
        "name": f"Game {game_id}",
        "game_modes": game_modes,
        "achievements": achievements,
    }


def build(rows, genres=None, names=None):
    return archetypes.build_games(archetypes.prepare_logs(rows), genres or {}, names or {})


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


def test_an_achievement_ticked_on_several_logs_counts_once():
    names = {7: {"first blood", "boss slayer", "collector"}}
    games, unmatched = build([
        row(1, 7, achievements=["First Blood"]),
        row(2, 7, achievements=["first blood ", "Boss Slayer"]),   # repeat, other case/space
        row(3, 7, achievements=["  FIRST BLOOD"]),
    ], names=names)
    assert games[0]["trophies_unlocked"] == 2
    assert games[0]["trophies_available"] == 3
    assert unmatched == 0


def test_unmatched_names_are_counted_once_per_game_and_not_unlocked():
    names = {7: {"first blood", "collector"}}
    games, unmatched = build([
        row(1, 7, achievements=["First Blood", "Renamed Trophy"]),
        row(2, 7, achievements=["renamed trophy", "Another Typo"]),
        row(3, 8, achievements=["Renamed Trophy"]),                 # other game: counted again
    ], names=names)
    g = by_id(games)
    assert g[7]["trophies_unlocked"] == 1
    assert g[8]["trophies_unlocked"] == 0
    assert unmatched == 3   # game 7: renamed trophy, another typo; game 8: renamed trophy


def test_game_without_an_achievement_list_is_left_out_of_trophy_rate():
    names = {7: {"a", "b", "c", "d"}}
    rows = [row(1, 7, achievements=["A"])]
    rows += [row(i, i, achievements=["Ticked Anyway"] if i == 2 else None) for i in range(2, 6)]
    games, unmatched = build(rows, names=names)
    g = by_id(games)
    assert g[2]["trophies_available"] == 0          # no list → excluded
    assert unmatched == 1                           # its ticked name can't match
    # Only game 7 has a list: 1 / 4
    assert compute_features(games)["trophy_rate"] == 0.25


def test_blank_and_null_names_are_ignored():
    games, unmatched = build([row(1, 7, achievements=["", "   ", None, "A"])], names={7: {"a"}})
    assert games[0]["trophies_unlocked"] == 1 and unmatched == 0


def test_no_logs_no_games():
    assert build([]) == ([], 0)
