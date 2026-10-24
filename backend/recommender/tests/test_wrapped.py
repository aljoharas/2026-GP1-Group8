"""
Unit tests for wrapped.py's pure functions. No database: rows are built in the
shape psycopg2's RealDictCursor returns (Decimal hours, UTC-aware timestamps).

Run from recommender/:  pytest
"""

from datetime import datetime, timezone
from decimal import Decimal

import pytest

import wrapped
from wrapped import FULL, LOCKED, PARTIAL, WRAPPED_TZ


def riyadh(*args):
    return datetime(*args, tzinfo=WRAPPED_TZ)


def utc(*args):
    return datetime(*args, tzinfo=timezone.utc)


def row(game_id=1, hours=Decimal("2.5"), logged_at=None, status="completed", **extra):
    return {
        "id": extra.get("id", 1),
        "game_id": game_id,
        "status": status,
        "hours_played": hours,
        "logged_at": logged_at or utc(2026, 6, 1, 12),
        "name": extra.get("name", f"Game {game_id}"),
        "game_modes": extra.get("game_modes"),
        "cover_image": extra.get("cover_image"),
        "background_image": extra.get("background_image"),
    }


def fake_lookup(game_ids):
    """Stands in for load_games: every game has a name and a cover."""
    return {
        gid: {"id": gid, "name": f"Game {gid}", "cover_image": f"cover-{gid}.jpg", "background_image": None}
        for gid in game_ids
    }


# --- parse_year ---------------------------------------------------------------

NOW = riyadh(2026, 10, 21, 12)


def test_parse_year_defaults_to_current_riyadh_year():
    assert wrapped.parse_year(None, NOW) == 2026
    assert wrapped.parse_year("", NOW) == 2026


def test_parse_year_default_uses_riyadh_not_utc():
    # 22:00 UTC on Dec 31 is already Jan 1 in Riyadh
    assert wrapped.parse_year(None, utc(2026, 12, 31, 22)) == 2027


@pytest.mark.parametrize("raw", ["abc", "2026.5", "20x6"])
def test_parse_year_rejects_non_integers(raw):
    with pytest.raises(ValueError):
        wrapped.parse_year(raw, NOW)


@pytest.mark.parametrize("raw", ["1999", "2101", "-5"])
def test_parse_year_rejects_out_of_range(raw):
    with pytest.raises(ValueError):
        wrapped.parse_year(raw, NOW)


@pytest.mark.parametrize("raw, expected", [("2000", 2000), ("2100", 2100), (" 2025 ", 2025)])
def test_parse_year_accepts_range_bounds(raw, expected):
    assert wrapped.parse_year(raw, NOW) == expected


# --- access_state -------------------------------------------------------------

@pytest.mark.parametrize("early_access", [True, False])
def test_past_year_is_full(early_access):
    assert wrapped.access_state(2025, early_access, NOW) == FULL


@pytest.mark.parametrize("early_access", [True, False])
def test_future_year_is_locked(early_access):
    assert wrapped.access_state(2027, early_access, NOW) == LOCKED


def test_current_year_before_release_depends_on_flag():
    assert wrapped.access_state(2026, True, NOW) == PARTIAL
    assert wrapped.access_state(2026, False, NOW) == LOCKED


def test_current_year_unlocks_on_release_date_in_riyadh():
    # 21:30 UTC Dec 30 = 00:30 Riyadh Dec 31
    assert wrapped.access_state(2026, False, utc(2026, 12, 30, 21, 30)) == FULL
    # 20:30 UTC Dec 30 = 23:30 Riyadh Dec 30
    assert wrapped.access_state(2026, False, utc(2026, 12, 30, 20, 30)) == LOCKED


def test_locked_response_shape():
    response = wrapped.locked_response(2027)
    assert list(response) == ["year", "locked", "release_date"]
    assert response == {
        "year": 2027,
        "locked": True,
        "release_date": "2027-12-31",
    }


# --- prepare_logs -------------------------------------------------------------

def test_prepare_logs_converts_decimal_and_null_hours_to_float():
    df = wrapped.prepare_logs([row(hours=Decimal("1.25")), row(hours=None)])
    assert df["hours_played"].tolist() == [1.25, 0.0]
    assert df["hours_played"].dtype == "float64"


