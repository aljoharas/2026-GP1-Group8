"""
Tests for serving archetypes: model loading, softmax scores, the
whole-number percentages, reasons, and the /archetype response shape.
Uses the real frozen model with a test temperature; no database.

Run from recommender/:  pytest
"""

import json
import math

import numpy as np
import pytest

import archetypes
from archetype_features import FEATURE_NAMES

TEST_TEMPERATURE = 1.0


@pytest.fixture(scope="module")
def model(tmp_path_factory):
    data = json.loads(archetypes.MODEL_PATH.read_text())
    data["scoring"] = {"temperature": TEST_TEMPERATURE}
    path = tmp_path_factory.mktemp("model") / "model.json"
    path.write_text(json.dumps(data))
    return archetypes.load_model(path)


def game(hours, completed=False, genres=("Action",), online=False, month="2026-01", name=None,
         unlocked=0, available=0):
    return {
        "game_id": 0, "name": name or f"Game {hours}", "hours": float(hours), "completed": completed,
        "latest_status": "completed" if completed else "playing", "trophies_unlocked": unlocked,
        "trophies_available": available, "genres": list(genres), "is_online": online, "months": [month],
    }


# --- largest_remainder --------------------------------------------------------

def test_percentages_always_add_up_to_100():
    rng = np.random.default_rng(0)
    for _ in range(5000):
        k = int(rng.integers(2, 9))
        p = rng.dirichlet(np.full(k, rng.choice([0.05, 0.5, 1.0, 5.0])))
        percents = archetypes.largest_remainder(p)
        assert sum(percents) == 100
        assert all(isinstance(x, int) and 0 <= x <= 100 for x in percents)


def test_percentages_add_up_with_exact_ties():
    assert sum(archetypes.largest_remainder([1 / 3] * 3)) == 100
    assert sum(archetypes.largest_remainder([1 / 6] * 6)) == 100
    assert archetypes.largest_remainder([1 / 3] * 3) == [34, 33, 33]


def test_higher_probability_never_gets_a_lower_percentage():
    rng = np.random.default_rng(1)
    for _ in range(2000):
        p = rng.dirichlet(np.ones(6))
        percents = archetypes.largest_remainder(p)
        for i in range(6):
            for j in range(6):
                if p[i] > p[j]:
                    assert percents[i] >= percents[j]


def test_largest_remainder_hand_example():
    # 46.7 / 33.3 / 20.0 → floors 46/33/20 = 99; the biggest remainder (.7) gets the point
    assert archetypes.largest_remainder([0.467, 0.333, 0.200]) == [47, 33, 20]


# --- softmax -------------------------------------------------------------------

def test_nearest_centre_gets_the_highest_probability():
    centres = np.array([[0.0, 0.0], [3.0, 0.0], [0.0, 4.0]])
    p = archetypes.match_probabilities(np.array([0.5, 0.0]), centres, 1.0)
    assert p.argmax() == 0 and p.sum() == pytest.approx(1.0)
    # distances 0.5, 2.5, 4.03 → weights e^0, e^-2, e^-3.53
    w = np.exp(-np.array([0.5, 2.5, math.hypot(0.5, 4.0)]))
    assert p == pytest.approx(w / w.sum())


def test_lower_temperature_is_more_confident():
    centres = np.array([[0.0, 0.0], [2.0, 0.0]])
    z = np.array([0.5, 0.0])
    assert archetypes.match_probabilities(z, centres, 0.5)[0] > archetypes.match_probabilities(z, centres, 2.0)[0]


def test_huge_distances_do_not_overflow():
    p = archetypes.match_probabilities(np.array([1e4, 0.0]), np.array([[0.0, 0.0], [1e4, 1.0]]), 0.1)
    assert np.isfinite(p).all() and p.argmax() == 1


# --- load_model ------------------------------------------------------------------

def test_model_without_a_temperature_is_refused(tmp_path):
    data = json.loads(archetypes.MODEL_PATH.read_text())
    data.pop("scoring", None)
    path = tmp_path / "m.json"
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="temperature"):
        archetypes.load_model(path)


