"""Tests for notebooks/v3_real/v3_real.py on small hand-made data (no Steam files needed).

    pytest notebooks/v3_real
"""
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import v3_real as V  # noqa: E402

M, E = 0.6, 2.0


# --- Betas -------------------------------------------------------------------------------

def test_mixture_beta_matches_mean_and_variance():
    betas = [(8, 2), (2, 6)]
    a, b, m, v = V.mixture_beta(betas)
    # mixture of means 0.8 and 0.25 → 0.525
    assert m == pytest.approx(0.525)
    assert a / (a + b) == pytest.approx(m)
    assert a * b / ((a + b) ** 2 * (a + b + 1)) == pytest.approx(v)
    # the mixture is wider than either component
    assert v > max(x * y / ((x + y) ** 2 * (x + y + 1)) for x, y in betas)


def test_population_betas_have_the_persona_mixture_means():
    comp = np.mean([a / (a + b) for a, b in (p["completion_beta"] for p in V.sim.PERSONAS.values())])
    tro = np.mean([a / (a + b) for a, b in (p["trophy_beta"] for p in V.sim.PERSONAS.values())])
    assert V.COMPLETION_BETA[2] == pytest.approx(comp)
    assert V.TROPHY_BETA[2] == pytest.approx(tro)


def test_shifted_beta_keeps_the_variance():
    a, b = V.shifted_beta(V.COMPLETION_BETA, 0.1)
    v = V.COMPLETION_BETA[3]
    assert a / (a + b) == pytest.approx(V.COMPLETION_BETA[2] + 0.1)
    assert a * b / ((a + b) ** 2 * (a + b + 1)) == pytest.approx(v)
    with pytest.raises(ValueError):
        V.beta_from_moments(0.5, 0.3)


# --- Vectorised rules match v2's scalar ones ------------------------------------------------

def test_vectorised_rules_match_v2():
    rs = np.linspace(0, 5, 101)
    assert V.finish_factor(rs) == pytest.approx([V.sim2.finish_factor(r) for r in rs])
    for completed in (False, True):
        got = V.trophy_progress(rs, np.full(len(rs), completed), M, E)
        assert got == pytest.approx([V.sim2.trophy_progress(r, completed, M, E) for r in rs])


# --- Hash uniforms --------------------------------------------------------------------------

def test_uniforms_are_deterministic_and_keyed():
    a = V.uniforms(42, ["P1", "P2", "P3"], "x")
    assert np.array_equal(a, V.uniforms(42, ["P1", "P2", "P3"], "x"))
    assert np.array_equal(a[[0, 2]], V.uniforms(42, ["P1", "P3"], "x")), "a row's draw ignores the others"
    assert not np.array_equal(a, V.uniforms(43, ["P1", "P2", "P3"], "x"))
    big = V.uniforms(1, [f"P{i}" for i in range(20000)], "u")
    assert big.min() > 0 and big.max() < 1 and abs(big.mean() - 0.5) < 0.01


# --- Base building and simulation on a toy dataset -----------------------------------------

def _toy():
    cat = pd.DataFrame({
        "appid": [1, 2, 3], "name": ["Story", "Arena", "Puzzle"],
        "genres": ["RPG", "Action;Shooter", "Puzzle"], "is_online": [False, True, False],
        "is_multiplayer_only": [False, True, False], "achievement_count": [10, 0, 20],
        "typical_length_h": [20.0, 5.0, np.nan],
    }).set_index("appid")
    cat["genre_list"] = cat["genres"].str.split(";")
    matches = pd.DataFrame({"game": ["Story", "Arena", "Arena - Multiplayer", "Puzzle"], "appid": [1, 2, 2, 3]})
    rows = []
    for u in ("u1", "u2"):
        for title, h in [("Story", 40), ("Arena", 100), ("Arena - Multiplayer", 50), ("Puzzle", 1),
                         ("Indie A", 3), ("Indie B", 2), ("Indie C", 0.5)]:
            rows.append({"user_id": u, "game": title, "hours": h * (2 if u == "u2" else 1)})
    rows.append({"user_id": "u3", "game": "Story", "hours": 5})  # too few games
    return cat, matches, pd.DataFrame(rows)


