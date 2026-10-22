"""
Unit tests for Wrapped cards 7-9: average rating and rater type, hours
compared with friends, and most similar friend. No database: rows are built in
the shape psycopg2's RealDictCursor returns (Decimal numbers, UTC timestamps).

Run from recommender/:  pytest
"""

from datetime import datetime, timezone
from decimal import Decimal

import pandas as pd
import pytest

import wrapped
from wrapped import FULL, PARTIAL, WRAPPED_TZ

NOW = datetime(2026, 10, 21, 12, tzinfo=WRAPPED_TZ)
ME = {"user_id": "me", "username": "ghada", "avatar_url": "me.png"}


def utc(*args):
    return datetime(*args, tzinfo=timezone.utc)


_next_id = iter(range(1, 100_000))


def row(game_id=1, hours=Decimal("2"), logged_at=None, status="playing",
        user_rating=None, rawg_rating=None, **extra):
    return {
        "id": extra.get("id", next(_next_id)),
        "game_id": game_id,
        "status": status,
        "hours_played": hours,
        "logged_at": logged_at or utc(2026, 6, 1, 12),
        "name": extra.get("name", f"Game {game_id}"),
        "game_modes": extra.get("game_modes"),
        "user_rating": None if user_rating is None else Decimal(str(user_rating)),
        "rawg_rating": None if rawg_rating is None else Decimal(str(rawg_rating)),
    }


def year_logs_for(rows, year=2026, now=NOW):
    return wrapped.person_year_logs(rows, year, now)


def fake_lookup(game_ids):
    return {gid: {"id": gid, "name": f"Game {gid}", "cover_image": None, "background_image": None}
            for gid in game_ids}


# --- prepare_logs: rating columns ---------------------------------------------

def test_prepare_logs_converts_ratings_and_keeps_null_as_nan():
    df = wrapped.prepare_logs([row(user_rating=8, rawg_rating=4.5), row(game_id=2)])
    assert df["user_rating"].tolist()[0] == 8.0
    assert df["rawg_rating"].tolist()[0] == 4.5
    assert df["user_rating"].isna().tolist() == [False, True]
    assert df["rawg_rating"].isna().tolist() == [False, True]


def test_prepare_logs_without_rating_keys_still_has_rating_columns():
    raw = row()
    del raw["user_rating"], raw["rawg_rating"]
    df = wrapped.prepare_logs([raw])
    assert df["user_rating"].isna().all() and df["rawg_rating"].isna().all()


# --- Card 7: rating -----------------------------------------------------------

def rated(*pairs):
    """(user_rating, rawg_rating) per game → rows, one game each."""
    return [row(game_id=i + 1, user_rating=u, rawg_rating=r) for i, (u, r) in enumerate(pairs)]


def test_rating_none_with_fewer_than_three_rated_games():
    rows = rated((8, 4), (6, 3)) + [row(game_id=9)]  # third game unrated
    assert wrapped.rating_card(year_logs_for(rows)) is None


def test_rating_none_without_any_rating():
    assert wrapped.rating_card(year_logs_for([row(), row(game_id=2), row(game_id=3)])) is None


def test_rating_average_rounded_to_one_decimal():
    card = wrapped.rating_card(year_logs_for(rated((8, None), (7, None), (8, None))))
    assert card["rated_games"] == 3
    assert card["average"] == 7.7  # 23 / 3 = 7.666…


def test_rating_uses_newest_rated_log_per_game():
    rows = [
        row(game_id=1, user_rating=4, logged_at=utc(2026, 2, 1)),
        row(game_id=1, user_rating=10, logged_at=utc(2026, 8, 1)),
        row(game_id=1, logged_at=utc(2026, 9, 1)),  # newer but unrated: ignored
        row(game_id=2, user_rating=6),
        row(game_id=3, user_rating=8),
    ]
    card = wrapped.rating_card(year_logs_for(rows))
    assert card["rated_games"] == 3  # one rating per game
    assert card["average"] == 8.0    # (10 + 6 + 8) / 3


def test_rating_ignores_ratings_outside_the_year():
    rows = rated((8, None), (8, None)) + [row(game_id=3, user_rating=2, logged_at=utc(2025, 5, 1))]
    assert wrapped.rating_card(year_logs_for(rows)) is None


def test_rating_tough_critic():
    # gaps: 3-4.5, 3.5-4.5, 2-3 → -1.5, -1, -1 → -1.17
    card = wrapped.rating_card(year_logs_for(rated((6, 4.5), (7, 4.5), (4, 3))))
    assert card["rater_type"] == wrapped.RATER_TOUGH
    assert card["average_gap"] == -1.2