def test_prepare_logs_converts_logged_at_to_riyadh():
    df = wrapped.prepare_logs([row(logged_at=utc(2026, 1, 1, 0))])
    assert str(df["logged_at"].dt.tz) == "Asia/Riyadh"
    assert df["logged_at"].iloc[0].hour == 3


def test_prepare_logs_handles_no_rows():
    df = wrapped.prepare_logs([])
    assert df.empty
    assert list(df.columns) == wrapped.LOG_COLUMNS
    assert df["hours_played"].dtype == "float64"


# --- select_year_logs ---------------------------------------------------------

AFTER_2026 = riyadh(2027, 1, 15, 12)


def test_year_window_uses_riyadh_boundaries():
    logs = wrapped.prepare_logs([
        row(id=1, logged_at=utc(2025, 12, 31, 20, 59)),            # 23:59 Dec 31 Riyadh → 2025
        row(id=2, logged_at=utc(2025, 12, 31, 21, 0)),             # 00:00 Jan 1 Riyadh → 2026
        row(id=3, logged_at=utc(2026, 12, 31, 20, 59, 59, 500000)),  # 23:59:59.5 Dec 31 Riyadh → 2026
        row(id=4, logged_at=utc(2026, 12, 31, 21, 0)),             # 00:00 Jan 1 Riyadh → 2027
    ])
    assert wrapped.select_year_logs(logs, 2026, AFTER_2026)["id"].tolist() == [2, 3]


def test_partial_year_window_ends_now():
    # NOW is 2026-10-21 12:00 Riyadh
    start, end = wrapped.year_window(2026, NOW)
    assert start == riyadh(2026, 1, 1)
    assert end == NOW


def test_partial_year_excludes_logs_after_now():
    logs = wrapped.prepare_logs([
        row(id=1, logged_at=utc(2026, 10, 21, 8, 59)),  # 11:59 Riyadh, before NOW
        row(id=2, logged_at=utc(2026, 10, 21, 9, 1)),   # 12:01 Riyadh, after NOW
        row(id=3, logged_at=utc(2026, 11, 5, 12)),
    ])
    assert wrapped.select_year_logs(logs, 2026, NOW)["id"].tolist() == [1]


def test_past_year_window_ends_dec_31():
    _, end = wrapped.year_window(2025, NOW)
    assert end == riyadh(2025, 12, 31, 23, 59, 59, 999999)


def test_dec_31_window_ends_now():
    dec_31 = riyadh(2026, 12, 31, 18)
    _, end = wrapped.year_window(2026, dec_31)
    assert end == dec_31
    logs = wrapped.prepare_logs([
        row(id=1, logged_at=utc(2026, 12, 31, 14)),  # 17:00 Riyadh
        row(id=2, logged_at=utc(2026, 12, 31, 16)),  # 19:00 Riyadh, after now
    ])
    assert wrapped.select_year_logs(logs, 2026, dec_31)["id"].tolist() == [1]


def test_year_logs_exclude_plan_to_play():
    logs = wrapped.prepare_logs([
        row(id=1, status="playing"),
        row(id=2, status="completed"),
        row(id=3, status="paused"),
        row(id=4, status="plan_to_play"),
    ])
    assert wrapped.select_year_logs(logs, 2026, NOW)["id"].tolist() == [1, 2, 3]


def test_year_logs_keep_zero_and_null_hour_rows():
    logs = wrapped.prepare_logs([row(id=1, hours=None), row(id=2, hours=Decimal("0"))])
    assert len(wrapped.select_year_logs(logs, 2026, NOW)) == 2


# --- build_wrapped ------------------------------------------------------------

UNLOCKED_KEYS = [
    "year", "locked", "release_date", "is_partial", "empty_state", "window",
    "total_hours", "games_played", "games_played_covers", "top_games", "top_online_game",
    "trophies_earned", "trophies", "play_style", "replay", "rating", "friends_hours",
    "similar_friend", "me",
]


