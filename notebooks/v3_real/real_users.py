"""Step 5.3: the real Loadout users (>= 5 manual-log games) with the served 2.0.0 model and with
the v3 k = 6 model (main run: 7 features, refitted scaler). Read-only session; same data path as
/archetype. Anonymised output: notebooks/v3_real/real_users.csv

    backend/recommender/.venv/bin/python notebooks/v3_real/real_users.py
(run after the notebook has written notebooks/v3_real/model_v3_k6.json)
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetypes  # noqa: E402
import wrapped  # noqa: E402
from archetype_features import compute_features  # noqa: E402
from db import get_connection  # noqa: E402

SERVED = archetypes.load_model()
V3 = json.loads((HERE / "model_v3_k6.json").read_text())


def v3_assign(features: dict) -> tuple[str, float, float]:
    """(matched name, distance to nearest, distance to second) in v3's scaled space."""
    x = np.array([V3["imputation"][f] if features[f] is None else features[f] for f in V3["features"]], dtype=float)
    z = (x - np.array(V3["scaler"]["mean"])) / np.array(V3["scaler"]["scale"])
    C = np.array([c["centre_scaled"] for c in V3["clusters"]])
    d = np.sqrt(((C - z) ** 2).sum(axis=1))
    order = np.argsort(d)
    return V3["clusters"][int(order[0])]["matched_served_name"], float(d[order[0]]), float(d[order[1]])


def main():
    conn = get_connection()
    conn.set_session(readonly=True, autocommit=False)
    rows = []
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT user_id FROM library_entries
            WHERE source = %s AND logged_at IS NOT NULL AND status <> ALL(%s)
            GROUP BY user_id HAVING COUNT(DISTINCT game_id) >= %s ORDER BY user_id
        """, (wrapped.WRAPPED_SOURCE, list(wrapped.EXCLUDED_STATUSES), SERVED["min_games"]))
        uids = [r[0] for r in cur.fetchall()]
        cur.close()
        for n, uid in enumerate(uids, 1):
            logs = archetypes.load_manual_logs(conn, uid)
            ids = sorted(int(g) for g in logs["game_id"].unique())
            games, _ = archetypes.build_games(logs, wrapped.load_game_genres(conn, ids),
                                              archetypes.load_achievement_list_sizes(conn, ids))
            served = archetypes.archetype_response(games, SERVED)
            v3_name, d1, d2 = v3_assign(compute_features(games))
            rows.append({"user": f"user {n}", "games": len(games),
                         "served 2.0.0": f"{served['archetype']} {served['scores'][0]['percent']}%",
                         "v3 k=6 (matched name)": v3_name, "v3 distance nearest / second": f"{d1:.2f} / {d2:.2f}",
                         "differs": v3_name != served["archetype"]})
        conn.rollback()
    finally:
        conn.close()
    out = pd.DataFrame(rows)
    out.to_csv(HERE / "real_users.csv", index=False)
    print(out.to_string(index=False))


if __name__ == "__main__":
    main()