def test_rating_generous_critic():
    # gaps: 5-3, 4.5-4, 5-4 → 2, 0.5, 1 → 1.17
    card = wrapped.rating_card(year_logs_for(rated((10, 3), (9, 4), (10, 4))))
    assert card["rater_type"] == wrapped.RATER_GENEROUS
    assert card["average_gap"] == 1.2


def test_rating_fair_judge():
    card = wrapped.rating_card(year_logs_for(rated((8, 4), (7, 3.5), (9, 4.5))))
    assert card["rater_type"] == wrapped.RATER_FAIR
    assert card["average_gap"] == 0.0


@pytest.mark.parametrize("pairs, expected", [
    ([(8, 4.5), (8, 4.5), (8, 4.5)], wrapped.RATER_FAIR),       # exactly -0.5
    ([(10, 4.5), (10, 4.5), (10, 4.5)], wrapped.RATER_FAIR),    # exactly +0.5
    ([(8, 4.5), (6, 3.5), (7, 4)], wrapped.RATER_FAIR),         # -0.5 average of -0.5s
    ([(8, 4.6), (8, 4.6), (8, 4.6)], wrapped.RATER_TOUGH),      # just past -0.5
    ([(10, 4.4), (10, 4.4), (10, 4.4)], wrapped.RATER_GENEROUS),
])
def test_rating_boundaries_are_fair_judge(pairs, expected):
    assert wrapped.rating_card(year_logs_for(rated(*pairs)))["rater_type"] == expected


def test_rating_zero_or_null_rawg_left_out_of_gap_but_kept_in_average():
    pairs = [(6, 4.5), (7, 4.5), (4, 3), (10, 0), (10, None)]
    card = wrapped.rating_card(year_logs_for(rated(*pairs)))
    assert card["rated_games"] == 5
    assert card["average"] == 7.4               # all five: 37 / 5
    assert card["rater_type"] == wrapped.RATER_TOUGH  # only the three on RAWG


def test_rating_without_rater_type_when_fewer_than_three_on_rawg():
    card = wrapped.rating_card(year_logs_for(rated((8, 4), (8, 4), (8, 0), (8, None))))
    assert card == {"rated_games": 4, "average": 8.0, "rater_type": None, "average_gap": None}


# --- Card 8: friends_hours ----------------------------------------------------

def friend(uid, hours, name=None):
    return {"user_id": uid, "username": name or uid, "avatar_url": f"{uid}.png", "hours": hours}


def test_friends_hours_spec_example_beat_three_of_five():
    friends = [friend("a", 300), friend("b", 250), friend("c", 100), friend("d", 50), friend("e", 10)]
    card = wrapped.friends_hours_card(ME, 214.5, friends)
    assert card["user_rank"] == 3
    assert card["friends_beaten"] == 3
    assert card["friends_counted"] == 5
    assert [e["user_id"] for e in card["leaderboard"]] == ["a", "b", "me", "c", "d", "e"]


def test_friends_hours_leaderboard_shows_only_public_fields():
    card = wrapped.friends_hours_card(ME, 10, [{**friend("a", 5), "email": "x@y.z", "logs": [1]}])
    assert set(card["leaderboard"][1]) == {"user_id", "username", "avatar_url", "hours", "is_me", "rank"}


def test_friends_hours_none_when_no_friend_has_hours():
    assert wrapped.friends_hours_card(ME, 50, []) is None
    assert wrapped.friends_hours_card(ME, 50, [friend("a", 0), friend("b", 0.04)]) is None


def test_friends_hours_leaves_out_zero_hour_friends():
    card = wrapped.friends_hours_card(ME, 5, [friend("a", 0), friend("b", 3)])
    assert card["friends_counted"] == 1
    assert [e["user_id"] for e in card["leaderboard"]] == ["me", "b"]


def test_friends_hours_user_with_zero_hours_is_still_on_the_board():
    card = wrapped.friends_hours_card(ME, 0, [friend("a", 3)])
    assert card["user_rank"] == 2
    assert card["friends_beaten"] == 0
    assert card["leaderboard"][-1]["is_me"] is True


def test_friends_hours_equal_hours_share_a_rank():
    card = wrapped.friends_hours_card(ME, 20, [friend("a", 30), friend("b", 20), friend("c", 10)])
    ranks = {e["user_id"]: e["rank"] for e in card["leaderboard"]}
    assert ranks == {"a": 1, "me": 2, "b": 2, "c": 4}
    assert card["user_rank"] == 2
    assert card["friends_beaten"] == 1  # a tie is not a win


