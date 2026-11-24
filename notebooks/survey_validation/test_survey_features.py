"""Tests for the survey conversion and scoring helpers (no survey file needed).

    pytest notebooks/survey_validation
"""
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import survey_features as S  # noqa: E402


def test_hour_midpoints_are_geometric():
    assert S.HOURS["2–5"] == pytest.approx(math.sqrt(2 * 5), abs=0.05)
    assert S.HOURS["26–50"] == pytest.approx(math.sqrt(26 * 50), abs=0.1)
    assert S.HOURS["101–200"] == pytest.approx(math.sqrt(101 * 200), abs=0.2)
    assert list(S.HOURS.values()) == sorted(S.HOURS.values())


def test_game_dict_status_and_trophies():
    g = S.game_dict("26–50", "Finished", "51–75%", ["Action"], True, ["m0"])
    assert g["hours"] == 36.0 and g["completed"] and g["latest_status"] == "completed"
    assert g["trophies_unlocked"] / g["trophies_available"] == pytest.approx(0.63)
    assert S.game_dict("2–5", "Paused", "The game has none", [], False, [])["trophies_available"] == 0
    assert S.game_dict("2–5", "Still Playing", "Don’t know", [], False, [])["trophies_available"] == 0
    assert S.game_dict("2–5", "Still Playing", "0%", [], False, [])["trophies_available"] == S.TROPHY_DENOM
    with pytest.raises(ValueError):
        S.game_dict("about 3", "Finished", "0%", [], False, [])


def _entries(rows):
    return pd.DataFrame(rows, columns=["hours", "status", "trophies", "genres", "online"])


ROWS = [
    ("More than 200", "Still Playing", "1–25%", "Action;Shooter", True),
    ("26–50", "Finished", "100%", "Action", False),
    ("6–10", "Finished", "The game has none", "RPG", False),
    ("Less than 2", "Paused", "Don’t know", np.nan, False),      # unmatched
    ("11–25", "Finished", "51–75%", "Puzzle", False),
]


def test_trophy_rate_is_the_unweighted_mean_of_known_shares():
    f = S.features(S.respondent_games(_entries(ROWS), 10))
    assert f["trophy_rate"] == pytest.approx(np.mean([0.13, 1.0, 0.63]))


def test_other_features_follow_compute_features():
    games = S.respondent_games(_entries(ROWS), 10)
    f = S.features(games, games_played="five")
    total = 280 + 36 + 7.7 + 1 + 16.6
    assert f["completion_rate"] == pytest.approx(3 / 5)
    assert f["top_game_share"] == pytest.approx(280 / total)
    assert f["online_share"] == pytest.approx(280 / total), "unmatched counts as offline, as in the app"
    assert f["log_activity"] == pytest.approx(math.log1p(total / 10))
    assert f["log_games_played"] == pytest.approx(math.log(5))
    assert f["genre_diversity"] is not None


def test_games_played_and_activity_treatments():
    games = S.respondent_games(_entries(ROWS), 12)
    main = S.features(games)
    assert main["log_games_played"] is None and main["log_activity"] is not None
    act = S.features(games, activity="mean")
    assert act["log_activity"] is None
    with pytest.raises(ValueError):
        S.features(games, games_played="six")


def test_missing_values_get_the_training_mean_at_scoring():
    model = S.archetypes.load_model()
    f = S.features(S.respondent_games(_entries(ROWS), 12), activity="mean")
    filled = S.fill_missing(f, model)
    i_games = S.FEATURE_NAMES.index("log_games_played")
    i_act = S.FEATURE_NAMES.index("log_activity")
    assert filled["log_games_played"] == pytest.approx(model["_mean"][i_games])
    assert filled["log_activity"] == pytest.approx(model["_mean"][i_act])
    s = S.score(f, model)
    assert sum(p for _, p in s["ranked"]) == 100 and len(s["ranked"]) == 6
    assert s["top1"] == s["ranked"][0][0] and s["top2"] == [n for n, _ in s["ranked"][:2]]


def test_score_matches_the_endpoint_for_complete_features():
    model = S.archetypes.load_model()
    games = S.respondent_games(_entries(ROWS), 12)
    for g in games:
        g["name"] = "x"
    body = S.archetypes.archetype_response(games, model)
    s = S.score(S.features(games, games_played="five"), model)
    assert [(x["archetype"], x["percent"]) for x in body["scores"]] == s["ranked"]
    assert body["blend"] == s["blend"]


def test_self_mapping_covers_the_five_answers():
    assert len(S.SELF) == 5
    assert S.SELF["I sink a lot of hours into a few favourite games."] == {"Devotee", "The Main"}
    assert S.SELF["I mostly play online or multiplayer games."] == {"Competitor", "The Main"}


def test_wilson_interval():
    lo, hi = S.wilson(10, 20)
    assert lo == pytest.approx(0.2993, abs=1e-3) and hi == pytest.approx(0.7007, abs=1e-3)
    assert S.wilson(0, 20)[0] == 0.0 and S.wilson(20, 20)[1] == 1.0


def test_permutation_test_on_perfect_and_random_agreement():
    labels = [frozenset({x}) for x in "ABCDEFGHIJ" * 2]
    perfect = [{next(iter(s))} for s in labels]
    res = S.permutation_test(perfect, labels, n=2000)
    assert res["observed"] == 20 and res["p_value"] < 0.01
    assert res["chance_mean"] == pytest.approx(2 / 20, abs=0.02)
    none_ = [{"Z"} for _ in labels]
    assert S.permutation_test(none_, labels, n=500)["p_value"] == pytest.approx(1.0)
