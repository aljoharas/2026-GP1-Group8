"""v2.2: recalibrate v2-core's engagement LEVELS on the 20 survey responses (calibration data).

Fixed method (decided before fitting):
- Targets: median and IQR of log hours per game, trophy rate, online share, completion rate and
  activity over the 20 responses (survey_validation's conversion, tables/features_main.csv).
  Games played stays Steam-based.
- Rules 1-4, the catalogue, the personas and their ordering are kept. Five level parameters, each
  ONE common shift across personas:
    s_hours   added to every persona's per-game hours quantile range (and the devotee's top-game
              range), clipped to [0.001, 0.999]
    s_comp    completion propensity Beta mean, logit scale (concentration a + b kept)
    s_trophy  trophy propensity Beta mean, logit scale (concentration kept)
    s_online  P(online) Beta mean, logit scale (concentration kept)
    s_months  whole months added to the active-months range, clipped to 1..12
- Objective: sum over the five features of ((pooled simulated median - target median) / target IQR)^2.
- Search: coordinate descent over fixed grids on a 100-per-persona population (seed 42, common
  random numbers), then the result is checked at 500 per persona.

    python notebooks/v2_2/calibrate.py search      -> notebooks/v2_2/calibration.json
"""
from __future__ import annotations

import contextlib
import copy
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "notebooks"))
import archetype_v2_lib as L  # noqa: E402

CORE = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})
TARGET_FEATURES = ["log_hours_per_game", "trophy_rate", "online_share", "completion_rate", "log_activity"]
SHIFT_NAMES = ["s_hours", "s_comp", "s_trophy", "s_online", "s_months"]
ZERO = {k: 0.0 for k in SHIFT_NAMES}
GRIDS = {
    "s_hours": np.round(np.arange(0.0, 0.651, 0.05), 3),
    "s_comp": np.round(np.arange(-1.0, 3.01, 0.25), 3),
    "s_trophy": np.round(np.arange(-1.0, 4.01, 0.25), 3),
    "s_online": np.round(np.arange(-1.0, 4.01, 0.25), 3),
    "s_months": np.arange(0, 9, 1),
}


def targets() -> dict:
    X = pd.read_csv(REPO / "notebooks" / "survey_validation" / "tables" / "features_main.csv", index_col=0)
    out = {}
    for f in TARGET_FEATURES:
        x = X[f].dropna()
        out[f] = {"median": float(x.median()), "p25": float(x.quantile(0.25)), "p75": float(x.quantile(0.75)),
                  "iqr": float(x.quantile(0.75) - x.quantile(0.25)), "n": int(len(x))}
    return out


def _shift_beta(ab, s):
    a, b = ab
    k = a + b
    m = a / k
    m2 = 1 / (1 + math.exp(-(math.log(m / (1 - m)) + s)))
    return (m2 * k, (1 - m2) * k)


def _shift_range(r, s, lo=0.001, hi=0.999):
    a, b = min(max(r[0] + s, lo), hi), min(max(r[1] + s, lo), hi)
    if b <= a:
        a = max(lo, b - 0.001)
    return (a, b)


def shifted_personas(shifts: dict) -> dict:
    """A copy of the persona table with the five common shifts applied."""
    P = copy.deepcopy(L.sim.PERSONAS)
    for p in P.values():
        p["hours_quantiles"] = _shift_range(p["hours_quantiles"], shifts["s_hours"])
        if p["top_game_quantiles"] is not None:
            p["top_game_quantiles"] = _shift_range(p["top_game_quantiles"], shifts["s_hours"])
        p["completion_beta"] = _shift_beta(p["completion_beta"], shifts["s_comp"])
        p["trophy_beta"] = _shift_beta(p["trophy_beta"], shifts["s_trophy"])
        p["online_beta"] = _shift_beta(p["online_beta"], shifts["s_online"])
        lo, hi = p["active_months"]
        s = int(round(shifts["s_months"]))
        p["active_months"] = (min(max(lo + s, 1), 12), min(max(hi + s, 1), 12))
    return P


@contextlib.contextmanager
def personas_patched(P: dict):
    """Run the unchanged v2 generator with a different persona table."""
    old = L.sim2.PERSONAS
    L.sim2.PERSONAS = P
    try:
        yield
    finally:
        L.sim2.PERSONAS = old


_INPUTS = {}


def inputs():
    if not _INPUTS:
        _, cal, CAT, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")
        _INPUTS.update(cal=cal, CAT=CAT)
    return _INPUTS["cal"], _INPUTS["CAT"]


def simulate(shifts: dict, n_per_persona: int = 100, seed: int = 42):
    cal, CAT = inputs()
    with personas_patched(shifted_personas(shifts)):
        return L.sim2.generate_players(cal, CAT, n_per_persona, L.MIX_SHARE, seed, CORE)


def summary(X: pd.DataFrame) -> dict:
    return {f: {"median": float(X[f].median()), "p25": float(X[f].quantile(0.25)), "p75": float(X[f].quantile(0.75)),
                "iqr": float(X[f].quantile(0.75) - X[f].quantile(0.25))} for f in TARGET_FEATURES}


def objective(X: pd.DataFrame, T: dict) -> float:
    return float(sum(((X[f].median() - T[f]["median"]) / T[f]["iqr"]) ** 2 for f in TARGET_FEATURES))


def search(n_per_persona: int = 100, rounds: int = 4, log=print) -> dict:
    T = targets()
    cache = {}

    def f(sh):
        key = tuple(round(float(sh[k]), 4) for k in SHIFT_NAMES)
        if key not in cache:
            cache[key] = objective(L.features(simulate(sh, n_per_persona)), T)
        return cache[key]

    best = dict(ZERO)
    best_val = f(best)
    log(f"start {best} -> {best_val:.4f}")
    for r in range(rounds):
        improved = False
        for name in SHIFT_NAMES:
            vals = {v: f({**best, name: float(v)}) for v in GRIDS[name]}
            v_best = min(vals, key=vals.get)
            if vals[v_best] < best_val - 1e-9:
                best, best_val, improved = {**best, name: float(v_best)}, vals[v_best], True
            log(f"round {r + 1} {name} -> {best[name]} | objective {best_val:.4f} | evals {len(cache)}")
        if not improved:
            break
    return {"targets": T, "shifts": best, "objective_search": best_val, "evaluations": len(cache),
            "search_population_per_persona": n_per_persona}


if __name__ == "__main__":
    if sys.argv[1:] == ["search"]:
        t = time.time()
        res = search(log=lambda m: print(m, flush=True))
        X0 = L.features(simulate(ZERO, 500))
        X1 = L.features(simulate(res["shifts"], 500))
        res["check_500_per_persona"] = {"v2_core": summary(X0), "v2_2": summary(X1),
                                        "objective_v2_core": objective(X0, res["targets"]),
                                        "objective_v2_2": objective(X1, res["targets"])}
        res["seconds"] = time.time() - t
        (HERE / "calibration.json").write_text(json.dumps(res, indent=2) + "\n")
        print(json.dumps(res, indent=1))