def test_friends_hours_float_noise_is_a_tie():
    card = wrapped.friends_hours_card(ME, 0.1 + 0.2, [friend("a", 0.3)])
    assert card["user_rank"] == 1 and card["friends_beaten"] == 0
    assert [e["rank"] for e in card["leaderboard"]] == [1, 1]


def test_friends_hours_hours_rounded_to_one_decimal():
    card = wrapped.friends_hours_card(ME, 12.345, [friend("a", 7.25)])
    assert [e["hours"] for e in card["leaderboard"]] == [12.3, 7.2]


# --- Card 9: genre shares and similar friend ----------------------------------

def test_genre_shares_split_hours_equally_between_genres():
    per_game = pd.Series({1: 30.0, 2: 10.0})
    shares, count = wrapped.genre_shares(per_game, {1: ["RPG", "Action", "Adventure"], 2: ["Action"]})
    assert count == 2
    assert shares["RPG"] == pytest.approx(10 / 40)
    assert shares["Action"] == pytest.approx(20 / 40)
    assert shares["Adventure"] == pytest.approx(10 / 40)
    assert sum(shares.values()) == pytest.approx(1)


def test_genre_shares_skip_games_without_genres():
    per_game = pd.Series({1: 10.0, 2: 90.0})
    shares, count = wrapped.genre_shares(per_game, {1: ["RPG"]})
    assert count == 1
    assert shares == {"RPG": pytest.approx(1)}


def test_genre_shares_weight_one_per_game_when_no_hours():
    per_game = pd.Series({1: 0.0, 2: 0.0, 3: 0.0})
    shares, _ = wrapped.genre_shares(per_game, {1: ["RPG"], 2: ["RPG"], 3: ["Action"]})
    assert shares == {"RPG": pytest.approx(2 / 3), "Action": pytest.approx(1 / 3)}


def test_genre_shares_empty():
    assert wrapped.genre_shares(pd.Series(dtype="float64"), {}) == ({}, 0)


def test_cosine_similarity_spec_worked_example():
    me = {"RPG": 0.6, "Action": 0.4}
    other = {"RPG": 0.5, "Action": 0.3, "Shooter": 0.2}
    assert wrapped.cosine_similarity(me, other) == pytest.approx(0.944, abs=0.001)


def similar(uid, shares, hours=10, genre_games=3):
    return {**friend(uid, hours), "shares": shares, "genre_games": genre_games}


MY_SHARES = {"RPG": 0.6, "Action": 0.4}


def test_similar_friend_spec_example():
    card = wrapped.similar_friend_card(
        MY_SHARES, 3, [similar("sara", {"RPG": 0.5, "Action": 0.3, "Shooter": 0.2})],
    )
    assert card == {
        "user_id": "sara", "username": "sara", "avatar_url": "sara.png",
        "match_percent": 94, "shared_genres": ["RPG", "Action"],
    }


def test_similar_friend_picks_the_highest_similarity():
    friends = [similar("far", {"Shooter": 0.7, "RPG": 0.3}), similar("close", {"RPG": 0.6, "Action": 0.4})]
    card = wrapped.similar_friend_card(MY_SHARES, 3, friends)
    assert card["user_id"] == "close" and card["match_percent"] == 100


def test_similar_friend_tie_goes_to_more_hours():
    friends = [similar("less", MY_SHARES, hours=5), similar("more", dict(MY_SHARES), hours=50)]
    assert wrapped.similar_friend_card(MY_SHARES, 3, friends)["user_id"] == "more"


def test_similar_friend_none_when_user_has_fewer_than_three_genre_games():
    assert wrapped.similar_friend_card(MY_SHARES, 2, [similar("a", MY_SHARES)]) is None


def test_similar_friend_skips_friends_with_fewer_than_three_genre_games():
    friends = [similar("few", MY_SHARES, genre_games=2), similar("ok", {"RPG": 0.5, "Action": 0.5})]
    assert wrapped.similar_friend_card(MY_SHARES, 3, friends)["user_id"] == "ok"
    assert wrapped.similar_friend_card(MY_SHARES, 3, friends[:1]) is None


def test_similar_friend_threshold_is_checked_before_rounding():
    # cos = 0.496: rounds to 50% but is below 0.5, so the card is skipped
    x = 0.496
    other = {"RPG": x, "Shooter": (1 - x * x) ** 0.5}
    assert wrapped.cosine_similarity({"RPG": 1.0}, other) == pytest.approx(0.496)
    assert wrapped.similar_friend_card({"RPG": 1.0}, 3, [similar("a", other)]) is None