def test_empty_year_returns_empty_state():
    year_logs = wrapped.select_year_logs(wrapped.prepare_logs([]), 2025, NOW)
    response = wrapped.build_wrapped(2025, FULL, year_logs, NOW, game_lookup=fake_lookup)
    assert list(response) == UNLOCKED_KEYS
    assert response == {
        "year": 2025,
        "locked": False,
        "release_date": "2025-12-31",
        "is_partial": False,
        "empty_state": True,
        "window": {"start": "2025-01-01", "end": "2025-12-31"},
        "total_hours": None,
        "games_played": 0,
        "games_played_covers": [],
        "top_games": None,
        "top_online_game": None,
        "trophies_earned": None,
        "trophies": None,
        "play_style": None,
        "replay": None,
        "rating": None,
        "friends_hours": None,
        "similar_friend": None,
        "me": None,
    }


def test_unlocked_year_with_logs_has_every_key():
    year_logs = wrapped.select_year_logs(wrapped.prepare_logs([row()]), 2026, NOW)
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs, NOW, game_lookup=fake_lookup)
    assert list(response) == UNLOCKED_KEYS
    assert response["locked"] is False
    assert response["release_date"] == "2026-12-31"
    assert response["is_partial"] is True
    assert response["empty_state"] is False
    # Partial year: window ends today in Riyadh
    assert response["window"] == {"start": "2026-01-01", "end": "2026-10-21"}


def test_past_year_response_window_ends_dec_31():
    year_logs = wrapped.select_year_logs(wrapped.prepare_logs([]), 2025, NOW)
    assert wrapped.build_wrapped(2025, FULL, year_logs, NOW, game_lookup=fake_lookup)["window"] == {
        "start": "2025-01-01",
        "end": "2025-12-31",
    }


def test_dec_31_response_window_ends_today():
    dec_31 = riyadh(2026, 12, 31, 18)
    year_logs = wrapped.select_year_logs(wrapped.prepare_logs([row()]), 2026, dec_31)
    response = wrapped.build_wrapped(2026, FULL, year_logs, dec_31, game_lookup=fake_lookup)
    assert response["window"] == {"start": "2026-01-01", "end": "2026-12-31"}
    assert response["is_partial"] is False


# --- Block C: game_hours ------------------------------------------------------

def year_logs_for(rows, year=2026, now=NOW):
    return wrapped.select_year_logs(wrapped.prepare_logs(rows), year, now)


def test_game_hours_sums_every_log_of_a_game():
    per_game = wrapped.game_hours(year_logs_for([
        row(id=1, game_id=1, hours=Decimal("2.5")),
        row(id=2, game_id=1, hours=Decimal("4")),
        row(id=3, game_id=2, hours=Decimal("1.5")),
    ]))
    assert per_game.to_dict() == {1: 6.5, 2: 1.5}


def test_game_hours_counts_null_as_zero():
    per_game = wrapped.game_hours(year_logs_for([
        row(id=1, game_id=1, hours=None),
        row(id=2, game_id=1, hours=Decimal("3")),
        row(id=3, game_id=2, hours=None),
    ]))
    assert per_game.to_dict() == {1: 3.0, 2: 0.0}


def test_game_hours_handles_no_logs():
    per_game = wrapped.game_hours(year_logs_for([]))
    assert per_game.empty
    assert per_game.dtype == "float64"


# --- Card 1: total_hours ------------------------------------------------------

def total_hours_for(rows, now=NOW):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=fake_lookup)["total_hours"]


def test_total_hours_normal_data():
    assert total_hours_for([
        row(id=1, game_id=1, hours=Decimal("120.5")),
        row(id=2, game_id=2, hours=Decimal("94")),
    ]) == 214.5


def test_total_hours_ignores_null_hours():
    assert total_hours_for([
        row(id=1, game_id=1, hours=None),
        row(id=2, game_id=2, hours=Decimal("7.5")),
    ]) == 7.5


def test_total_hours_all_null_is_none():
    assert total_hours_for([
        row(id=1, game_id=1, hours=None),
        row(id=2, game_id=2, hours=None),
    ]) is None