def test_model_with_other_features_is_refused(tmp_path):
    data = json.loads(archetypes.MODEL_PATH.read_text())
    data["scoring"] = {"temperature": 1.0}
    data["features"] = list(reversed(data["features"]))
    path = tmp_path / "m.json"
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="features"):
        archetypes.load_model(path)


# --- response ----------------------------------------------------------------------

def test_fewer_than_five_games_is_not_enough(model):
    body = archetypes.archetype_response([game(5) for _ in range(4)], model)
    assert body == {
        "archetype": None, "reason": "not_enough_games", "games_played": 4,
        "min_games": 5, "model_version": model["version"],
    }


def devotee_games():
    # One offline game holds almost all the hours
    return [game(400, name="Elden Ring", month="2026-01")] + [
        game(2, genres=("Action",), month=f"2026-0{m}") for m in range(2, 6)
    ]


def test_response_shape(model):
    body = archetypes.archetype_response(devotee_games(), model)
    assert set(body) == {"archetype", "description", "scores", "reasons", "games_played", "model_version"}
    names = [c["name"] for c in model["clusters"]]
    assert sorted(s["archetype"] for s in body["scores"]) == sorted(names)
    assert sum(s["percent"] for s in body["scores"]) == 100
    percents = [s["percent"] for s in body["scores"]]
    assert percents == sorted(percents, reverse=True)
    assert body["archetype"] == body["scores"][0]["archetype"]
    assert body["description"] == body["scores"][0]["description"]
    assert body["games_played"] == 5
    assert len(body["reasons"]) == 2


def test_one_dominant_offline_game_is_a_devotee(model):
    body = archetypes.archetype_response(devotee_games(), model)
    assert body["archetype"] == "Devotee"
    assert "98% of your hours go to Elden Ring" in body["reasons"]


def test_reasons_skip_imputed_features(model):
    # No trophy lists and no genres: both are imputed, so never a reason
    games = [game(h, genres=(), available=0) for h in (30, 25, 40, 20, 35)]
    body = archetypes.archetype_response(games, model)
    assert not any("trophies" in r.lower() or "genre" in r.lower() for r in body["reasons"])


@pytest.mark.parametrize("feature, above, expected", [
    ("completion_rate", True, "You've finished 2 of your 5 games"),
    ("completion_rate", False, "Only 2 of your 5 games are finished so far"),
    ("genre_diversity", True, "You've played 3 different genres"),
    ("online_share", True, "60% of your hours are in online games"),
    ("online_share", False, "40% of your hours are in offline games"),
    ("log_games_played", True, "You've played 5 games"),
    ("log_games_played", False, "You keep to a small set of 5 games"),
    ("top_game_share", True, "40% of your hours go to Big One"),
    ("trophy_rate", True, "You've unlocked 25% of the trophies in your games"),
])
def test_reason_sentences_use_real_values(feature, above, expected):
    # 5 games, 100 hours: Big One 40h online, 20h online, three 13.33h offline
    games = [
        game(40, completed=True, genres=("RPG",), online=True, name="Big One"),
        game(20, completed=True, genres=("Shooter",), online=True),
        game(40 / 3, genres=("Puzzle",)), game(40 / 3, genres=("Puzzle",)), game(40 / 3, genres=("Puzzle",)),
    ]
    features = {f: None for f in FEATURE_NAMES}
    features.update(trophy_rate=0.25, online_share=0.6, top_game_share=0.4)
    assert archetypes.reason_sentence(feature, above, games, features) == expected


def test_hours_sentences_round_sensibly():
    features = {"log_hours_per_game": math.log1p(4.5), "log_activity": math.log1p(37.4)}
    games = [game(1)] * 5
    assert archetypes.reason_sentence("log_hours_per_game", True, games, features) == \
        "A typical game gets about 4.5 hours from you"
    assert archetypes.reason_sentence("log_activity", True, games, features) == \
        "You average about 37 hours in each month you play"
