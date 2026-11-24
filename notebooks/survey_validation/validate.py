"""Steps 2-4: score the 20 survey respondents with the FROZEN served model (2.0.0) and, for comparison,
the frozen v1 (1.0.0). All rules fixed before scoring (see report.md). Nothing is retrained or changed.

    backend/recommender/.venv/bin/python notebooks/survey_validation/validate.py
Writes notebooks/survey_validation/tables/ and results.json. IDs R01-R20, no timestamps.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import survey_features as S  # noqa: E402

REPO = S.REPO
TAB = HERE / "tables"
TAB.mkdir(exist_ok=True)
FN = S.FEATURE_NAMES
SERVED = S.archetypes.load_model()
V1 = S.archetypes.load_model(REPO / "models" / "archetype_model_v1.json")
assert SERVED["version"] == "2.0.0" and V1["version"] == "1.0.0"
NAMES = [c["name"] for c in SERVED["clusters"]]
ORDER = ["Completionist", "Explorer", "Competitor", "Casual", "Devotee", "The Main"]
SELF_ORDER = list(S.SELF)

# --- Inputs ---------------------------------------------------------------------------------
survey = pd.read_csv(REPO / "data" / "Gaming_Habits_Survey.csv")
resp = pd.DataFrame({
    "respondent": [f"R{i + 1:02d}" for i in range(len(survey))],
    "months": survey.iloc[:, 2].astype(int).to_numpy(),
    "frequency": survey.iloc[:, 3].to_numpy(),
    "self": survey.iloc[:, -1].to_numpy(),
}).set_index("respondent")
matches = pd.read_csv(HERE / "survey_game_matches.csv").sort_values(["respondent", "slot"])
alts = pd.read_csv(HERE / "survey_game_matches_alternatives.csv")


def with_alternatives(m: pd.DataFrame) -> pd.DataFrame:
    m = m.copy()
    for a in alts.itertuples(index=False):
        sel = (m["respondent"] == a.respondent) & (m["raw name"].str.strip().str.casefold() == a._1)
        assert sel.sum() == 1, (a.respondent, a._1)
        m.loc[sel, ["matched title", "genres", "online"]] = [a._3, a.genres, bool(a.online)]
    return m


def feature_table(m: pd.DataFrame, games_played="missing", activity="computed") -> pd.DataFrame:
    rows = {}
    for rid, entries in m.groupby("respondent", sort=True):
        rows[rid] = S.features(S.respondent_games(entries, resp.loc[rid, "months"]), games_played, activity)
    return pd.DataFrame(rows).T[FN]


def scores(X: pd.DataFrame, model: dict) -> dict:
    return {rid: S.score({f: (None if pd.isna(v) else float(v)) for f, v in X.loc[rid].items()}, model) for rid in X.index}


def evaluate(sc: dict, ids: list[str]) -> dict:
    labels = [S.SELF[resp.loc[r, "self"]] for r in ids]
    top1 = S.summary([{sc[r]["top1"]} for r in ids], labels)
    top2 = S.summary([set(sc[r]["top2"]) for r in ids], labels)
    return {"top1": top1, "top2": top2}


def confusion(sc: dict, ids: list[str]) -> pd.DataFrame:
    t = pd.crosstab(pd.Series([S.SELF_SHORT[resp.loc[r, "self"]] for r in ids], name="self-description"),
                    pd.Series([sc[r]["top1"] for r in ids], name="model top archetype"))
    return t.reindex(index=[S.SELF_SHORT[s] for s in SELF_ORDER], columns=ORDER, fill_value=0)


ALL = list(resp.index)
R = {"n": len(ALL), "self_counts": resp["self"].map(S.SELF_SHORT).value_counts().to_dict(),
     "frequency": resp["frequency"].value_counts().to_dict(), "months": resp["months"].value_counts().sort_index().to_dict()}

# --- Main analysis -----------------------------------------------------------------------------
X_main = feature_table(matches)
X_main.round(4).to_csv(TAB / "features_main.csv")
sc_served = scores(X_main, SERVED)
sc_v1 = scores(X_main, V1)
R["main_served"] = evaluate(sc_served, ALL)
R["main_v1"] = evaluate(sc_v1, ALL)
conf_served, conf_v1 = confusion(sc_served, ALL), confusion(sc_v1, ALL)
conf_served.to_csv(TAB / "confusion_served.csv")
conf_v1.to_csv(TAB / "confusion_v1.csv")
R["confusion_served"] = conf_served.to_dict("index")
R["confusion_v1"] = conf_v1.to_dict("index")

per = []
for r in ALL:
    s, v = sc_served[r], sc_v1[r]
    lab = S.SELF[resp.loc[r, "self"]]
    per.append({
        "respondent": r, "self-description": S.SELF_SHORT[resp.loc[r, "self"]], "mapped": " / ".join(sorted(lab)),
        "top 3 (2.0.0)": ", ".join(f"{n} {p}%" for n, p in s["ranked"][:3]),
        "blend": f"{s['blend']['primary']}, with a touch of {s['blend']['secondary']}" if s["blend"] else "",
        "top-1 agrees": s["top1"] in lab, "top-2 agrees": bool(set(s["top2"]) & lab),
        "v1 top": v["top1"], "v1 top-1 agrees": v["top1"] in lab,
    })
per = pd.DataFrame(per).set_index("respondent")
per.to_csv(TAB / "per_respondent.csv")
R["per_respondent"] = per.reset_index().to_dict("records")

# --- Sensitivities (decided before scoring) ----------------------------------------------------
sens_rows, changes = [], {}
variants = {
    "games played = 5": (feature_table(matches, games_played="five"), ALL),
    "activity = training mean": (feature_table(matches, activity="mean"), ALL),
    "alternative matches": (feature_table(with_alternatives(matches)), ALL),
    "without R13": (X_main.drop(index="R13"), [r for r in ALL if r != "R13"]),
}
main_row = {"variant": "main", "n": 20, **{f"{k} {m}": R["main_served"][k][m] for k in ("top1", "top2")
                                          for m in ("agree", "share", "wilson_lo", "wilson_hi", "chance", "p_value")}}
sens_rows.append(main_row)
for name, (X, ids) in variants.items():
    sc = scores(X, SERVED)
    ev = evaluate(sc, ids)
    sens_rows.append({"variant": name, "n": len(ids), **{f"{k} {m}": ev[k][m] for k in ("top1", "top2")
                                                         for m in ("agree", "share", "wilson_lo", "wilson_hi", "chance", "p_value")}})
    changes[name] = [{"respondent": r, "main top": sc_served[r]["top1"], "variant top": sc[r]["top1"],
                      "main top-1 agrees": sc_served[r]["top1"] in S.SELF[resp.loc[r, "self"]],
                      "variant top-1 agrees": sc[r]["top1"] in S.SELF[resp.loc[r, "self"]],
                      "main top 3": ", ".join(f"{n} {p}%" for n, p in sc_served[r]["ranked"][:3]),
                      "variant top 3": ", ".join(f"{n} {p}%" for n, p in sc[r]["ranked"][:3])}
                     for r in ids if sc[r]["top1"] != sc_served[r]["top1"] or sc[r]["top2"] != sc_served[r]["top2"]]
sens = pd.DataFrame(sens_rows).set_index("variant")
sens.round(4).to_csv(TAB / "sensitivities.csv")
R["sensitivities"] = sens.reset_index().to_dict("records")
R["sensitivity_changes"] = changes

# --- Step 4: descriptive comparisons -----------------------------------------------------------
X_report = X_main.copy()   # survey values as computed (games played is the form cap: 5 for everyone)
X_report["log_games_played"] = feature_table(matches, games_played="five")["log_games_played"]


def iqr(x: pd.Series) -> str:
    x = x.dropna()
    return f"{x.median():.2f} ({x.quantile(0.25):.2f}–{x.quantile(0.75):.2f})"


# v2-core training players (the served model's population), cached
v2_path = TAB / "v2core_training_features.csv"
if not v2_path.exists():
    sys.path.insert(0, str(REPO / "notebooks"))
    import archetype_v2_lib as L
    _, cal, CAT, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")
    P2 = L.sim2.generate_players(cal, CAT, 500, L.MIX_SHARE, 42, L.sim2.rules_variant(rule5_trophy_hunters={"on": False}))
    L.features(P2).to_csv(v2_path, index=False)
X2 = pd.read_csv(v2_path)
v1_path = TAB / "v1_training_features.csv"
if not v1_path.exists():
    sys.path.insert(0, str(REPO / "notebooks"))
    import archetype_v2_lib as L
    _, cal, _, _, _ = L.load_inputs(REPO / "data" / "steam-200k.csv", REPO / "data" / "steam_catalogue.csv")
    L.features(L.players_v1(cal)).to_csv(v1_path, index=False)
X1 = pd.read_csv(v1_path)
# Real Steam players (v3), the five real features: read from the v3 branch's committed table
try:
    raw = subprocess.run(["git", "-C", str(REPO), "show",
                          "feature/archetype-v3-real:notebooks/v3_real/tables/feature_distributions_v3_v2core.csv"],
                         capture_output=True, text=True, check=True).stdout
    from io import StringIO
    v3 = pd.read_csv(StringIO(raw))
    v3 = v3[v3["population"] == "v3 (real)"].set_index("feature")
except subprocess.CalledProcessError:
    v3 = None
REAL5 = ["log_games_played", "log_hours_per_game", "top_game_share", "genre_diversity", "online_share"]
dist = pd.DataFrame({
    "survey (n = 20)": {f: iqr(X_report[f]) for f in FN},
    "v2-core training (3,333)": {f: iqr(X2[f]) for f in FN},
    "v1 training (667)": {f: iqr(X1[f]) for f in FN},
    "real Steam, v3 (2,408)": {f: (f"{v3.loc[f, 'p50']:.2f} ({v3.loc[f, 'p25']:.2f}–{v3.loc[f, 'p75']:.2f})"
                                   if v3 is not None and f in REAL5 else "–") for f in FN},
}).loc[FN]
dist.to_csv(TAB / "feature_distributions.csv")
R["distributions"] = dist.to_dict("index")
closer = {}
for f in ["completion_rate", "trophy_rate", "log_activity"]:
    s = X_report[f].median()
    d2, d1 = abs(X2[f].median() - s), abs(X1[f].median() - s)
    closer[f] = {"survey median": float(s), "v2-core median": float(X2[f].median()), "v1 median": float(X1[f].median()),
                 "closer": "v2-core" if d2 < d1 else "v1"}
R["closer_simulation"] = closer

# Trophy-hunter check: unfinished games with >= 51% trophies
m = matches.copy()
m["unfinished"] = m["status"] != "Finished"
m["high_trophies"] = m["trophies"].isin(["51–75%", "76–99%", "100%"])
hunt = m[m["unfinished"] & m["high_trophies"]]
hunt_kind = np.where(hunt["multiplayer-only"], "multiplayer-only", np.where(hunt["online"], "online (not multiplayer-only)", "offline"))
per_resp_offline = hunt[~hunt["online"]].groupby("respondent").size()
R["trophy_hunter"] = {
    "unfinished games with >= 51% trophies": int(len(hunt)),
    "by kind": pd.Series(hunt_kind).value_counts().to_dict(),
    "respondents with >= 2 such offline games": int((per_resp_offline >= 2).sum()),
    "those respondents": per_resp_offline[per_resp_offline >= 2].index.tolist(),
    "unfinished games overall": int(m["unfinished"].sum()),
}

# Completionist vs Competitor among respondents the served model assigns either
cc = [r for r in ALL if sc_served[r]["top1"] in ("Completionist", "Competitor")]
cc_tab = pd.DataFrame({r: {"model top": sc_served[r]["top1"], "self-description": S.SELF_SHORT[resp.loc[r, "self"]],
                           "completion_rate": X_main.loc[r, "completion_rate"], "trophy_rate": X_main.loc[r, "trophy_rate"],
                           "online_share": X_main.loc[r, "online_share"]} for r in cc}).T
cc_tab.to_csv(TAB / "completionist_vs_competitor.csv")
grp = cc_tab.groupby("model top")[["completion_rate", "trophy_rate", "online_share"]].agg(lambda s: pd.to_numeric(s).median())
R["completionist_vs_competitor"] = {"rows": cc_tab.reset_index().rename(columns={"index": "respondent"}).to_dict("records"),
                                    "medians": grp.to_dict("index")}
R["served_top_counts"] = pd.Series([sc_served[r]["top1"] for r in ALL]).value_counts().to_dict()
R["blends"] = int(sum(1 for r in ALL if sc_served[r]["blend"]))
(HERE / "results.json").write_text(json.dumps(R, indent=2, default=lambda o: o.item() if hasattr(o, "item") else str(o)) + "\n")

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 70)
print("served 2.0.0:", json.dumps(R["main_served"], indent=1))
print("v1 1.0.0:", json.dumps(R["main_v1"], indent=1))
print(conf_served.to_string())
print(conf_v1.to_string())
print(per.to_string())
print(sens.round(3).to_string())
print(json.dumps(changes, indent=1))
print(dist.to_string())
print(json.dumps(closer, indent=1))
print(json.dumps(R["trophy_hunter"], indent=1))
print(cc_tab.to_string())
print(grp.round(3).to_string())
print("served top counts", R["served_top_counts"], "| blends", R["blends"])