def test_total_hours_sums_logs_of_the_same_game():
    assert total_hours_for([
        row(id=1, game_id=1, hours=Decimal("10")),
        row(id=2, game_id=1, hours=Decimal("5.5")),
        row(id=3, game_id=1, hours=Decimal("2")),
    ]) == 17.5


def test_total_hours_excludes_logs_outside_the_year():
    assert total_hours_for([
        row(id=1, hours=Decimal("5"), logged_at=utc(2026, 6, 1, 12)),
        row(id=2, hours=Decimal("100"), logged_at=utc(2025, 12, 31, 20, 59)),  # 2025 in Riyadh
        row(id=3, hours=Decimal("200"), logged_at=utc(2026, 10, 21, 9, 1)),    # after NOW
    ]) == 5.0


def test_total_hours_excludes_plan_to_play():
    assert total_hours_for([
        row(id=1, hours=Decimal("5"), status="playing"),
        row(id=2, hours=Decimal("50"), status="plan_to_play"),
    ]) == 5.0


def test_total_hours_rounds_to_one_decimal():
    assert total_hours_for([
        row(id=1, game_id=1, hours=Decimal("0.04")),
        row(id=2, game_id=2, hours=Decimal("0.04")),
    ]) == 0.1
    assert total_hours_for([row(id=1, hours=Decimal("12.345"))]) == 12.3


def test_total_hours_rounding_to_zero_is_none():
    assert total_hours_for([row(id=1, hours=Decimal("0.04"))]) is None


# --- Card 2: games_played -----------------------------------------------------

def games_played_for(rows, now=NOW):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=fake_lookup)["games_played"]


def test_games_played_counts_a_game_once_across_logs():
    assert games_played_for([
        row(id=1, game_id=1),
        row(id=2, game_id=1),
        row(id=3, game_id=1),
        row(id=4, game_id=2),
    ]) == 2


def test_games_played_counts_null_and_zero_hour_games():
    assert games_played_for([
        row(id=1, game_id=1, hours=None),
        row(id=2, game_id=2, hours=Decimal("0")),
        row(id=3, game_id=3, hours=Decimal("4")),
    ]) == 3


def test_games_played_ignores_plan_to_play():
    assert games_played_for([
        row(id=1, game_id=1, status="completed"),
        row(id=2, game_id=2, status="plan_to_play"),
    ]) == 1


def test_games_played_ignores_logs_outside_the_year():
    assert games_played_for([
        row(id=1, game_id=1, logged_at=utc(2026, 6, 1, 12)),
        row(id=2, game_id=2, logged_at=utc(2025, 12, 31, 20, 59)),  # 2025 in Riyadh
        row(id=3, game_id=3, logged_at=utc(2026, 10, 21, 9, 1)),    # after NOW
    ]) == 1


def test_games_played_zero_logs_is_empty_state_with_zero():
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs_for([]), NOW, game_lookup=fake_lookup)
    assert response["empty_state"] is True
    assert response["games_played"] == 0


def covers_for(rows, now=NOW):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=fake_lookup)["games_played_covers"]


def test_games_played_covers_one_per_game_most_hours_first():
    assert covers_for([
        row(id=1, game_id=1, hours=Decimal("2"), cover_image="a.jpg"),
        row(id=2, game_id=2, hours=Decimal("5"), cover_image="b.jpg"),
        row(id=3, game_id=1, hours=Decimal("1"), cover_image="a.jpg"),
    ]) == ["b.jpg", "a.jpg"]


def test_games_played_covers_ties_go_to_the_most_recent_log():
    assert covers_for([
        row(id=1, game_id=1, logged_at=utc(2026, 3, 1), cover_image="old.jpg"),
        row(id=2, game_id=2, logged_at=utc(2026, 5, 1), cover_image="new.jpg"),
    ]) == ["new.jpg", "old.jpg"]


def test_games_played_covers_fall_back_to_background_and_skip_missing():
    assert covers_for([
        row(id=1, game_id=1, cover_image=None, background_image="bg.jpg"),
        row(id=2, game_id=2, cover_image="  ", background_image=None),
    ]) == ["bg.jpg"]


