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

import archetypes
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


def test_temperature_is_recorded_and_the_service_accepts_the_model(model):
    assert model["scoring"]["temperature"] == 0.75
    archetypes.load_model(MODEL_PATH)


# --- v2.0.0 and the v1 rollback file ----------------------------------------------

FAMILIES = {"Casual": "Light", "Explorer": "Light", "Competitor": "Committed",
            "Completionist": "Committed", "Devotee": "One-game", "The Main": "One-game"}
V1_PATH = MODEL_PATH.with_name("archetype_model_v1.json")


def test_served_model_is_v2_with_the_confirmed_names_and_families(model):
    assert model["version"] == "2.0.1"
    assert model["k"] == 6
    assert {c["name"]: c["family"] for c in model["clusters"]} == FAMILIES
    completionist = next(c for c in model["clusters"] if c["name"] == "Completionist")
    assert completionist["description"] == \
        "You see more of your games through than most players, and pick up trophies on the way."


def test_v1_rollback_file_is_the_untouched_v1_model():
    v1 = json.loads(V1_PATH.read_text())
    assert v1["version"] == "1.0.0"
    assert v1["k"] == 6 and v1["scoring"]["temperature"] == 0.75
    assert all("family" not in c for c in v1["clusters"])
    archetypes.load_model(V1_PATH)


def test_v1_and_v2_share_names_and_the_unchanged_descriptions(model):
    v1 = {c["name"]: c["description"] for c in json.loads(V1_PATH.read_text())["clusters"]}
    v2 = {c["name"]: c["description"] for c in model["clusters"]}
    assert set(v1) == set(v2)
    assert {n: d for n, d in v1.items() if n != "Completionist"} == {n: d for n, d in v2.items() if n != "Completionist"}


def test_a_model_with_families_on_only_some_clusters_is_refused(model, tmp_path):
    data = json.loads(json.dumps(model))
    data["clusters"][0].pop("family")
    path = tmp_path / "m.json"
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="family"):
        archetypes.load_model(path)


# 2.0.0's scoring fields (features, imputation, scaler, temperature, centres, names, families,
# descriptions), hashed before 2.0.1 added the atypical check
V200_SCORING_SHA256 = "908a6cc09f0b058122260810e77d9e98ff4d67bf3ee2019f6ddeeba58e597af2"


def test_2_0_1_scores_exactly_like_2_0_0(model):
    import hashlib
    core = {k: model[k] for k in ("features", "imputation", "scaler", "scoring", "min_games", "k")}
    core["clusters"] = [{k: c[k] for k in ("id", "name", "family", "description", "centre_scaled", "centre")}
                        for c in model["clusters"]]
    assert hashlib.sha256(json.dumps(core, sort_keys=True).encode()).hexdigest() == V200_SCORING_SHA256


def test_atypical_threshold_is_the_training_95th_percentile(model):
    q = model["training_distance_quantiles"]
    assert len(q) == 101 and q == sorted(q)
    assert model["atypical_distance_threshold"] == pytest.approx(q[95])
    assert model["atypical"]["percentile"] == 95 and model["atypical"]["training_players"] == 3333
    assert model["atypical"]["flagged_share_of_training"] == pytest.approx(0.05, abs=0.002)


def test_a_bad_threshold_is_refused(model, tmp_path):
    for bad in ({"atypical_distance_threshold": -1}, {"training_distance_quantiles": [1.0, 0.5] + [2.0] * 99}):
        data = {**json.loads(json.dumps(model)), **bad}
        path = tmp_path / "m.json"
        path.write_text(json.dumps(data))
        with pytest.raises(ValueError):
            archetypes.load_model(path)
