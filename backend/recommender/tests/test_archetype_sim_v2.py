"""Simulator v2: the rule functions and the generator's hard constraints, on a tiny
hand-made catalogue (no Kaggle file needed)."""
import math

import numpy as np
import pandas as pd
import pytest

import archetype_sim as sim
import archetype_sim_v2 as v2
from archetype_features import compute_features

M, E = 0.6, 2.0


# --- Rule 2: trophy accrual --------------------------------------------------------

@pytest.mark.parametrize("r, completed, expected", [
    (0.0, False, 0.0),
    (0.5, False, 0.3),          # halfway through the story: half of M
    (1.0, False, 0.6),          # end of the main story: M
    (1.0, True, 0.6),
    (2.5, False, 0.6),          # unfinished: never past M, however long
    (2.0, True, 0.6 + 0.4 / 2),  # half of the extra E x length hours
    (3.0, True, 1.0),           # completed and r = 1 + E: the full list
    (9.0, True, 1.0),
])
def test_trophy_progress(r, completed, expected):
    assert v2.trophy_progress(r, completed, M, E) == pytest.approx(expected)


def test_trophy_progress_is_monotone_and_full_only_when_allowed():
    for m in (0.4, 0.6, 0.8):
        for completed in (False, True):
            rs = np.linspace(0, 5, 501)
            p = [v2.trophy_progress(r, completed, m, E) for r in rs]
            assert all(b >= a for a, b in zip(p, p[1:]))
            for r, value in zip(rs, p):
                if value >= 1.0:
                    assert completed and r >= 1 + E


def test_trophy_progress_m_is_the_story_share():
    for m in (0.4, 0.8):
        assert v2.trophy_progress(1.0, True, m, E) == pytest.approx(m)
        assert v2.trophy_progress(1.0 + E, True, m, E) == pytest.approx(1.0)


# --- Rule 1: finishing needs hours ---------------------------------------------------

def test_finish_factor_edges():
    assert v2.finish_factor(0.5) == pytest.approx(0.05)
    assert v2.finish_factor(1.5) == pytest.approx(0.95)
    assert v2.finish_factor(0.49) < 0.05
    assert v2.finish_factor(0) == 0.0
    rs = np.linspace(0.01, 5, 300)
    f = [v2.finish_factor(r) for r in rs]
    assert all(b > a for a, b in zip(f, f[1:]))


# --- Generator on a tiny catalogue ----------------------------------------------------

def _catalogue():
    rows = []
    appid = 1
    for genre in sim.GENRES:
        for online, mp_only in ((False, False), (True, False), (True, True)):
            rows.append({"appid": appid, "name": f"g{appid}", "genres": genre, "is_online": online,
                         "is_multiplayer_only": mp_only, "achievement_count": 20 if appid % 4 else 0,
                         "typical_length_h": float(2 + appid % 30), "steam200k_players": 1 + appid % 7})
            appid += 1
    cat = pd.DataFrame(rows)
    cat["genre_list"] = cat["genres"].str.split(";")
    hours = {1: np.sort(np.linspace(0.5, 80, 50)), 2: np.sort(np.linspace(0.1, 5, 30))}
    return v2.Catalogue(cat, hours)


def _calibration():
    rng = np.random.default_rng(0)
    return {"cap": 500.0, "hours": np.sort(rng.lognormal(1.5, 1.4, 5000).clip(max=500)),
            "library_sizes": np.arange(5, 60)}


@pytest.fixture(scope="module")
def players():
    log = {}
    out = v2.generate_players(_calibration(), _catalogue(), n_per_persona=40, seed=3, log=log)
    out_log = log
    return out, out_log


def test_generator_shape_and_features(players):
    out, log = players
    assert len(out) == 40 * 5 + round(200 * 0.25 / 0.75)
    for p in out:
        assert compute_features(p["games"]) is not None
        ids = [g["_appid"] for g in p["games"]]
        assert len(ids) == len(set(ids)), "a library never holds the same game twice"
    assert sum(log["hours_source"].values()) == sum(len(p["games"]) for p in out)
    assert log["hours_source"]["game"] > 0


def test_generator_hard_constraints(players):
    out, _ = players
    for p in out:
        for g in p["games"]:
            n, k = g["trophies_available"], g["trophies_unlocked"]
            assert 0 <= k <= n
            if n and k == n:
                assert g["completed"] and g["_r"] >= 1 + E
            if g["completed"]:
                assert g["latest_status"] == "completed"
            else:
                assert g["latest_status"] in ("playing", "paused")


def test_generator_is_deterministic_and_v1_default_unchanged():
    cal, cat = _calibration(), _catalogue()
    a = v2.generate_players(cal, cat, n_per_persona=5, seed=1)
    b = sim.generate_players(cal, n_per_persona=5, seed=1, version=2, catalogue=cat)
    assert [p["games"] for p in a] == [p["games"] for p in b]
    v1a = sim.generate_players(cal, n_per_persona=5, seed=1)
    v1b = sim.generate_players(cal, n_per_persona=5, seed=1, version=1)
    assert [p["games"] for p in v1a] == [p["games"] for p in v1b]
    assert "_appid" not in v1a[0]["games"][0]


def test_switching_a_rule_off_keeps_the_random_stream():
    """Common random numbers: rule 5 off changes trophies only, not games or hours."""
    cal, cat = _calibration(), _catalogue()
    on = v2.generate_players(cal, cat, n_per_persona=10, seed=2)
    off = v2.generate_players(cal, cat, n_per_persona=10, seed=2,
                              rules=v2.rules_variant(rule5_trophy_hunters={"on": False}))
    for a, b in zip(on, off):
        assert [(g["_appid"], g["hours"], g["completed"]) for g in a["games"]] == \
               [(g["_appid"], g["hours"], g["completed"]) for g in b["games"]]
    assert not any(p["hunter"] for p in off)
    assert math.isclose(v2.RULES["rule2_trophies_follow_hours"]["story_share_M"], 0.6)
