"""
Checks the frozen model JSON (models/archetype_model.json) still fits the code
that will serve it: same features in the same order, consistent shapes, every
cluster named and described.

Run from recommender/:  pytest
"""

import json
import math
from pathlib import Path

import pytest

from archetype_features import FEATURE_NAMES, IMPUTED_FEATURES, MIN_GAMES

MODEL_PATH = Path(__file__).resolve().parents[3] / "models" / "archetype_model.json"


@pytest.fixture(scope="module")
def model():
    return json.loads(MODEL_PATH.read_text())


def test_features_match_compute_features(model):
    assert model["features"] == FEATURE_NAMES
    assert model["min_games"] == MIN_GAMES
    assert set(model["imputation"]) == set(IMPUTED_FEATURES)


def test_scaler_and_centres_have_one_value_per_feature(model):
    n = len(FEATURE_NAMES)
    assert len(model["scaler"]["mean"]) == n
    assert len(model["scaler"]["scale"]) == n
    assert all(s > 0 for s in model["scaler"]["scale"])
    for cluster in model["clusters"]:
        assert len(cluster["centre_scaled"]) == n
        assert list(cluster["centre"]) == FEATURE_NAMES


def test_every_cluster_is_named_and_described(model):
    clusters = model["clusters"]
    assert len(clusters) == model["k"]
    assert [c["id"] for c in clusters] == list(range(model["k"]))
    names = [c["name"] for c in clusters]
    assert len(set(names)) == len(names)
    assert all(c["description"].strip() for c in clusters)
    assert math.isclose(sum(c["training_share"] for c in clusters), 1.0, abs_tol=1e-3)


def test_centre_in_original_units_matches_the_scaled_centre(model):
    mean, scale = model["scaler"]["mean"], model["scaler"]["scale"]
    for cluster in model["clusters"]:
        for i, feature in enumerate(FEATURE_NAMES):
            assert cluster["centre"][feature] == pytest.approx(cluster["centre_scaled"][i] * scale[i] + mean[i])