def test_games_played_covers_stop_at_the_limit():
    rows = [row(id=i, game_id=i, cover_image=f"{i}.jpg") for i in range(1, 20)]
    assert len(covers_for(rows)) == wrapped.GAMES_PLAYED_COVERS_LIMIT


def test_games_played_covers_empty_year_is_empty_list():
    assert covers_for([]) == []


# --- Card 3: top_games --------------------------------------------------------

def top_games_for(rows, now=NOW, lookup=fake_lookup):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=lookup)["top_games"]


def top_ids(rows, **kwargs):
    return [g["game_id"] for g in top_games_for(rows, **kwargs)]


def test_top_games_clean_top_three():
    top = top_games_for([
        row(id=1, game_id=1, hours=Decimal("10")),
        row(id=2, game_id=2, hours=Decimal("40")),
        row(id=3, game_id=3, hours=Decimal("25")),
        row(id=4, game_id=4, hours=Decimal("5")),
    ])
    assert top == [
        {"game_id": 2, "name": "Game 2", "cover_image": "cover-2.jpg", "hours": 40.0},
        {"game_id": 3, "name": "Game 3", "cover_image": "cover-3.jpg", "hours": 25.0},
        {"game_id": 1, "name": "Game 1", "cover_image": "cover-1.jpg", "hours": 10.0},
    ]
    assert all(list(item) == ["game_id", "name", "cover_image", "hours"] for item in top)


def test_top_games_hours_summed_across_logs():
    # game 1: 3 logs adding to 30 beats game 2's single 20-hour log
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("10")),
        row(id=2, game_id=1, hours=Decimal("10")),
        row(id=3, game_id=1, hours=Decimal("10")),
        row(id=4, game_id=2, hours=Decimal("20")),
    ]) == [1, 2]


def test_top_games_tie_broken_by_log_count():
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("10")),
        row(id=2, game_id=2, hours=Decimal("6")),
        row(id=3, game_id=2, hours=Decimal("4")),
    ]) == [2, 1]


def test_top_games_tie_broken_by_latest_logged_at():
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("10"), logged_at=utc(2026, 3, 1, 12)),
        row(id=2, game_id=2, hours=Decimal("10"), logged_at=utc(2026, 8, 1, 12)),
    ]) == [2, 1]


def test_top_games_tie_broken_by_name():
    logged_at = utc(2026, 5, 1, 12)
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("10"), logged_at=logged_at, name="zelda"),
        row(id=2, game_id=2, hours=Decimal("10"), logged_at=logged_at, name="Hades"),
        row(id=3, game_id=3, hours=Decimal("10"), logged_at=logged_at, name="celeste"),
    ]) == [3, 2, 1]


def test_top_games_float_noise_is_a_tie():
    # 0.1 + 0.2 != 0.3 in floats; both show as 0.3, so the log count decides
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("0.3")),
        row(id=2, game_id=2, hours=Decimal("0.1")),
        row(id=3, game_id=2, hours=Decimal("0.2")),
    ]) == [2, 1]


def test_top_games_fewer_than_three():
    assert top_ids([row(id=1, game_id=1, hours=Decimal("3"))]) == [1]
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("3")),
        row(id=2, game_id=2, hours=Decimal("8")),
    ]) == [2, 1]


def test_top_games_all_null_hours_is_none():
    calls = []
    top = top_games_for(
        [row(id=1, game_id=1, hours=None), row(id=2, game_id=2, hours=None)],
        lookup=lambda ids: calls.append(ids) or {},
    )
    assert top is None
    assert calls == []  # no lookup when nothing qualifies


def test_top_games_excludes_zero_hour_game_with_many_logs():
    assert top_ids([
        row(id=1, game_id=1, hours=Decimal("0")),
        row(id=2, game_id=1, hours=None),
        row(id=3, game_id=1, hours=Decimal("0")),
        row(id=4, game_id=1, hours=None),
        row(id=5, game_id=2, hours=Decimal("1")),
    ]) == [2]