def test_similar_friend_exactly_half_is_shown():
    other = {"RPG": 0.5, "Shooter": 0.75 ** 0.5}
    card = wrapped.similar_friend_card({"RPG": 1.0}, 3, [similar("a", other)])
    assert card["match_percent"] == 50


def test_similar_friend_shared_genres_ranked_by_smaller_share():
    me = {"RPG": 0.5, "Action": 0.3, "Puzzle": 0.2}
    other = {"RPG": 0.1, "Action": 0.6, "Puzzle": 0.3}
    card = wrapped.similar_friend_card(me, 3, [similar("a", other)])
    # min shares: RPG 0.1, Action 0.3, Puzzle 0.2
    assert card["shared_genres"] == ["Action", "Puzzle"]


# --- build_wrapped wiring -----------------------------------------------------

GENRES = {1: ["RPG"], 2: ["RPG", "Action"], 3: ["Action"], 4: ["Shooter"], 5: ["Puzzle"]}


def friend_with_logs(uid, rows):
    return {"user_id": uid, "username": uid, "avatar_url": None, "logs": rows}


def build(rows, friends, now=NOW, year=2026, access=PARTIAL, genre_calls=None):
    def genre_lookup(ids):
        if genre_calls is not None:
            genre_calls.append(list(ids))
        return {gid: GENRES[gid] for gid in ids if gid in GENRES}

    return wrapped.build_wrapped(
        year, access, year_logs_for(rows, year, now), now,
        game_lookup=fake_lookup, me=ME,
        friends_lookup=lambda: friends, genre_lookup=genre_lookup,
    )


MY_ROWS = [row(game_id=1, hours=Decimal("10")), row(game_id=2, hours=Decimal("10")),
           row(game_id=3, hours=Decimal("5"))]


def test_build_fills_cards_8_and_9_from_friends_logs():
    friends = [
        friend_with_logs("twin", [row(game_id=1, hours=Decimal("8")), row(game_id=2, hours=Decimal("8")),
                                  row(game_id=3, hours=Decimal("4"))]),
        friend_with_logs("other", [row(game_id=4, hours=Decimal("40")), row(game_id=5, hours=Decimal("2")),
                                   row(game_id=4, hours=Decimal("1"))]),
    ]
    response = build(MY_ROWS, friends)
    board = response["friends_hours"]["leaderboard"]
    assert [(e["user_id"], e["hours"]) for e in board] == [("other", 43.0), ("me", 25.0), ("twin", 20.0)]
    assert response["similar_friend"]["user_id"] == "twin"
    assert response["similar_friend"]["match_percent"] == 100


def test_build_friends_use_the_same_partial_window():
    friends = [friend_with_logs("a", [
        row(game_id=1, hours=Decimal("3")),
        row(game_id=1, hours=Decimal("500"), logged_at=utc(2026, 11, 15)),  # after now
        row(game_id=1, hours=Decimal("500"), logged_at=utc(2025, 12, 1)),   # last year
    ])]
    board = build(MY_ROWS, friends)["friends_hours"]["leaderboard"]
    assert [e["hours"] for e in board if not e["is_me"]] == [3.0]


def test_build_genre_lookup_called_once_for_everyone():
    calls = []
    friends = [friend_with_logs("a", [row(game_id=4)]), friend_with_logs("b", [row(game_id=5)])]
    build(MY_ROWS, friends, genre_calls=calls)
    assert calls == [[1, 2, 3, 4, 5]]


def test_build_without_friends_skips_cards_8_and_9_and_genre_lookup():
    calls = []
    response = build(MY_ROWS, [], genre_calls=calls)
    assert response["friends_hours"] is None and response["similar_friend"] is None
    assert calls == []


def test_build_without_lookups_leaves_cards_8_and_9_none():
    response = wrapped.build_wrapped(2026, PARTIAL, year_logs_for(MY_ROWS), NOW, game_lookup=fake_lookup)
    assert response["friends_hours"] is None and response["similar_friend"] is None


def test_build_fills_card_7():
    rows = rated((6, 4.5), (7, 4.5), (4, 3))
    response = wrapped.build_wrapped(2026, FULL, year_logs_for(rows), NOW, game_lookup=fake_lookup)
    assert response["rating"]["rater_type"] == wrapped.RATER_TOUGH


def test_build_empty_year_never_calls_friends_lookup():
    def boom():
        raise AssertionError("friends_lookup should not be called")
    response = wrapped.build_wrapped(
        2026, PARTIAL, year_logs_for([]), NOW, game_lookup=fake_lookup,
        me=ME, friends_lookup=boom, genre_lookup=lambda ids: {},
    )
    assert response["empty_state"] is True
    assert response["rating"] is None and response["friends_hours"] is None
