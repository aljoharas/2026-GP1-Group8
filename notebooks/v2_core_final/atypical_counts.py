"""How many are flagged atypical by model 2.0.1: the training players, the 20 survey respondents
(survey_validation's main conversion), and the real app users with >= 5 manual-log games
(read-only, the endpoint's own path). Anonymised output: notebooks/v2_core_final/atypical_counts.json

    backend/recommender/.venv/bin/python notebooks/v2_core_final/atypical_counts.py   (needs DATABASE_URL)
"""
import json
import os
import sys
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "notebooks" / "survey_validation"))
sys.path.insert(0, str(REPO / "backend" / "recommender"))
os.chdir(REPO / "backend" / "recommender")   # db.py reads .env from here

import archetypes  # noqa: E402
import survey_features as S  # noqa: E402
import wrapped  # noqa: E402
from db import get_connection  # noqa: E402

M = archetypes.load_model()
assert M["version"] == "2.0.1"
out = {"threshold": M["atypical_distance_threshold"], "training_flagged_share": M["atypical"]["flagged_share_of_training"]}

# Survey respondents (main conversion: games played = training mean, activity computed)
X = pd.read_csv(REPO / "notebooks" / "survey_validation" / "tables" / "features_main.csv", index_col=0)
rows = []
for rid, f in X.iterrows():
    feats = {k: (None if pd.isna(v) else float(v)) for k, v in f.items()}
    z = archetypes.scale_features(S.fill_missing(feats, M), M)
    flag, pct = archetypes.atypical_check(z, M)
    rows.append({"respondent": rid, "top": S.score(feats, M)["top1"], "atypical": flag, "distance_percentile": pct})
survey = pd.DataFrame(rows)
out["survey"] = {"n": len(survey), "flagged": int(survey["atypical"].sum()), "rows": survey.to_dict("records"),
                 "distance_percentile_median": float(survey["distance_percentile"].median())}

# Real app users, read-only
conn = get_connection()
conn.set_session(readonly=True, autocommit=False)
real = []
try:
    cur = conn.cursor()
    cur.execute("""
        SELECT user_id FROM library_entries
        WHERE source = %s AND logged_at IS NOT NULL AND status <> ALL(%s)
        GROUP BY user_id HAVING COUNT(DISTINCT game_id) >= %s ORDER BY user_id
    """, (wrapped.WRAPPED_SOURCE, list(wrapped.EXCLUDED_STATUSES), M["min_games"]))
    uids = [r[0] for r in cur.fetchall()]
    cur.close()
    for n, uid in enumerate(uids, 1):
        logs = archetypes.load_manual_logs(conn, uid)
        ids = sorted(int(g) for g in logs["game_id"].unique())
        games, _ = archetypes.build_games(logs, wrapped.load_game_genres(conn, ids),
                                          archetypes.load_achievement_list_sizes(conn, ids))
        b = archetypes.archetype_response(games, M)
        real.append({"user": f"user {n}", "games": len(games), "archetype": b["archetype"],
                     "top %": b["scores"][0]["percent"], "atypical": b["atypical"],
                     "distance_percentile": b["distance_percentile"], "blend": b["blend"]})
    conn.rollback()
finally:
    conn.close()
real = pd.DataFrame(real)
out["real_users"] = {"n": len(real), "flagged": int(real["atypical"].sum()), "rows": real.to_dict("records")}
(HERE / "atypical_counts.json").write_text(json.dumps(out, indent=2, default=str) + "\n")
print(json.dumps({k: v for k, v in out.items() if k not in ("survey", "real_users")}, indent=1))
print(survey.to_string(index=False))
print(real.to_string(index=False))