def test_top_games_cover_falls_back_to_background_image():
    def lookup(game_ids):
        return {
            1: {"id": 1, "name": "Game 1", "cover_image": None, "background_image": "bg-1.jpg"},
            2: {"id": 2, "name": "Game 2", "cover_image": "cover-2.jpg", "background_image": "bg-2.jpg"},
            3: {"id": 3, "name": "Game 3", "cover_image": None, "background_image": None},
        }
    top = top_games_for([
        row(id=1, game_id=1, hours=Decimal("30")),
        row(id=2, game_id=2, hours=Decimal("20")),
        row(id=3, game_id=3, hours=Decimal("10")),
    ], lookup=lookup)
    assert [g["cover_image"] for g in top] == ["bg-1.jpg", "cover-2.jpg", None]


def test_top_games_hours_rounded_to_one_decimal():
    top = top_games_for([
        row(id=1, game_id=1, hours=Decimal("12.345")),
        row(id=2, game_id=1, hours=Decimal("0.04")),
    ])
    assert top[0]["hours"] == 12.4


def test_top_games_lookup_called_once_with_selected_ids_only():
    calls = []

    def lookup(game_ids):
        calls.append(sorted(game_ids))
        return fake_lookup(game_ids)

    top_games_for([
        row(id=i, game_id=i, hours=Decimal(str(i))) for i in range(1, 6)
    ], lookup=lookup)
    assert calls == [[3, 4, 5]]


def test_top_games_empty_state_is_none():
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs_for([]), NOW, game_lookup=fake_lookup)
    assert response["top_games"] is None


# --- Card 4: top_online_game --------------------------------------------------

MP = ["Single player", "Multiplayer"]


def online_for(rows, now=NOW, lookup=fake_lookup):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=lookup)["top_online_game"]


@pytest.mark.parametrize("raw, expected", [
    (None, ()),
    ([], ()),
    (["Single player", "Multiplayer"], ("Single player", "Multiplayer")),
    ('["Battle Royale", "Co-operative"]', ("Battle Royale", "Co-operative")),
    ('{"Single player",Multiplayer}', ("Single player", "Multiplayer")),
    ("Single player, Split screen", ("Single player", "Split screen")),
    ("", ()),
])
def test_parse_game_modes_accepts_every_shape(raw, expected):
    assert wrapped.parse_game_modes(raw) == expected


@pytest.mark.parametrize("modes, expected", [
    (("Multiplayer",), True),
    (("Massively Multiplayer Online (MMO)",), True),
    (("BATTLE ROYALE",), True),
    (("Co-operative",), True),
    (("Single player", "Split screen"), False),
    ((), False),
])
def test_is_online(modes, expected):
    assert wrapped.is_online(modes) is expected


def test_top_online_game_picks_most_hours_among_online_only():
    online = online_for([
        row(id=1, game_id=1, hours=Decimal("50"), game_modes=["Single player"]),
        row(id=2, game_id=2, hours=Decimal("20"), game_modes=MP),
        row(id=3, game_id=3, hours=Decimal("30"), game_modes=["Battle Royale"]),
    ])
    assert online == {"game_id": 3, "name": "Game 3", "cover_image": "cover-3.jpg", "hours": 30.0}


def test_top_online_game_sums_hours_across_logs():
    assert online_for([
        row(id=1, game_id=1, hours=Decimal("10"), game_modes=MP),
        row(id=2, game_id=1, hours=Decimal("10"), game_modes=MP),
        row(id=3, game_id=2, hours=Decimal("15"), game_modes=MP),
    ])["game_id"] == 1


def test_top_online_game_ties_use_log_count():
    assert online_for([
        row(id=1, game_id=1, hours=Decimal("10"), game_modes=MP),
        row(id=2, game_id=2, hours=Decimal("6"), game_modes=MP),
        row(id=3, game_id=2, hours=Decimal("4"), game_modes=MP),
    ])["game_id"] == 2


def test_top_online_game_none_without_online_games():
    assert online_for([row(id=1, game_id=1, game_modes=["Single player"])]) is None
    assert online_for([row(id=1, game_id=1, game_modes=None)]) is None


def test_top_online_game_none_when_online_game_has_no_hours():
    assert online_for([
        row(id=1, game_id=1, hours=None, game_modes=MP),
        row(id=2, game_id=2, hours=Decimal("5"), game_modes=["Single player"]),
    ]) is None


