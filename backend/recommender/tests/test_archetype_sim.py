"""
Tests for archetype_sim: Steam preparation on a tiny hand-made CSV and the
generator's shape, ranges and reproducibility. No real Steam file needed.

Run from recommender/:  pytest
"""

import numpy as np
import pytest

import archetype_sim as sim
from archetype_features import FEATURE_NAMES, compute_features

CALIBRATION = {
    "cap": 900.0,
    "hours": np.sort(np.concatenate([np.linspace(0.1, 50, 900), np.linspace(50, 900, 100)])),
    "library_sizes": np.array([5, 6, 8, 12, 20, 35, 60]),
}


@pytest.fixture(scope="module")
def players():
    return sim.generate_players(CALIBRATION, n_per_persona=20, mix_share=0.25, seed=7)


def test_load_steam_plays_keeps_play_rows_with_hours_and_sums_them(tmp_path):
    csv = tmp_path / "steam.csv"
    csv.write_text(
        '1,"Dota 2",purchase,1.0,0\n'
        '1,"Dota 2",play,10.0,0\n'
        '1,"Dota 2",play,2.5,0\n'      # same user+game again → summed
        '1,"Portal",play,0,0\n'        # 0 hours → dropped
        '2,"Portal",play,3.0,0\n'
    )
    plays = sim.load_steam_plays(str(csv))
    got = {(r.user_id, r.game): r.hours for r in plays.itertuples()}
    assert got == {(1, "Dota 2"): 12.5, (2, "Portal"): 3.0}


def test_steam_calibration_caps_hours_and_keeps_users_with_five_games(tmp_path):
    rows = [f'1,"G{i}",play,{h},0' for i, h in enumerate([1, 2, 3, 4, 5000])]  # 5 games
    rows += [f'{u},"G0",play,1,0' for u in range(2, 200)]                       # 1 game each
    csv = tmp_path / "steam.csv"
    csv.write_text("\n".join(rows) + "\n")
    cal = sim.steam_calibration(sim.load_steam_plays(str(csv)))
    assert list(cal["library_sizes"]) == [5]
    assert cal["hours"].max() == pytest.approx(cal["cap"])
    assert cal["cap"] < 5000


def test_population_size_and_labels(players):
    # 20 per persona = 100 pure; mixed are 25% of everyone → 33
    assert len(players) == 133
    labels = [p["persona"] for p in players]
    for name in sim.PERSONA_NAMES:
        assert labels.count(name) == 20
    mixed = [l for l in labels if l.startswith("mixed:")]
    assert len(mixed) == 33
    for label in mixed:
        a, b = label[len("mixed:"):].split("+")
        assert a != b and {a, b} <= set(sim.PERSONA_NAMES)


def test_same_seed_same_players_different_seed_different_players(players):
    assert sim.generate_players(CALIBRATION, n_per_persona=20, seed=7) == players
    assert sim.generate_players(CALIBRATION, n_per_persona=20, seed=8) != players


def test_games_are_compute_features_input(players):
    for p in players:
        features = compute_features(p["games"])
        assert features is not None and list(features) == FEATURE_NAMES
        for g in p["games"]:
            assert g["latest_status"] in ("playing", "completed", "paused")
            assert (g["latest_status"] == "completed") == g["completed"]
            assert 1 <= len(g["genres"]) <= sim.MAX_GENRES_PER_GAME
            assert len(set(g["genres"])) == len(g["genres"])
            assert set(g["genres"]) <= set(sim.GENRES)
            assert 0 <= g["trophies_unlocked"] <= g["trophies_available"]
            assert g["months"]


def test_pure_players_respect_their_persona_ranges(players):
    for p in players:
        if p["persona"].startswith("mixed:"):
            continue
        cfg = sim.PERSONAS[p["persona"]]
        low, high = cfg["library_size"]
        assert low <= len(p["games"]) <= high
        months = {m for g in p["games"] for m in g["months"]}
        assert cfg["active_months"][0] <= len(months) <= cfg["active_months"][1]


def test_devotee_has_one_dominant_game(players):
    devotees = [p for p in players if p["persona"] == "devotee"]
    top_low = np.quantile(CALIBRATION["hours"], sim.PERSONAS["devotee"]["top_game_quantiles"][0])
    for p in devotees:
        hours = sorted((g["hours"] for g in p["games"]), reverse=True)
        assert hours[0] >= top_low > hours[1]