def test_build_base_merges_same_game_titles_and_anonymises():
    cat, matches, plays = _toy()
    g, anon, cap = V.build_base(plays, cat, matches)
    assert set(anon) == {"u1", "u2"} and set(g["pid"]) == {"P0001", "P0002"}
    assert "user_id" not in g.columns
    u1 = g[g["pid"] == "P0001"]
    assert len(u1) == 6, "Arena and Arena - Multiplayer are one game"
    arena = u1[u1["key"] == "app:2"].iloc[0]
    assert arena["hours"] == pytest.approx(min(150, cap)) and arena["mp_only"] and arena["is_online"]
    indie = u1[~u1["matched"]]
    assert len(indie) == 3 and all(len(x) == 0 for x in indie["genres"]) and (indie["achievement_count"] == 0).all()
    assert indie["typical_length_h"].isna().all()


def test_build_base_exclusion_refilters_users():
    cat, matches, plays = _toy()
    _, anon, _ = V.build_base(plays, cat, matches)
    g, _, _ = V.build_base(plays, cat, matches, exclude_titles=("Story", "Puzzle"), anon=anon)
    assert g.empty, "both users drop below 5 games"
    g2, _, _ = V.build_base(plays, cat, matches, exclude_titles=("Puzzle",), anon=anon)
    assert set(g2["pid"]) == {"P0001", "P0002"} and (g2.groupby("pid").size() == 5).all()


def test_simulation_respects_the_rules():
    cat, matches, plays = _toy()
    g, _, _ = V.build_base(plays, cat, matches)
    for seed in range(30):
        sg, pl = V.simulate(g, seed, V.SimConfig(), median_length=3.8)
        assert (sg["trophies_unlocked"] <= sg["trophies_available"]).all()
        full = (sg["trophies_available"] > 0) & (sg["trophies_unlocked"] == sg["trophies_available"])
        assert (sg.loc[full, "completed"]).all() and (sg.loc[full, "r"] >= 1 + E).all()
        assert (sg.loc[~sg["matched"], "trophies_available"] == 0).all()
        assert pl["months"].between(6, 12).all()
    # unmatched and no-length games use the median length
    sg, _ = V.simulate(g, 0, V.SimConfig(), median_length=3.8)
    puzzle = sg[sg["key"] == "app:3"].iloc[0]
    assert puzzle["r"] == pytest.approx(puzzle["hours"] / 3.8)


def test_engagement_zero_removes_the_z_shift():
    cat, matches, plays = _toy()
    g, _, _ = V.build_base(plays, cat, matches)
    _, pl = V.simulate(g, 1, V.SimConfig(engagement=0.0), 3.8)
    assert pl["p"].to_numpy() == pytest.approx(pl["p_base"].to_numpy())
    _, pl1 = V.simulate(g, 1, V.SimConfig(), 3.8)
    assert pl1.loc["P0002", "z"] > 0 > pl1.loc["P0001", "z"]
    assert pl1.loc["P0002", "p"] > pl1.loc["P0002", "p_base"]


def test_features_use_the_shared_function_except_online_share():
    cat, matches, plays = _toy()
    g, _, _ = V.build_base(plays, cat, matches)
    sg, pl = V.simulate(g, 5, V.SimConfig(activity=True), 3.8)
    X = V.features(sg, pl, V.SimConfig(activity=True))
    assert list(X.columns) == V.FEATURES_ACTIVITY
    u1 = sg[sg["pid"] == "P0001"]
    # online share over matched games only: Arena 150 (capped) of 40 + 150 + 1 matched hours
    assert X.loc["P0001", "online_share"] == pytest.approx(150 / 191)
    assert V.online_share_app_rule(sg).loc["P0001"] == pytest.approx(150 / u1["hours"].sum())
    assert X.loc["P0001", "log_games_played"] == pytest.approx(math.log(6))
    tot = u1["hours"].sum()
    assert X.loc["P0001", "log_activity"] == pytest.approx(math.log1p(tot / pl.loc["P0001", "months"]))
    assert list(V.features(sg, pl, V.SimConfig()).columns) == V.FEATURES_MAIN