def test_top_online_game_shares_the_single_lookup_with_top_games():
    calls = []

    def lookup(game_ids):
        calls.append(sorted(game_ids))
        return fake_lookup(game_ids)

    online_for([
        row(id=i, game_id=i, hours=Decimal(str(i + 10)), game_modes=["Single player"]) for i in range(1, 5)
    ] + [row(id=9, game_id=9, hours=Decimal("1"), game_modes=MP)], lookup=lookup)
    assert calls == [[2, 3, 4, 9]]


# --- Card 5: trophies_earned + trophies ---------------------------------------

def tick(name, logged_at, game_id=1, game_name="Hades", achievement_id=None, icon_url=None):
    """One achievement ticked on one log, shaped like load_trophy_unlocks."""
    return {"game_id": game_id, "name": name, "logged_at": logged_at, "game_name": game_name,
            "achievement_id": achievement_id, "icon_url": icon_url}


def trophy_response(ticks, now=NOW):
    return wrapped.build_wrapped(
        2026, PARTIAL, year_logs_for([row()], now=now), now,
        game_lookup=fake_lookup, trophy_lookup=lambda: ticks,
    )


def trophies_for(ticks, now=NOW):
    return trophy_response(ticks, now)["trophies_earned"]


def test_trophies_counts_ticks_on_logs_in_window():
    assert trophies_for([
        tick("a", utc(2026, 2, 1)),
        tick("b", utc(2026, 9, 1)),
        tick("c", utc(2025, 6, 1)),          # last year's log
        tick("d", utc(2026, 10, 21, 10)),    # log after NOW
    ]) == 2


def test_trophies_same_achievement_on_two_logs_counts_once():
    assert trophies_for([tick("a", utc(2026, 2, 1)), tick("a", utc(2026, 5, 1))]) == 1


def test_trophies_first_ticked_last_year_not_counted_again():
    assert trophies_for([tick("a", utc(2025, 11, 1)), tick("a", utc(2026, 5, 1))]) is None


def test_trophies_same_name_in_two_games_counts_twice():
    assert trophies_for([
        tick("Completionist", utc(2026, 2, 1), game_id=1),
        tick("Completionist", utc(2026, 3, 1), game_id=2),
    ]) == 2


def test_trophies_log_without_a_date_is_skipped():
    assert trophies_for([tick("a", utc(2026, 3, 1)), tick("b", None)]) == 1


def test_trophies_uses_riyadh_year_boundary():
    # 21:30 UTC Dec 31 2025 is 00:30 Jan 1 2026 in Riyadh
    assert trophies_for([tick("a", utc(2025, 12, 31, 21, 30))]) == 1


def test_trophies_list_is_newest_first_dated_by_first_log():
    response = trophy_response([
        tick("Old", utc(2026, 2, 1), achievement_id=7, icon_url="https://icon/7"),
        tick("New", utc(2026, 9, 1), game_id=2, game_name="Portal"),
        tick("Old", utc(2026, 8, 1), achievement_id=7, icon_url="https://icon/7"),  # replay: ignored
    ])
    assert response["trophies_earned"] == 2
    assert response["trophies"] == [
        {"achievement_id": None, "name": "New", "icon_url": None, "game_name": "Portal",
         "unlocked_at": "2026-09-01T03:00:00+03:00"},
        {"achievement_id": 7, "name": "Old", "icon_url": "https://icon/7", "game_name": "Hades",
         "unlocked_at": "2026-02-01T03:00:00+03:00"},
    ]


def test_trophies_zero_is_none():
    response = trophy_response([])
    assert response["trophies_earned"] is None and response["trophies"] is None


def test_trophies_none_without_lookup():
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs_for([row()]), NOW, game_lookup=fake_lookup)
    assert response["trophies_earned"] is None and response["trophies"] is None


def test_trophies_lookup_not_called_in_empty_state():
    calls = []
    wrapped.build_wrapped(2026, PARTIAL, year_logs_for([]), NOW,
                          game_lookup=fake_lookup, trophy_lookup=lambda: calls.append(1) or [])
    assert calls == []


# --- Block D & Card 6: play_style ---------------------------------------------

