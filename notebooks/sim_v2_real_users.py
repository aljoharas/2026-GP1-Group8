"""Assign real users with model v1 and candidate v2 (Step 5). Local only: needs DATABASE_URL.

Read-only: the session is opened with readonly=True and every transaction is rolled back.
Same data path as the /archetype endpoint (archetypes.load_manual_logs -> build_games).
Users with >= 5 manual-log games. Output (anonymised, no ids): notebooks/sim_v2/real_users.csv

Run from the repo root with the recommender venv:
    backend/recommender/.venv/bin/python notebooks/sim_v2_real_users.py
"""
import json
import sys
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetypes  # noqa: E402
import wrapped  # noqa: E402
from db import get_connection  # noqa: E402

V1 = archetypes.load_model(REPO / "models" / "archetype_model.json")
V2 = archetypes.load_model(REPO / "models" / "archetype_model_v2.json")
RESULTS = REPO / "notebooks" / "sim_v2"
match = json.loads((RESULTS / "results.json").read_text())["v1_vs_v2"]["v2_name_by_match"]


def main():
    conn = get_connection()
    conn.set_session(readonly=True, autocommit=False)
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT user_id, COUNT(DISTINCT game_id) FROM library_entries
            WHERE source = %s AND logged_at IS NOT NULL AND status <> ALL(%s)
            GROUP BY user_id HAVING COUNT(DISTINCT game_id) >= %s
        """, (wrapped.WRAPPED_SOURCE, list(wrapped.EXCLUDED_STATUSES), V1["min_games"]))
        uids = sorted(u for u, _ in cur.fetchall())
        cur.close()
        rows = []
        for n, uid in enumerate(uids, start=1):
            logs = archetypes.load_manual_logs(conn, uid)
            ids = sorted(int(g) for g in logs["game_id"].unique())
            games, _ = archetypes.build_games(logs, wrapped.load_game_genres(conn, ids),
                                              archetypes.load_achievement_list_sizes(conn, ids))
            a, b = archetypes.archetype_response(games, V1), archetypes.archetype_response(games, V2)
            if a["archetype"] is None:
                continue
            v2_id = int(b["archetype"].rsplit(" ", 1)[-1])
            v2_as_v1 = match[str(v2_id)]
            rows.append({
                "user": f"user {n}", "games": a["games_played"],
                "v1 archetype": a["archetype"], "v1 %": a["scores"][0]["percent"],
                "v2 cluster": b["archetype"], "v2 cluster ≈ v1": v2_as_v1, "v2 %": b["scores"][0]["percent"],
                "changed": v2_as_v1 != a["archetype"],
            })
        conn.rollback()
    finally:
        conn.close()
    out = pd.DataFrame(rows)
    out.to_csv(RESULTS / "real_users.csv", index=False)
    print(out.to_string(index=False))


if __name__ == "__main__":
    main()