def play_style_for(rows, now=NOW):
    return wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows, now=now), now, game_lookup=fake_lookup)["play_style"]


def games_with(finished=0, paused=0, playing=0):
    """One log per game, ids 1..n, in the given groups."""
    statuses = ["completed"] * finished + ["paused"] * paused + ["playing"] * playing
    return [row(id=i, game_id=i, status=s) for i, s in enumerate(statuses, start=1)]


def test_latest_log_per_game_newest_then_higher_id():
    logs = year_logs_for([
        row(id=1, game_id=1, status="playing", logged_at=utc(2026, 3, 1)),
        row(id=2, game_id=1, status="paused", logged_at=utc(2026, 5, 1)),
        row(id=3, game_id=2, status="paused", logged_at=utc(2026, 5, 1)),
        row(id=4, game_id=2, status="playing", logged_at=utc(2026, 5, 1)),  # same time, higher id wins
    ])
    latest = wrapped.latest_log_per_game(logs)
    assert latest.loc[1, "status"] == "paused"
    assert latest.loc[2, "status"] == "playing"


def test_play_style_completed_then_replayed_counts_as_finished():
    # Spec example: completed in March, replay logged as playing later
    style = play_style_for([
        row(id=1, game_id=1, status="completed", logged_at=utc(2026, 3, 1)),
        row(id=2, game_id=1, status="playing", logged_at=utc(2026, 9, 1)),
        row(id=3, game_id=2, status="playing"),
        row(id=4, game_id=3, status="playing"),
    ])
    assert (style["finished"], style["paused"], style["playing"]) == (1, 0, 2)


def test_play_style_paused_uses_latest_log_only():
    groups = wrapped.play_style_groups(year_logs_for([
        row(id=1, game_id=1, status="paused", logged_at=utc(2026, 3, 1)),
        row(id=2, game_id=1, status="playing", logged_at=utc(2026, 4, 1)),  # resumed → playing
        row(id=3, game_id=2, status="playing", logged_at=utc(2026, 3, 1)),
        row(id=4, game_id=2, status="paused", logged_at=utc(2026, 4, 1)),   # paused last → paused
        row(id=5, game_id=3, status="completed"),
    ]))
    assert groups.to_dict() == {1: "playing", 2: "paused", 3: "finished"}


def test_play_style_counts_add_up_to_games_played():
    rows = games_with(finished=7, paused=3, playing=8) + [row(id=99, game_id=1, status="completed")]
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs_for(rows), NOW, game_lookup=fake_lookup)
    style = response["play_style"]
    assert style["finished"] + style["paused"] + style["playing"] == response["games_played"] == 18


def test_play_style_spec_example_juggler():
    assert play_style_for(games_with(finished=7, paused=3, playing=8)) == {
        "personality": "the_juggler", "finished": 7, "paused": 3, "playing": 8,
    }


def test_play_style_spec_example_tie_skipped():
    assert play_style_for(games_with(finished=6, paused=3, playing=6)) is None


@pytest.mark.parametrize("groups, personality", [
    ({"finished": 3}, "credits_chaser"),
    ({"paused": 1, "playing": 2}, "forever_in_progress"),
    ({"paused": 3}, "forever_in_progress"),
    ({"finished": 3, "paused": 1, "playing": 1}, "the_closer"),
    ({"finished": 1, "paused": 3, "playing": 1}, "save_and_quit"),
    ({"finished": 4, "paused": 3, "playing": 3}, "the_closer"),  # exactly 40%
    ({"finished": 5, "paused": 4, "playing": 4}, None),          # strictly biggest but 38%
    ({"finished": 2, "paused": 2, "playing": 1}, None),          # tie at the top
])
def test_play_style_personality(groups, personality):
    style = play_style_for(games_with(**groups))
    assert (style and style["personality"]) == personality


def test_play_style_fewer_than_three_games_skipped():
    assert play_style_for(games_with(finished=2)) is None
    # many play-throughs of 2 games are still 2 games
    assert play_style_for([row(id=i, game_id=1 + i % 2) for i in range(6)]) is None


def test_play_style_empty_state_is_none():
    assert play_style_for([]) is None
